import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../models/language.dart';
import 'alert_player.dart';
import 'detection.dart';
import 'detector_service.dart';
import 'hazard_policy.dart';

/// Camera → on-device detector → walking-path policy → offline alert. Always on while the
/// guide screen is active, in both modes. [onAlert] fires after an alert has played, so the
/// caller can send `hazard_event` to the agent.
class HazardController extends ChangeNotifier {
  HazardController({
    required this.detector,
    required this.alerts,
    required this.language,
    HazardPolicy? policy,
  }) : policy = policy ?? HazardPolicy();

  final HazardDetector detector;
  final AlertPlayer alerts;
  final HazardPolicy policy;
  AppLanguage language;

  void Function(HazardAlert alert)? onAlert;

  CameraController? _cam;
  int _rotation = 90;
  bool _running = false;
  Completer<Uint8List?>? _jpegWanted;
  List<Detection> lastDetections = const [];
  HazardAlert? lastAlert;

  bool get running => _running;
  CameraController? get camera => _cam;

  set minorSilenced(bool v) => policy.minorSilenced = v;
  bool get minorSilenced => policy.minorSilenced;

  Future<bool> start() async {
    if (_running) return true;
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final cam = CameraController(back, ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await cam.initialize();
      _rotation = back.sensorOrientation; // portrait phone: rotate the sensor image upright
      _cam = cam;
      _running = true;
      await cam.startImageStream(_onImage);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('HazardController.start failed: $e');
      return false;
    }
  }

  void _onImage(CameraImage image) {
    final want = _jpegWanted;
    if (want != null) {
      _jpegWanted = null;
      detector.jpegFromCamera(image, _rotation).then(want.complete, onError: (_) => want.complete(null));
    }
    if (detector.busy) return; // drop frames while the worker is busy
    detector.detectCamera(image, _rotation).then((dets) {
      if (dets != null) handleDetections(dets, DateTime.now());
    });
  }

  /// Policy + alert for one frame's detections (also used by demo mode).
  void handleDetections(List<Detection> dets, DateTime now) {
    lastDetections = dets;
    final alert = policy.onFrame(dets, now);
    if (alert != null) {
      lastAlert = alert;
      alerts.play(alert, language).then((played) {
        if (played) onAlert?.call(alert);
      });
    }
    notifyListeners();
  }

  /// Grabs the next camera frame as JPEG (scene description).
  Future<Uint8List?> captureJpeg({Duration timeout = const Duration(seconds: 3)}) {
    if (!_running) return Future.value(null);
    final c = Completer<Uint8List?>();
    _jpegWanted = c;
    return c.future.timeout(timeout, onTimeout: () => null);
  }

  Future<void> stop() async {
    _running = false;
    final cam = _cam;
    _cam = null;
    if (cam != null) {
      try {
        await cam.stopImageStream();
      } catch (_) {}
      await cam.dispose();
    }
    policy.reset();
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
