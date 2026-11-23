import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';

import '../models/language.dart';
import '../onboarding/onboarding_controller.dart';
import '../theme.dart';

/// Full-screen tap target. Everything is spoken; the large caption is for low-vision
/// users and is also announced by TalkBack.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.controller, required this.onFinished});

  final OnboardingController controller;
  final Future<void> Function(AppLanguage language) onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final lang = await widget.controller.run();
      await widget.onFinished(lang);
    });
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final caption = widget.controller.caption;
    return Scaffold(
      body: Semantics(
        // With TalkBack on, a double tap activates this; it's forwarded as one tap.
        button: true,
        label: caption.isEmpty ? 'SafeStep' : caption,
        hint: 'Tap anywhere',
        onTap: widget.controller.onTap,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.controller.onTap,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('SafeStep',
                      style: Theme.of(context)
                          .textTheme
                          .displaySmall
                          ?.copyWith(color: SafeStepColors.accent)),
                  const SizedBox(height: 32),
                  Text(caption, style: Theme.of(context).textTheme.headlineMedium),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Announce a string through TalkBack without moving focus.
void announce(BuildContext context, String message) {
  SemanticsService.sendAnnouncement(View.of(context), message, TextDirection.ltr);
}
