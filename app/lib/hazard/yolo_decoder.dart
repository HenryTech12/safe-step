import 'dart:math' as math;
import 'dart:typed_data';

import 'detection.dart';
import 'hazard_classes.dart';

/// Decodes YOLOv8 output [1, 4 + C, N] (cx, cy, w, h in model pixels, then class scores)
/// into SafeStep detections, with per-class NMS.
List<Detection> decodeYolo(
  Float32List out, {
  required int channels,
  required int anchors,
  required Letterbox lb,
  double confThreshold = 0.35,
  double iouThreshold = 0.45,
  int maxDetections = 20,
}) {
  final numClasses = channels - 4;
  final cands = <_Cand>[];
  for (var a = 0; a < anchors; a++) {
    var best = -1;
    var bestScore = confThreshold;
    for (var c = 0; c < numClasses; c++) {
      final s = out[(4 + c) * anchors + a];
      if (s > bestScore) {
        bestScore = s;
        best = c;
      }
    }
    if (best < 0) continue;
    final cls = classForModel(best, numClasses);
    if (cls == null) continue;
    final cx = out[a], cy = out[anchors + a], w = out[2 * anchors + a], h = out[3 * anchors + a];
    // model px -> source px -> normalised
    final x1 = ((cx - w / 2 - lb.padX) / lb.scale / lb.srcW).clamp(0.0, 1.0);
    final y1 = ((cy - h / 2 - lb.padY) / lb.scale / lb.srcH).clamp(0.0, 1.0);
    final x2 = ((cx + w / 2 - lb.padX) / lb.scale / lb.srcW).clamp(0.0, 1.0);
    final y2 = ((cy + h / 2 - lb.padY) / lb.scale / lb.srcH).clamp(0.0, 1.0);
    if (x2 <= x1 || y2 <= y1) continue;
    cands.add(_Cand(Detection(cls, bestScore, x1, y1, x2, y2)));
  }
  cands.sort((a, b) => b.d.score.compareTo(a.d.score));
  final kept = <Detection>[];
  for (final c in cands) {
    if (kept.length >= maxDetections) break;
    if (kept.any((k) => k.cls == c.d.cls && iou(k, c.d) > iouThreshold)) continue;
    kept.add(c.d);
  }
  return kept;
}

double iou(Detection a, Detection b) {
  final ix = math.max(0.0, math.min(a.x2, b.x2) - math.max(a.x1, b.x1));
  final iy = math.max(0.0, math.min(a.y2, b.y2) - math.max(a.y1, b.y1));
  final inter = ix * iy;
  final union = a.width * a.height + b.width * b.height - inter;
  return union <= 0 ? 0 : inter / union;
}

class _Cand {
  _Cand(this.d);
  final Detection d;
}
