import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import '../models/app_mode.dart';
import '../models/language.dart';
import 'protocol.dart';
import 'token_client.dart';

enum VoiceStatus { disconnected, connecting, waitingForAgent, listening, thinking, speaking, failed }

/// Owns the LiveKit room: connects via the token server, tracks the agent's state and
/// exchanges data messages. Ported from BlindSpot's VoiceService without in-app JWT signing.
class LiveKitService extends ChangeNotifier {
  LiveKitService({required TokenClient tokenClient, required this.installId}) : _tokens = tokenClient;

  final TokenClient _tokens;
  final String Function() installId;

  Room? _room;
  EventsListener<RoomEvent>? _listener;

  VoiceStatus _status = VoiceStatus.disconnected;
  VoiceStatus get status => _status;

  bool _micEnabled = true;
  bool get micEnabled => _micEnabled;

  bool get isConnected => _room != null;

  /// Called when the agent switches mode (set_mode tool).
  void Function(AppMode mode)? onModeFromAgent;

  /// Called when the agent quiets or restores minor warnings.
  void Function(bool minorSilenced)? onWarningsFromAgent;

  Future<void> connect({required AppLanguage language, required AppMode mode}) async {
    if (_room != null || _status == VoiceStatus.connecting) return;
    _setStatus(VoiceStatus.connecting);
    try {
      final ticket = await _tokens.fetch(language: language, mode: mode, installId: installId());
      final room = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
      _listen(room);
      await room.connect(
        ticket.url,
        ticket.token,
        fastConnectOptions: FastConnectOptions(microphone: const TrackOption(enabled: true)),
      );
      _room = room;
      _micEnabled = true;
      try {
        await room.startAudio();
      } catch (e) {
        debugPrint('LiveKitService.startAudio: $e');
      }
      _setStatus(_agentStatus(room) ?? VoiceStatus.waitingForAgent);
    } catch (e) {
      debugPrint('LiveKitService.connect failed: $e');
      await _teardown();
      _setStatus(VoiceStatus.failed);
    }
  }

  Future<void> disconnect() async {
    await _teardown();
    _setStatus(VoiceStatus.disconnected);
  }

  Future<void> setMicEnabled(bool enabled) async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    await lp.setMicrophoneEnabled(enabled);
    _micEnabled = enabled;
    notifyListeners();
  }

  /// Tell the agent the phone changed mode by itself (e.g. an offline phrase).
  Future<void> publishModeFromPhone(AppMode mode) =>
      _publish(topicMode, {'mode': mode.wire, 'source': 'phone'});

  /// Phase 3: sent after the on-device alert has played.
  Future<void> publishHazardEvent({
    required String hazardClass,
    required String side,
    required String distanceBand,
  }) =>
      _publish(topicHazard, {'class': hazardClass, 'side': side, 'distance_band': distanceBand});

  Future<void> _publish(String topic, Map<String, Object?> payload) async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    try {
      await lp.publishData(encodeMessage(payload), reliable: true, topic: topic);
    } catch (e) {
      debugPrint('LiveKitService.publish($topic) failed: $e');
    }
  }

  void _listen(Room room) {
    _listener?.dispose();
    _listener = room.createListener()
      ..on<RoomDisconnectedEvent>((_) async {
        if (_room == room) {
          await _teardown();
          _setStatus(VoiceStatus.disconnected);
        }
      })
      ..on<ParticipantConnectedEvent>((_) => _refreshAgentStatus(room))
      ..on<ParticipantDisconnectedEvent>((e) {
        if (e.participant.kind == ParticipantKind.AGENT) _setStatus(VoiceStatus.waitingForAgent);
      })
      ..on<ParticipantAttributesChanged>((_) => _refreshAgentStatus(room))
      ..on<TrackSubscribedEvent>((e) async {
        if (e.track.kind == TrackType.AUDIO) {
          try {
            await room.startAudio();
          } catch (_) {}
        }
      })
      ..on<DataReceivedEvent>(_onData);
  }

  void _onData(DataReceivedEvent e) {
    final msg = decodeMessage(e.data);
    if (msg == null) return;
    switch (e.topic) {
      case topicMode:
        if (msg['source'] == 'agent') onModeFromAgent?.call(AppMode.fromWire(msg['mode'] as String?));
      case topicWarnings:
        onWarningsFromAgent?.call(msg['minor_silenced'] == true);
    }
  }

  void _refreshAgentStatus(Room room) {
    final s = _agentStatus(room);
    if (s != null) _setStatus(s);
  }

  VoiceStatus? _agentStatus(Room room) {
    for (final p in room.remoteParticipants.values) {
      if (p.kind != ParticipantKind.AGENT) continue;
      return switch (p.attributes[agentStateAttribute]) {
        'thinking' => VoiceStatus.thinking,
        'speaking' => VoiceStatus.speaking,
        'listening' || 'idle' => VoiceStatus.listening,
        _ => VoiceStatus.waitingForAgent,
      };
    }
    return null;
  }

  Future<void> _teardown() async {
    final room = _room;
    _room = null;
    await _listener?.dispose();
    _listener = null;
    if (room != null) {
      try {
        await room.disconnect();
      } catch (_) {}
      await room.dispose();
    }
  }

  void _setStatus(VoiceStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}
