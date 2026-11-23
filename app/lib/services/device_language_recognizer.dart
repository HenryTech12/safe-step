import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../onboarding/onboarding_controller.dart';

/// Android's on-device speech recogniser, used only to hear a language name during
/// onboarding (before the agent is connected). Falls back gracefully: if it is not
/// available, listen() returns null and the user can use tap counting instead.
class DeviceLanguageRecognizer implements LanguageRecognizer {
  DeviceLanguageRecognizer({this.phrases = const ['English', 'Pidgin', 'Naija', 'Yoruba', 'Hausa', 'Igbo']});

  /// Hints for the recogniser (Android 13+ uses them to bias recognition).
  final List<String> phrases;
  final SpeechToText _stt = SpeechToText();
  bool? _ready;

  @override
  Future<String?> listen(Duration window) async {
    _ready ??= await _stt.initialize(onError: (e) => debugPrint('stt error: $e'));
    if (_ready != true) return null;

    final done = Completer<String?>();
    String last = '';
    await _stt.listen(
      onResult: (r) {
        last = r.recognizedWords;
        if (r.finalResult && !done.isCompleted) done.complete(last);
      },
      listenOptions: SpeechListenOptions(
        listenFor: window,
        pauseFor: const Duration(seconds: 2),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
        contextualPhrases: phrases,
      ),
    );
    return done.future.timeout(window + const Duration(seconds: 1), onTimeout: () async {
      await _stt.stop();
      return last.isEmpty ? null : last;
    });
  }

  @override
  Future<void> cancel() => _stt.cancel();
}
