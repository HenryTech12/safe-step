import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import '../models/language.dart';
import '../onboarding/onboarding_controller.dart';

/// Plays pre-recorded prompts from `assets/onboarding/<lang>/<id>.mp3` (works offline).
/// If a clip is missing it falls back to Android's built-in TTS reading the text from
/// prompts.json. Android has no Yoruba/Hausa/Igbo voices, so generate the clips with
/// agent/scripts/generate_onboarding_audio.py before a demo.
class PromptPlayer implements PromptSpeaker {
  PromptPlayer._(this._texts);

  final Map<String, Map<String, String>> _texts;
  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();
  int _generation = 0;

  static Future<PromptPlayer> load() async {
    final raw = jsonDecode(await rootBundle.loadString('assets/onboarding/prompts.json')) as Map<String, dynamic>;
    final texts = <String, Map<String, String>>{};
    raw.forEach((id, v) {
      if (v is Map) texts[id] = v.map((k, t) => MapEntry(k as String, t as String));
    });
    final p = PromptPlayer._(texts);
    await p._tts.awaitSpeakCompletion(true);
    await p._tts.setSpeechRate(0.45);
    return p;
  }

  @override
  String textFor(String id, AppLanguage language) {
    final m = _texts[id];
    if (m == null) return '';
    return m[language.code] ?? m['en'] ?? '';
  }

  @override
  Future<void> say(String id, List<AppLanguage> languages) async {
    final gen = ++_generation;
    for (final lang in languages) {
      if (gen != _generation) return; // stopped
      final m = _texts[id];
      if (m == null || !m.containsKey(lang.code)) continue;
      if (!await _playClip('assets/onboarding/${lang.code}/$id.mp3')) {
        await _speak(m[lang.code]!, lang);
      }
    }
  }

  Future<bool> _playClip(String asset) async {
    try {
      await rootBundle.load(asset); // throws if the clip wasn't bundled
    } catch (_) {
      return false;
    }
    try {
      await _player.setAsset(asset);
      await _player.play(); // completes when playback ends or is stopped
      return true;
    } catch (e) {
      debugPrint('PromptPlayer clip failed $asset: $e');
      return false;
    }
  }

  Future<void> _speak(String text, AppLanguage lang) async {
    const locales = {'en': 'en-NG', 'pcm': 'en-NG', 'yo': 'yo-NG', 'ha': 'ha-NG', 'ig': 'ig-NG'};
    final want = locales[lang.code]!;
    final ok = await _tts.isLanguageAvailable(want);
    await _tts.setLanguage(ok == true ? want : 'en-US');
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _player.stop();
    await _tts.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
