import 'dart:typed_data';

import 'detection.dart';

/// A camera frame in Android's YUV_420_888 layout (as delivered by the camera plugin).
class YuvFrame {
  const YuvFrame({
    required this.width,
    required this.height,
    required this.y,
    required this.u,
    required this.v,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
  });
  final int width, height;
  final Uint8List y, u, v;
  final int yRowStride, uvRowStride, uvPixelStride;
}

/// Size of the frame after rotating by [rotation] degrees (0/90/180/270).
(int, int) rotatedSize(int w, int h, int rotation) => rotation % 180 == 0 ? (w, h) : (h, w);

Letterbox letterboxFor(int srcW, int srcH, int size) {
  final scale = size / (srcW > srcH ? srcW : srcH);
  return Letterbox(
    scale: scale,
    padX: (size - srcW * scale) / 2,
    padY: (size - srcH * scale) / 2,
    srcW: srcW,
    srcH: srcH,
  );
}

/// Converts a YUV frame into the model's NHWC float32 input (size x size x 3, 0..1),
/// rotating so "up" in the tensor is up in the world, and letterboxing with grey.
(Float32List, Letterbox) yuvToInput(YuvFrame f, {required int rotation, int size = 640}) {
  final (rw, rh) = rotatedSize(f.width, f.height, rotation);
  final lb = letterboxFor(rw, rh, size);
  final out = Float32List(size * size * 3)..fillRange(0, size * size * 3, 114 / 255);
  final inv = 1 / lb.scale;
  final x0 = lb.padX.round(), y0 = lb.padY.round();
  final x1 = (lb.padX + rw * lb.scale).round(), y1 = (lb.padY + rh * lb.scale).round();
  for (var ty = y0; ty < y1; ty++) {
    final ry = ((ty - lb.padY) * inv).floor().clamp(0, rh - 1);
    for (var tx = x0; tx < x1; tx++) {
      final rx = ((tx - lb.padX) * inv).floor().clamp(0, rw - 1);
      // rotated (rx, ry) -> sensor (sx, sy)
      int sx, sy;
      switch (rotation % 360) {
        case 90:
          sx = ry;
          sy = f.height - 1 - rx;
        case 180:
          sx = f.width - 1 - rx;
          sy = f.height - 1 - ry;
        case 270:
          sx = f.width - 1 - ry;
          sy = rx;
        default:
          sx = rx;
          sy = ry;
      }
      final yy = f.y[sy * f.yRowStride + sx];
      final uvi = (sy >> 1) * f.uvRowStride + (sx >> 1) * f.uvPixelStride;
      final uu = f.u[uvi] - 128;
      final vv = f.v[uvi] - 128;
      final r = (yy + 1.402 * vv).clamp(0, 255);
      final g = (yy - 0.344136 * uu - 0.714136 * vv).clamp(0, 255);
      final b = (yy + 1.772 * uu).clamp(0, 255);
      final o = (ty * size + tx) * 3;
      out[o] = r / 255;
      out[o + 1] = g / 255;
      out[o + 2] = b / 255;
    }
  }
  return (out, lb);
}

/// RGB bytes (row-major, 3 bytes per pixel) -> model input. Used by demo mode (JPEG frames).
(Float32List, Letterbox) rgbToInput(Uint8List rgb, int w, int h, {int size = 640}) {
  final lb = letterboxFor(w, h, size);
  final out = Float32List(size * size * 3)..fillRange(0, size * size * 3, 114 / 255);
  final inv = 1 / lb.scale;
  final x0 = lb.padX.round(), y0 = lb.padY.round();
  final x1 = (lb.padX + w * lb.scale).round(), y1 = (lb.padY + h * lb.scale).round();
  for (var ty = y0; ty < y1; ty++) {
    final sy = ((ty - lb.padY) * inv).floor().clamp(0, h - 1);
    for (var tx = x0; tx < x1; tx++) {
      final sx = ((tx - lb.padX) * inv).floor().clamp(0, w - 1);
      final i = (sy * w + sx) * 3;
      final o = (ty * size + tx) * 3;
      out[o] = rgb[i] / 255;
      out[o + 1] = rgb[i + 1] / 255;
      out[o + 2] = rgb[i + 2] / 255;
    }
  }
  return (out, lb);
}
