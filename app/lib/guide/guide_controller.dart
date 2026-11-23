import 'dart:async';

import 'package:flutter/foundation.dart';

import '../hazard/alert_player.dart';
import '../hazard/detector_service.dart';
import '../hazard/hazard_controller.dart';
import '../hazard/hazard_policy.dart';
import '../hazard/local_phrases.dart';
import '../l10n/strings.dart';
import '../models/app_mode.dart';
import '../models/language.dart';
import '../onboarding/onboarding_controller.dart' show LanguageRecognizer;
import '../services/foreground_service.dart';
import '../services/livekit_service.dart';
import '../services/location_service.dart';
import '../services/prefs_service.dart';

/// Everything the guide screen does, without widgets:
/// - hazard detection always on (camera → detector → policy → offline alert → hazard_event)
/// - voice agent via LiveKit, with automatic reconnect
/// - GPS to the agent's navigation tracker
/// - offline phrases (double tap while offline) so mode switching works without network
/// - gestures: double tap = talk (mic) / offline command, swipe down = mute agent voice,
///   long press = repeat
/// - foreground service so all of this continues with the screen off
class GuideController extends ChangeNotifier {
  GuideController({
    required this.prefs,
    required this.voice,
    required this.recognizer,
    LocationService? location,
  }) : location = location ?? LocationService();

  final PrefsService prefs;
  final LiveKitService voice;
  final LanguageRecognizer recognizer;
  final LocationService location;

  HazardController? hazards;
  AlertPlayer? _alerts;
  StreamSubscription<Fix>? _fixSub;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _disposed = false;
  bool _listeningOffline = false;

  late AppLanguage language = prefs.language;
  late AppMode mode = prefs.lastMode;
  bool agentVoiceMuted = false;
  bool hazardsAvailable = false;
  bool _modeChangedOffline = false;

  Strings get strings => Strings.of(language);
  bool get listeningOffline => _listeningOffline;

  Future<void> start() async {
    voice
      ..addListener(_onVoiceChanged)
      ..onModeFromAgent = _setModeFromAgent
      ..onWarningsFromAgent = (silenced) {
        hazards?.minorSilenced = silenced;
        notifyListeners();
      }
      ..savedPlaces = (() => prefs.savedPlaces)
      ..onPlaceSaved = (p) {
        prefs.setSavedPlaces([...prefs.savedPlaces.where((x) => x.name != p.name), p]);
      }
      ..onFrameRequest = _sendFrame;

    await GuidanceService.start(title: 'SafeStep', text: strings.modeHazard);

    await _startHazards();
    if (await location.start()) {
      _fixSub = location.fixes.listen(voice.publishFix);
    }
    await _connect();
  }

  Future<void> _startHazards() async {
    try {
      final alerts = await AlertPlayer.load();
      final detector = await HazardDetector.load();
      final h = HazardController(detector: detector, alerts: alerts, language: language);
      alerts
        ..duck = (() => voice.setAgentAudioMuted(true))
        ..unduck = (() => voice.setAgentAudioMuted(agentVoiceMuted));
      h.onAlert = _onHazardAlert;
      _alerts = alerts;
      hazards = h;
      hazardsAvailable = await h.start();
    } catch (e) {
      debugPrint('hazard detection unavailable: $e');
      hazardsAvailable = false;
    }
    notifyListeners();
  }

  void _onHazardAlert(HazardAlert a) {
    if (voice.isConnected) {
      voice.publishHazardEvent(hazardClass: a.cls.wire, side: a.sideWire, distanceBand: a.bandWire);
    }
  }

  // --- connection ---

  Future<void> _connect() async {
    await voice.connect(language: language, mode: mode);
    if (voice.isConnected) {
      _reconnectAttempt = 0;
      if (_modeChangedOffline) {
        _modeChangedOffline = false;
        await voice.publishModeFromPhone(mode);
      }
    }
  }

  void _onVoiceChanged() {
    final s = voice.status;
    if ((s == VoiceStatus.disconnected || s == VoiceStatus.failed) && !_disposed) {
      _scheduleReconnect();
    }
    notifyListeners();
  }

  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive ?? false) return;
    final seconds = [3, 6, 12, 24, 45, 60][_reconnectAttempt.clamp(0, 5)];
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      if (!_disposed && !voice.isConnected && !_listeningOffline) _connect();
    });
  }

  // --- modes ---

  void _setModeFromAgent(AppMode m) {
    mode = m;
    prefs.setLastMode(m);
    GuidanceService.start(title: 'SafeStep', text: m == AppMode.navigation ? strings.modeNavigation : strings.modeHazard);
    notifyListeners();
  }

  // --- gestures ---

  /// Double tap: online = mic on/off ("tap to talk"); offline = listen for a fixed phrase.
  Future<void> onDoubleTap() async {
    if (voice.isConnected) {
      await voice.setMicEnabled(!voice.micEnabled);
      notifyListeners();
      return;
    }
    await listenOfflineCommand();
  }

  /// Swipe down: mute/unmute the agent's voice. Hazard alerts still play.
  Future<void> onSwipeDown() async {
    agentVoiceMuted = !agentVoiceMuted;
    await voice.setAgentAudioMuted(agentVoiceMuted);
    await _alerts?.sayText(agentVoiceMuted ? strings.agentMuted : strings.agentUnmuted, language);
    notifyListeners();
  }

  /// Long press: repeat what the agent last said (online) or the last alert (offline).
  Future<void> onLongPress() async {
    if (voice.isConnected) {
      await voice.publishControl('repeat');
    } else {
      final a = hazards?.lastAlert;
      if (a != null) await _alerts?.play(a, language);
    }
  }

  // --- offline commands ---

  Future<void> listenOfflineCommand() async {
    if (_listeningOffline) return;
    _listeningOffline = true;
    notifyListeners();
    try {
      final heard = await recognizer.listen(const Duration(seconds: 4));
      await applyLocalCommand(matchLocalCommand(heard));
    } finally {
      _listeningOffline = false;
      notifyListeners();
      if (!voice.isConnected) _scheduleReconnect();
    }
  }

  Future<void> applyLocalCommand(LocalCommand? cmd) async {
    final s = strings;
    String reply;
    switch (cmd) {
      case LocalCommand.hazardMode:
        _setModeOffline(AppMode.hazardDetection);
        reply = s.hazardModeOn;
      case LocalCommand.navigationMode:
        reply = s.navNeedsNetwork; // routes need the network; hazard detection stays on
      case LocalCommand.quietMinor:
        hazards?.minorSilenced = true;
        reply = s.minorQuiet;
      case LocalCommand.allWarnings:
        hazards?.minorSilenced = false;
        reply = s.allWarningsOn;
      case LocalCommand.repeat:
        final a = hazards?.lastAlert;
        if (a != null) await _alerts?.play(a, language);
        return;
      case null:
        reply = s.notUnderstood;
    }
    await _alerts?.sayText(reply, language);
    notifyListeners();
  }

  void _setModeOffline(AppMode m) {
    if (mode == m) return;
    mode = m;
    prefs.setLastMode(m);
    _modeChangedOffline = true;
  }

  // --- scene description ---

  Future<void> _sendFrame(String requestId) async {
    final jpeg = await hazards?.captureJpeg();
    if (jpeg != null) await voice.sendFrame(requestId, jpeg);
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _fixSub?.cancel();
    voice.removeListener(_onVoiceChanged);
    location.dispose();
    hazards?.detector.dispose();
    hazards?.dispose();
    _alerts?.dispose();
    GuidanceService.stop();
    super.dispose();
  }
}
