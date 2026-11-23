import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/hazard/detection.dart';
import 'package:safestep/hazard/hazard_classes.dart';
import 'package:safestep/hazard/hazard_policy.dart';
import 'package:safestep/hazard/local_phrases.dart';
import 'package:safestep/hazard/preprocess.dart';
import 'package:safestep/hazard/yolo_decoder.dart';

Detection det(HazardClass c, double cx, double bottom, {double w = 0.2, double h = 0.3, double s = 0.8}) =>
    Detection(c, s, cx - w / 2, bottom - h, cx + w / 2, bottom);

void main() {
  group('yolo decoder', () {
    test('maps COCO ids, un-letterboxes boxes and applies NMS', () {
      const anchors = 3, channels = 84;
      final out = Float32List(channels * anchors);
      void put(int a, double cx, double cy, double w, double h, int cls, double score) {
        out[a] = cx;
        out[anchors + a] = cy;
        out[2 * anchors + a] = w;
        out[3 * anchors + a] = h;
        out[(4 + cls) * anchors + a] = score;
      }

      // source 480x640 (portrait) letterboxed into 640: scale 1, padX 80
      final lb = letterboxFor(480, 640, 640);
      put(0, 320, 500, 100, 200, 3, 0.9); // motorcycle -> okada
      put(1, 322, 502, 100, 200, 3, 0.7); // duplicate, suppressed
      put(2, 100, 100, 50, 50, 40, 0.9); // wine glass: not a SafeStep class
      final dets = decodeYolo(out, channels: channels, anchors: anchors, lb: lb);
      expect(dets, hasLength(1));
      final d = dets.single;
      expect(d.cls, HazardClass.okada);
      expect(d.cx, closeTo((320 - 80) / 480, 1e-6));
      expect(d.y2, closeTo(600 / 640, 1e-6));
    });

    test('fine-tuned model with 10 classes uses SafeStep ids directly', () {
      expect(classForModel(0, 10), HazardClass.openGutter);
      expect(classForModel(2, 10), HazardClass.openManhole);
      expect(classForModel(3, 80), HazardClass.okada);
      expect(classForModel(40, 80), isNull);
    });
  });

  group('preprocess', () {
    test('rotates a 90° sensor frame upright', () {
      // 4x2 sensor frame; only pixel (3,0) is bright.
      final y = Uint8List(8);
      y[3] = 255;
      final f = YuvFrame(width: 4, height: 2, y: y, u: Uint8List(8)..fillRange(0, 8, 128), v: Uint8List(8)..fillRange(0, 8, 128), yRowStride: 4, uvRowStride: 2, uvPixelStride: 1);
      final (t, lb) = yuvToInput(f, rotation: 90, size: 4);
      expect((lb.srcW, lb.srcH), (2, 4));
      // clockwise rotation: sensor (3,0) -> upright (1,3), letterbox padX = 1
      final bright = <int>[];
      for (var i = 0; i < 16; i++) {
        if (t[i * 3] > 0.9) bright.add(i);
      }
      expect(bright, [3 * 4 + 1 + 1]);
    });
  });

  group('hazard policy', () {
    final t0 = DateTime(2027, 1, 1);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('only warns about the walking path', () {
      final p = HazardPolicy();
      expect(p.classify(det(HazardClass.person, 0.1, 0.9)), isNull); // far left edge
      expect(p.classify(det(HazardClass.person, 0.5, 0.3)), isNull); // upper frame / far away
      final a = p.classify(det(HazardClass.person, 0.7, 0.9))!;
      expect((a.side, a.band), (Side.right, DistanceBand.near));
      expect(p.classify(det(HazardClass.person, 0.5, 0.6)), isNull); // far minor: ignored
      expect(p.classify(det(HazardClass.okada, 0.5, 0.6))!.band, DistanceBand.far); // far critical: kept
    });

    test('needs 2 of 3 frames, then debounces repeats', () {
      final p = HazardPolicy();
      final d = [det(HazardClass.pole, 0.5, 0.9)];
      expect(p.onFrame(d, at(0)), isNull);
      expect(p.onFrame(d, at(300))?.cls, HazardClass.pole);
      expect(p.onFrame(d, at(600)), isNull); // same pole again: debounced
      expect(p.onFrame(d, at(8700))?.cls, HazardClass.pole); // after the cooldown
    });

    test('critical beats minor, and silencing never silences critical', () {
      final p = HazardPolicy()..minorSilenced = true;
      final frame = [det(HazardClass.person, 0.5, 0.95), det(HazardClass.okada, 0.3, 0.7)];
      p.onFrame(frame, at(0));
      final a = p.onFrame(frame, at(300));
      expect(a?.cls, HazardClass.okada);
      expect(a?.side, Side.left);
      final minorOnly = HazardPolicy()..minorSilenced = true;
      final m = [det(HazardClass.person, 0.5, 0.95)];
      minorOnly.onFrame(m, at(0));
      expect(minorOnly.onFrame(m, at(300)), isNull);
    });

    test('a hazard that gets closer is announced again sooner', () {
      final p = HazardPolicy();
      final far = [det(HazardClass.openGutter, 0.5, 0.6)];
      final near = [det(HazardClass.openGutter, 0.5, 0.92)];
      p.onFrame(far, at(0));
      expect(p.onFrame(far, at(200))?.band, DistanceBand.far);
      p.onFrame(near, at(1000));
      expect(p.onFrame(near, at(2300))?.band, DistanceBand.near);
    });
  });

  group('offline phrases', () {
    test('matches commands in several languages', () {
      expect(matchLocalCommand('Stop warning me!'), LocalCommand.quietMinor);
      expect(matchLocalCommand('abeg stop to dey warn me'), LocalCommand.quietMinor);
      expect(matchLocalCommand('warnings only please'), LocalCommand.hazardMode);
      expect(matchLocalCommand('Na only warning I want'), LocalCommand.hazardMode);
      expect(matchLocalCommand('gargadi kawai'), LocalCommand.hazardMode);
      expect(matchLocalCommand('take me to the market'), LocalCommand.navigationMode);
      expect(matchLocalCommand('say again'), LocalCommand.repeat);
      expect(matchLocalCommand('good morning'), isNull);
    });
  });
}
