import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vibration/vibration.dart';

import '../models/language.dart';
import 'hazard_classes.dart';
import 'hazard_policy.dart';

/// Vibration per severity: critical = three long pulses, minor = two short ones.
const Map<Severity, List<int>> vibrationPatterns = {
  Severity.critical: [0, 400, 120, 400, 120, 400],
  Severity.minor: [0, 150, 100, 150],
};

/// Plays offline hazard alerts: vibration + a pre-recorded clip for the class and side, in the
/// user's language. Falls back to Android TTS reading alerts.json if a clip is missing.
/// [duck]/[unduck] pause the agent's voice around the alert.
class AlertPlayer {
  AlertPlayer._(this._texts);

  final Map<String, Map<String, String>> _texts;
  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();
  final Set<String> _missing = {};
  bool _playing = false;

  Future<void> Function()? duck;
  Future<void> Function()? unduck;

  bool get playing => _playing;

  static Future<AlertPlayer> load() async {
    final raw = jsonDecode(await rootBundle.loadString('assets/alerts/alerts.json')) as Map<String, dynamic>;
    final texts = <String, Map<String, String>>{};
    raw.forEach((k, v) {
      if (v is Map) texts[k] = v.map((l, t) => MapEntry(l as String, t as String));
    });
    final p = AlertPlayer._(texts);
    await p._tts.awaitSpeakCompletion(true);
    await p._tts.setSpeechRate(0.55);
    return p;
  }

  String textFor(String id, AppLanguage lang) => _texts[id]?[lang.code] ?? _texts[id]?['en'] ?? '';

  /// Plays the alert. A critical alert interrupts a minor one already playing;
  /// otherwise a new alert is dropped while one is playing.
  Future<bool> play(HazardAlert alert, AppLanguage lang) async {
    if (_playing && !alert.cls.critical) return false;
    if (_playing) await _stopSound();
    _playing = true;
    try {
      unawaited(_vibrate(alert.cls.severity));
      await duck?.call();
      await _say(alert.cls.wire, lang);
      if (alert.side != Side.ahead || alert.cls.critical) {
        await _say('side_${alert.side.name}', lang);
      }
      return true;
    } finally {
      await unduck?.call();
      _playing = false;
    }
  }

  /// Plays an arbitrary alert-style line (used for offline mode confirmations).
  Future<void> sayText(String text, AppLanguage lang) async {
    await _setTtsLanguage(lang);
    await _tts.speak(text);
  }

  Future<void> _say(String id, AppLanguage lang) async {
    final asset = 'assets/alerts/${lang.code}/$id.mp3';
    if (!_missing.contains(asset)) {
      try {
        await rootBundle.load(asset);
        await _player.setAsset(asset);
        await _player.play();
        return;
      } catch (_) {
        _missing.add(asset);
      }
    }
    final text = textFor(id, lang);
    if (text.isEmpty) return;
    await _setTtsLanguage(lang);
    await _tts.speak(text);
  }

  Future<void> _setTtsLanguage(AppLanguage lang) async {
    const locales = {'en': 'en-NG', 'pcm': 'en-NG', 'yo': 'yo-NG', 'ha': 'ha-NG', 'ig': 'ig-NG'};
    final want = locales[lang.code]!;
    final ok = await _tts.isLanguageAvailable(want);
    await _tts.setLanguage(ok == true ? want : 'en-US');
  }

  Future<void> _vibrate(Severity s) async {
    try {
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(pattern: vibrationPatterns[s]!);
      }
    } catch (e) {
      debugPrint('vibrate failed: $e');
    }
  }

  Future<void> _stopSound() async {
    await _player.stop();
    await _tts.stop();
  }

  Future<void> dispose() async {
    await _stopSound();
    await _player.dispose();
  }
}
