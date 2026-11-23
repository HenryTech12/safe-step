import 'detection.dart';
import 'hazard_classes.dart';

enum Side { left, ahead, right }

enum DistanceBand { near, medium, far }

class HazardAlert {
  const HazardAlert(this.cls, this.side, this.band);
  final HazardClass cls;
  final Side side;
  final DistanceBand band;

  String get sideWire => side.name;
  String get bandWire => band.name;

  @override
  String toString() => 'HazardAlert(${cls.wire}, ${side.name}, ${band.name})';
}

/// Decides which detections deserve a spoken warning.
///
/// - Walking path only: box centre in the middle 60% horizontally and its bottom edge in
///   the lower part of the (upright) frame. Bottom edge ≈ where the object meets the ground,
///   so lower = closer.
/// - Must be seen in [confirmFrames] of the last [windowFrames] frames (kills flicker).
/// - Debounce: the same class on the same side isn't repeated within its cooldown, unless
///   it got closer. A global gap keeps alerts from stacking.
/// - Minor classes can be silenced; critical ones (open gutter, open manhole, okada) never.
class HazardPolicy {
  HazardPolicy({
    this.pathMinX = 0.2,
    this.pathMaxX = 0.8,
    this.minBottomY = 0.5,
    this.minHeight = 0.06,
    this.confirmFrames = 2,
    this.windowFrames = 3,
    this.criticalCooldown = const Duration(seconds: 4),
    this.minorCooldown = const Duration(seconds: 8),
    this.globalGap = const Duration(milliseconds: 1500),
    this.closerRepeatAfter = const Duration(seconds: 2),
  });

  final double pathMinX, pathMaxX, minBottomY, minHeight;
  final int confirmFrames, windowFrames;
  final Duration criticalCooldown, minorCooldown, globalGap, closerRepeatAfter;

  bool minorSilenced = false;

  final List<Set<String>> _recent = [];
  final Map<String, (DateTime, DistanceBand)> _lastAlert = {};
  DateTime? _lastAny;

  /// Feed one frame's detections; returns at most one alert (the most urgent).
  HazardAlert? onFrame(List<Detection> detections, DateTime now) {
    final candidates = <HazardAlert>[];
    for (final d in detections) {
      final a = classify(d);
      if (a != null) candidates.add(a);
    }

    _recent.add({for (final a in candidates) _key(a)});
    if (_recent.length > windowFrames) _recent.removeAt(0);

    final confirmed = candidates.where((a) {
      if (minorSilenced && !a.cls.critical) return false;
      final k = _key(a);
      return _recent.where((s) => s.contains(k)).length >= confirmFrames;
    }).toList()
      ..sort(_urgency);

    for (final a in confirmed) {
      if (_allowed(a, now)) {
        _lastAlert[_key(a)] = (now, a.band);
        _lastAny = now;
        return a;
      }
    }
    return null;
  }

  /// Path test + side + distance band for one detection, or null if not in the path.
  HazardAlert? classify(Detection d) {
    if (d.height < minHeight) return null;
    if (d.cx < pathMinX || d.cx > pathMaxX) return null;
    final bottom = d.y2;
    if (bottom < minBottomY) return null;
    final band = bottom >= 0.85
        ? DistanceBand.near
        : bottom >= 0.68
            ? DistanceBand.medium
            : DistanceBand.far;
    if (band == DistanceBand.far && !d.cls.critical) return null;
    final side = d.cx < 0.4
        ? Side.left
        : d.cx > 0.6
            ? Side.right
            : Side.ahead;
    return HazardAlert(d.cls, side, band);
  }

  void reset() {
    _recent.clear();
    _lastAlert.clear();
    _lastAny = null;
  }

  bool _allowed(HazardAlert a, DateTime now) {
    if (_lastAny != null && now.difference(_lastAny!) < globalGap && !a.cls.critical) return false;
    final last = _lastAlert[_key(a)];
    if (last == null) return true;
    final (at, band) = last;
    final since = now.difference(at);
    if (a.band.index < band.index && since >= closerRepeatAfter) return true; // got closer
    return since >= (a.cls.critical ? criticalCooldown : minorCooldown);
  }

  static String _key(HazardAlert a) => '${a.cls.wire}/${a.side.name}';

  static int _urgency(HazardAlert a, HazardAlert b) {
    if (a.cls.critical != b.cls.critical) return a.cls.critical ? -1 : 1;
    final band = a.band.index.compareTo(b.band.index);
    if (band != 0) return band;
    return a.side == Side.ahead ? -1 : (b.side == Side.ahead ? 1 : 0);
  }
}
