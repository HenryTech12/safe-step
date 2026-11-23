import 'hazard_classes.dart';

/// One detection. Box is normalised to the (rotated, un-letterboxed) camera frame: 0..1.
class Detection {
  const Detection(this.cls, this.score, this.x1, this.y1, this.x2, this.y2);
  final HazardClass cls;
  final double score;
  final double x1, y1, x2, y2;

  double get cx => (x1 + x2) / 2;
  double get width => x2 - x1;
  double get height => y2 - y1;

  @override
  String toString() =>
      'Detection(${cls.wire} ${score.toStringAsFixed(2)} [${x1.toStringAsFixed(2)},${y1.toStringAsFixed(2)},${x2.toStringAsFixed(2)},${y2.toStringAsFixed(2)}])';
}

/// How the model input was letterboxed from the frame, to map boxes back.
class Letterbox {
  const Letterbox({required this.scale, required this.padX, required this.padY, required this.srcW, required this.srcH});
  final double scale; // model px per source px
  final double padX, padY; // model px
  final int srcW, srcH;
}
