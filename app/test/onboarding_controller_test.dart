import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/models/language.dart';
import 'package:safestep/onboarding/onboarding_controller.dart';

class FakeSpeaker implements PromptSpeaker {
  final said = <String>[];
  @override
  Future<void> say(String id, List<AppLanguage> languages) async {
    said.add(id);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  @override
  Future<void> stop() async {}
  @override
  String textFor(String id, AppLanguage language) => '$id/${language.code}';
}

class FakePermissions implements PermissionGate {
  FakePermissions(this.micResults);
  final List<MicResult> micResults;
  int micCalls = 0;
  bool cameraAsked = false;
  @override
  Future<MicResult> requestMicrophone() async => micResults[micCalls++];
  @override
  Future<bool> requestCameraAndLocation() async => cameraAsked = true;
  @override
  Future<void> openSettings() async {}
}

class FakeRecognizer implements LanguageRecognizer {
  FakeRecognizer(this.answers);
  final List<String?> answers;
  int calls = 0;
  @override
  Future<String?> listen(Duration window) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return answers[calls++];
  }

  @override
  Future<void> cancel() async {}
}

OnboardingController make(FakeSpeaker s, FakePermissions p, FakeRecognizer r) => OnboardingController(
      speaker: s,
      permissions: p,
      recognizer: r,
      tapWindow: const Duration(milliseconds: 60),
      listenWindow: const Duration(milliseconds: 50),
      idleRepeat: const Duration(milliseconds: 100),
      confirmWindow: const Duration(milliseconds: 80),
      tipsWindow: const Duration(milliseconds: 80),
    );

/// Taps whenever the controller reaches [step].
void tapOn(OnboardingController c, OnboardingStep step, {int times = 1}) {
  var done = false;
  c.addListener(() {
    if (!done && c.step == step) {
      done = true;
      Future<void>.delayed(const Duration(milliseconds: 5), () async {
        for (var i = 0; i < times; i++) {
          c.onTap();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
    }
  });
}

void main() {
  test('voice path: welcome tap, mic granted, says Yoruba, skips tips', () async {
    final s = FakeSpeaker();
    final p = FakePermissions([MicResult.granted]);
    final c = make(s, p, FakeRecognizer(['Yoruba']));
    tapOn(c, OnboardingStep.welcome);
    final lang = await c.run();
    expect(lang, AppLanguage.yo);
    expect(p.cameraAsked, isTrue);
    expect(c.step, OnboardingStep.done);
    expect(s.said, containsAllInOrder(['welcome', 'mic_request', 'choose_language', 'language_confirmed', 'camera_location', 'tips_offer']));
    expect(s.said, isNot(contains('tips')));
  });

  test('tap path: four taps choose Hausa', () async {
    final c = make(FakeSpeaker(), FakePermissions([MicResult.granted]), FakeRecognizer([]));
    tapOn(c, OnboardingStep.welcome);
    tapOn(c, OnboardingStep.language, times: 4);
    expect(await c.run(), AppLanguage.ha);
  });

  test('mic denied then granted; unheard language falls back to English after 3 tries', () async {
    final s = FakeSpeaker();
    final p = FakePermissions([MicResult.denied, MicResult.granted]);
    final c = make(s, p, FakeRecognizer([null, 'hello', null]));
    tapOn(c, OnboardingStep.welcome);
    // after the denial the flow waits for a tap to retry
    c.addListener(() {
      if (c.caption.startsWith('mic_denied')) {
        Future<void>.delayed(const Duration(milliseconds: 40), c.onTap);
      }
    });
    expect(await c.run(), AppLanguage.en);
    expect(p.micCalls, 2);
    expect(s.said.where((x) => x == 'language_not_heard').length, 3);
  });

  test('double tap on confirmation lets the user choose again', () async {
    final c = make(FakeSpeaker(), FakePermissions([MicResult.granted]), FakeRecognizer(['English', 'Igbo']));
    tapOn(c, OnboardingStep.welcome);
    tapOn(c, OnboardingStep.confirmLanguage, times: 2);
    expect(await c.run(), AppLanguage.ig);
  });
}
