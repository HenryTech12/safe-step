import 'dart:async';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'detection.dart';
import 'preprocess.dart';
import 'yolo_decoder.dart';

const String modelAsset = 'assets/models/yolov8n.tflite';
const int modelSize = 640;

/// Runs YOLOv8n TFLite on a long-lived worker isolate (pre-processing + inference), so the UI
/// thread never blocks. Frames arriving while the worker is busy are dropped: the detector
/// always looks at the newest frame. Works fully offline.
class HazardDetector {
  HazardDetector._(this._interpreter, this._send, this._replies, this._isolate);

  final Interpreter _interpreter;
  final SendPort _send;
  final ReceivePort _replies;
  final Isolate _isolate;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 0;
  bool _busy = false;

  /// Average inference+preprocess time, for the debug log and demo screen.
  double avgMs = 0;

  static Future<HazardDetector> load() async {
    final options = InterpreterOptions()..threads = 4;
    final interpreter = await Interpreter.fromAsset(modelAsset, options: options);
    final replies = ReceivePort();
    final isolate = await Isolate.spawn(_workerMain, (replies.sendPort, interpreter.address));
    final ready = Completer<SendPort>();
    late final HazardDetector det;
    replies.listen((msg) {
      if (msg is SendPort) {
        ready.complete(msg);
      } else if (msg is (int, Object?)) {
        det._pending.remove(msg.$1)?.complete(msg.$2);
      }
    });
    det = HazardDetector._(interpreter, await ready.future, replies, isolate);
    return det;
  }

  bool get busy => _busy;

  /// Detect on a camera frame. Returns null if the worker is still busy with the last one.
  Future<List<Detection>?> detectCamera(CameraImage image, int rotation) {
    if (_busy) return Future.value(null);
    final frame = YuvFrame(
      width: image.width,
      height: image.height,
      y: image.planes[0].bytes,
      u: image.planes[1].bytes,
      v: image.planes[2].bytes,
      yRowStride: image.planes[0].bytesPerRow,
      uvRowStride: image.planes[1].bytesPerRow,
      uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
    );
    return _run(_Job.detectYuv(frame, rotation)).then((r) => r as List<Detection>?);
  }

  /// Detect on RGB pixels (demo mode).
  Future<List<Detection>?> detectRgb(Uint8List rgb, int w, int h) {
    if (_busy) return Future.value(null);
    return _run(_Job.detectRgb(rgb, w, h)).then((r) => r as List<Detection>?);
  }

  /// JPEG of a camera frame, upright, max 768 px (for scene description).
  Future<Uint8List?> jpegFromCamera(CameraImage image, int rotation) {
    final frame = YuvFrame(
      width: image.width,
      height: image.height,
      y: Uint8List.fromList(image.planes[0].bytes),
      u: Uint8List.fromList(image.planes[1].bytes),
      v: Uint8List.fromList(image.planes[2].bytes),
      yRowStride: image.planes[0].bytesPerRow,
      uvRowStride: image.planes[1].bytesPerRow,
      uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
    );
    return _run(_Job.jpeg(frame, rotation), countsAsBusy: false).then((r) => r as Uint8List?);
  }

  Future<Object?> _run(_Job job, {bool countsAsBusy = true}) async {
    final id = _nextId++;
    final c = Completer<Object?>();
    _pending[id] = c;
    if (countsAsBusy) _busy = true;
    final sw = Stopwatch()..start();
    _send.send((id, job));
    try {
      return await c.future;
    } finally {
      if (countsAsBusy) {
        _busy = false;
        avgMs = avgMs == 0 ? sw.elapsedMilliseconds.toDouble() : avgMs * 0.9 + sw.elapsedMilliseconds * 0.1;
      }
    }
  }

  Future<void> dispose() async {
    _isolate.kill(priority: Isolate.immediate);
    _replies.close();
    _interpreter.close();
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(null);
    }
  }
}

class _Job {
  _Job.detectYuv(YuvFrame this.yuv, this.rotation)
      : kind = 0,
        rgb = null,
        w = 0,
        h = 0;
  _Job.detectRgb(Uint8List this.rgb, this.w, this.h)
      : kind = 1,
        yuv = null,
        rotation = 0;
  _Job.jpeg(YuvFrame this.yuv, this.rotation)
      : kind = 2,
        rgb = null,
        w = 0,
        h = 0;

  final int kind;
  final YuvFrame? yuv;
  final int rotation;
  final Uint8List? rgb;
  final int w, h;
}

void _workerMain((SendPort, int) args) {
  final (reply, address) = args;
  final port = ReceivePort();
  reply.send(port.sendPort);
  final interpreter = Interpreter.fromAddress(address);
  final outShape = interpreter.getOutputTensor(0).shape; // [1, 4 + C, N]
  final channels = outShape[1], anchors = outShape[2];
  final outBytes = Uint8List(channels * anchors * 4);

  port.listen((msg) {
    final (id, job) = msg as (int, _Job);
    try {
      if (job.kind == 2) {
        reply.send((id, _toJpeg(job.yuv!, job.rotation)));
        return;
      }
      final (input, lb) = job.kind == 0
          ? yuvToInput(job.yuv!, rotation: job.rotation, size: modelSize)
          : rgbToInput(job.rgb!, job.w, job.h, size: modelSize);
      interpreter.run(input.buffer.asUint8List(), outBytes);
      final dets = decodeYolo(outBytes.buffer.asFloat32List(), channels: channels, anchors: anchors, lb: lb);
      reply.send((id, dets));
    } catch (e) {
      debugPrint('detector worker error: $e');
      reply.send((id, null));
    }
  });
}

Uint8List _toJpeg(YuvFrame f, int rotation) {
  final rgb = img.Image(width: f.width, height: f.height);
  for (var y = 0; y < f.height; y++) {
    for (var x = 0; x < f.width; x++) {
      final yy = f.y[y * f.yRowStride + x];
      final uvi = (y >> 1) * f.uvRowStride + (x >> 1) * f.uvPixelStride;
      final u = f.u[uvi] - 128, v = f.v[uvi] - 128;
      rgb.setPixelRgb(
        x,
        y,
        (yy + 1.402 * v).clamp(0, 255).toInt(),
        (yy - 0.344136 * u - 0.714136 * v).clamp(0, 255).toInt(),
        (yy + 1.772 * u).clamp(0, 255).toInt(),
      );
    }
  }
  var out = rotation == 0 ? rgb : img.copyRotate(rgb, angle: rotation);
  if (out.width > 768 || out.height > 768) {
    out = out.width >= out.height ? img.copyResize(out, width: 768) : img.copyResize(out, height: 768);
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: 80));
}
