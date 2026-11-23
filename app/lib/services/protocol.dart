/// Data-message topics shared with the agent. Keep in sync with
/// agent/safestep_agent/protocol.py and docs/PROTOCOL.md.
library;

import 'dart:convert';

const String topicMode = 'mode';
const String topicWarnings = 'warnings';
const String topicHazard = 'hazard_event';
const String topicGps = 'gps';
const String topicPlaces = 'places';
const String topicPlaceSaved = 'place_saved';
const String topicControl = 'control';
const String topicFrameRequest = 'frame_request';
const String streamCameraFrame = 'camera_frame';

/// LiveKit participant attribute where the agent publishes its state.
const String agentStateAttribute = 'lk.agent.state';

List<int> encodeMessage(Map<String, Object?> payload) => utf8.encode(jsonEncode(payload));

Map<String, dynamic>? decodeMessage(List<int> data) {
  try {
    final obj = jsonDecode(utf8.decode(data));
    return obj is Map<String, dynamic> ? obj : null;
  } catch (_) {
    return null;
  }
}
