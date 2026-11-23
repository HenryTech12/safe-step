import 'package:material_ui/material_ui.dart';

import 'config.dart';
import 'demo/demo_screen.dart';
import 'guide/guide_controller.dart';
import 'models/language.dart';
import 'onboarding/onboarding_controller.dart';
import 'screens/guide_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/device_language_recognizer.dart';
import 'services/device_permissions.dart';
import 'services/livekit_service.dart';
import 'services/prefs_service.dart';
import 'services/prompt_player.dart';
import 'services/token_client.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await PrefsService.load();
  final voice = LiveKitService(
    tokenClient: TokenClient(baseUrl: tokenServerUrl),
    installId: () => prefs.installId,
  );
  runApp(SafeStepApp(prefs: prefs, voice: voice));
}

class SafeStepApp extends StatefulWidget {
  const SafeStepApp({super.key, required this.prefs, required this.voice});

  final PrefsService prefs;
  final LiveKitService voice;

  @override
  State<SafeStepApp> createState() => _SafeStepAppState();
}

class _SafeStepAppState extends State<SafeStepApp> {
  late bool _onboarded = widget.prefs.onboarded;
  OnboardingController? _onboarding;
  PromptPlayer? _player;
  GuideController? _guide;

  GuideController _guideController() => _guide ??= GuideController(
        prefs: widget.prefs,
        voice: widget.voice,
        recognizer: DeviceLanguageRecognizer(
          phrases: const ['stop warning me', 'warnings only', 'navigation', 'repeat', 'say again'],
        ),
      );

  @override
  void initState() {
    super.initState();
    if (!_onboarded) _startOnboarding();
  }

  Future<void> _startOnboarding() async {
    final player = await PromptPlayer.load();
    setState(() {
      _player = player;
      _onboarding = OnboardingController(
        speaker: player,
        permissions: DevicePermissions(),
        recognizer: DeviceLanguageRecognizer(),
      );
    });
  }

  Future<void> _finishOnboarding(AppLanguage language) async {
    await widget.prefs.setLanguage(language);
    await widget.prefs.setOnboarded(true);
    await _player?.dispose();
    setState(() {
      _onboarded = true;
      _onboarding?.dispose();
      _onboarding = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget home;
    if (_onboarded) {
      final guide = _guideController();
      home = Builder(
        builder: (ctx) => GuideScreen(
          controller: guide,
          onOpenDemo: demoEnabled
              ? () => Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => DemoScreen(guide: guide)))
              : null,
        ),
      );
    } else if (_onboarding != null) {
      home = OnboardingScreen(controller: _onboarding!, onFinished: _finishOnboarding);
    } else {
      home = const Scaffold(body: SizedBox.expand());
    }
    return MaterialApp(
      title: 'SafeStep',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      home: home,
    );
  }
}
