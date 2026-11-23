import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config.dart' as config;
import '../models/language.dart';

/// Speaks a prompt from assets/onboarding/prompts.json in one or more languages, in order.
abstract class PromptSpeaker {
  Future<void> say(String id, List<AppLanguage> languages);
  Future<void> stop();
  String textFor(String id, AppLanguage language);
}

enum MicResult { granted, denied, permanentlyDenied }

abstract class PermissionGate {
  Future<MicResult> requestMicrophone();

  /// Returns true if the camera was granted (location is optional in Phase 1).
  Future<bool> requestCameraAndLocation();
  Future<void> openSettings();
}

/// Listens once and returns what was heard, or null.
abstract class LanguageRecognizer {
  Future<String?> listen(Duration window);
  Future<void> cancel();
}

enum OnboardingStep { welcome, microphone, language, confirmLanguage, cameraLocation, tips, done }

/// Voice-only onboarding flow (runs once):
/// welcome (all languages) → mic permission → language by voice or tap count →
/// camera + location → optional tips → done. No typing, no account.
///
/// The screen forwards every tap anywhere to [onTap].
class OnboardingController extends ChangeNotifier {
  OnboardingController({
    required this.speaker,
    required this.permissions,
    required this.recognizer,
    this.tapWindow = config.tapCountWindow,
    this.listenWindow = config.languageListenWindow,
    this.idleRepeat = const Duration(seconds: 8),
    this.confirmWindow = const Duration(seconds: 3),
    this.tipsWindow = const Duration(seconds: 5),
    this.maxLanguageAttempts = 3,
  });

  final PromptSpeaker speaker;
  final PermissionGate permissions;
  final LanguageRecognizer recognizer;
  final Duration tapWindow;
  final Duration listenWindow;
  final Duration idleRepeat;
  final Duration confirmWindow;
  final Duration tipsWindow;
  final int maxLanguageAttempts;

  final _taps = StreamController<void>.broadcast();
  bool _disposed = false;

  OnboardingStep _step = OnboardingStep.welcome;
  OnboardingStep get step => _step;

  AppLanguage? _language;
  AppLanguage? get language => _language;

  /// Text of the prompt being spoken, shown large on screen and read by TalkBack.
  String _caption = '';
  String get caption => _caption;

  void onTap() {
    if (!_taps.isClosed) _taps.add(null);
  }

  /// Runs the whole flow and returns the chosen language.
  Future<AppLanguage> run() async {
    await _welcome();
    await _microphone();
    final lang = await _chooseLanguage();
    await _cameraLocation(lang);
    await _tips(lang);
    _set(OnboardingStep.done);
    return lang;
  }

  // --- steps ---

  Future<void> _welcome() async {
    _set(OnboardingStep.welcome);
    while (true) {
      if (await _sayUntilTap('welcome', AppLanguage.values, waitAfter: idleRepeat)) return;
    }
  }

  Future<void> _microphone() async {
    _set(OnboardingStep.microphone);
    const langs = [AppLanguage.en, AppLanguage.pcm];
    await _sayUntilTap('mic_request', langs);
    while (true) {
      final r = await permissions.requestMicrophone();
      if (r == MicResult.granted) return;
      await _sayUntilTap('mic_denied', langs);
      await _nextTap();
      if (r == MicResult.permanentlyDenied) await permissions.openSettings();
    }
  }

  Future<AppLanguage> _chooseLanguage() async {
    while (true) {
      _set(OnboardingStep.language);
      AppLanguage? chosen;
      for (var attempt = 0; attempt < maxLanguageAttempts && chosen == null; attempt++) {
        chosen = await _askLanguageOnce();
        if (chosen == null) await _sayUntilTap('language_not_heard', const [AppLanguage.en, AppLanguage.pcm]);
      }
      chosen ??= AppLanguage.en;
      _language = chosen;
      _set(OnboardingStep.confirmLanguage);

      // Double tap within the window means "change it".
      var taps = 0;
      if (await _sayUntilTap('language_confirmed', [chosen], waitAfter: confirmWindow)) {
        taps = await _countTaps(already: 1);
      }
      if (taps < 2) return chosen;
    }
  }

  Future<AppLanguage?> _askLanguageOnce() async {
    // Tapping during the prompt skips straight to tap counting.
    if (await _sayUntilTap('choose_language', AppLanguage.values)) {
      return AppLanguage.fromTapCount(await _countTaps(already: 1));
    }
    final tap = _nextTapOrNever();
    final heard = recognizer.listen(listenWindow).then<Object?>((t) => t);
    final first = await Future.any<Object?>([heard, tap.then<Object?>((_) => #tap)]);
    if (first == #tap) {
      await recognizer.cancel();
      return AppLanguage.fromTapCount(await _countTaps(already: 1));
    }
    return matchLanguage(first as String?);
  }

  Future<void> _cameraLocation(AppLanguage lang) async {
    _set(OnboardingStep.cameraLocation);
    await _sayUntilTap('camera_location', [lang]);
    final ok = await permissions.requestCameraAndLocation();
    if (!ok) await _sayUntilTap('permissions_denied', [lang]);
  }

  Future<void> _tips(AppLanguage lang) async {
    _set(OnboardingStep.tips);
    if (await _sayUntilTap('tips_offer', [lang], waitAfter: tipsWindow)) {
      await _sayUntilTap('tips', [lang]);
    }
  }

  // --- tap helpers ---

  /// Speak, but stop as soon as the user taps. Optionally keep waiting for a tap after.
  /// Returns true if the user tapped.
  Future<bool> _sayUntilTap(String id, List<AppLanguage> langs, {Duration? waitAfter}) async {
    _caption = speaker.textFor(id, langs.first);
    if (!_disposed) notifyListeners();
    final tap = _nextTapOrNever();
    final tapped = await Future.any<bool>([
      speaker.say(id, langs).then((_) => false),
      tap.then((_) => true),
    ]);
    if (tapped) {
      await speaker.stop();
      return true;
    }
    if (waitAfter == null) return false;
    return Future.any<bool>([tap.then((_) => true), Future.delayed(waitAfter, () => false)]);
  }

  /// Counts further taps until [tapWindow] passes with none.
  Future<int> _countTaps({int already = 0}) async {
    var count = already;
    while (true) {
      final more = await Future.any<bool>([
        _nextTapOrNever().then((_) => true),
        Future.delayed(tapWindow, () => false),
      ]);
      if (!more) return count;
      count++;
    }
  }

  Future<void> _nextTap() => _taps.stream.first.catchError((_) {});

  /// Completes on the next tap; never completes (and never throws) once disposed.
  Future<void> _nextTapOrNever() {
    final c = Completer<void>();
    late final StreamSubscription<void> sub;
    sub = _taps.stream.listen((_) {
      sub.cancel();
      if (!c.isCompleted) c.complete();
    });
    return c.future;
  }

  void _set(OnboardingStep s) {
    _step = s;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _taps.close();
    super.dispose();
  }
}
