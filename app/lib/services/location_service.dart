import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

class Fix {
  const Fix(this.lat, this.lng, this.accuracy, this.heading);
  final double lat;
  final double lng;
  final double accuracy;
  final double? heading;

  Map<String, Object?> toJson() =>
      {'lat': lat, 'lng': lng, 'accuracy': accuracy, if (heading != null) 'heading': heading};
}

/// GPS + compass (from BlindSpot's main.dart). Emits a [Fix] on every position change
/// (3 m filter) and at least every [heartbeat], so the agent's tracker stays fresh.
class LocationService {
  LocationService({this.heartbeat = const Duration(seconds: 3)});

  final Duration heartbeat;
  final _fixes = StreamController<Fix>.broadcast();
  StreamSubscription<Position>? _pos;
  StreamSubscription<CompassEvent>? _compass;
  Timer? _timer;
  Position? _last;
  double? _heading;

  Stream<Fix> get fixes => _fixes.stream;
  Fix? get last => _last == null ? null : _toFix(_last!);

  Future<bool> start() async {
    if (_pos != null) return true;
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return false;

    _compass = FlutterCompass.events?.listen((e) {
      if (e.heading != null) _heading = (e.heading! + 360) % 360;
    });
    _pos = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
        intervalDuration: const Duration(seconds: 2),
      ),
    ).listen((p) {
      _last = p;
      _emit();
    }, onError: (Object e) => debugPrint('location error: $e'));
    _timer = Timer.periodic(heartbeat, (_) => _emit());
    return true;
  }

  void _emit() {
    final p = _last;
    if (p != null && !_fixes.isClosed) _fixes.add(_toFix(p));
  }

  Fix _toFix(Position p) => Fix(p.latitude, p.longitude, p.accuracy, _heading);

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _pos?.cancel();
    _pos = null;
    await _compass?.cancel();
    _compass = null;
  }

  Future<void> dispose() async {
    await stop();
    await _fixes.close();
  }
}
