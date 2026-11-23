import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../guide/guide_controller.dart';
import '../models/app_mode.dart';
import '../services/livekit_service.dart';
import '../theme.dart';
import '../widgets/status_card.dart';

/// Main screen: one full-screen gesture surface and a large status card.
/// - double tap: talk (mic on/off); when offline, listen for a fixed command
/// - swipe down: mute / unmute the agent's voice (hazard alerts always play)
/// - long press: repeat the last thing said
/// With TalkBack on, the same actions are exposed as semantic actions on the screen.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key, required this.controller, this.onOpenDemo});

  final GuideController controller;
  final VoidCallback? onOpenDemo;

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  GuideController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    c.start();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    super.dispose();
  }

  Future<void> _doubleTap() async {
    HapticFeedback.mediumImpact();
    await c.onDoubleTap();
  }

  Future<void> _swipeDown() async {
    HapticFeedback.heavyImpact();
    await c.onSwipeDown();
  }

  Future<void> _longPress() async {
    HapticFeedback.selectionClick();
    await c.onLongPress();
  }

  @override
  Widget build(BuildContext context) {
    final s = c.strings;
    final v = c.voice;
    final (String title, Color color) = c.listeningOffline
        ? (s.listening, SafeStepColors.accent)
        : switch (v.status) {
            VoiceStatus.connecting || VoiceStatus.waitingForAgent => (s.connecting, SafeStepColors.accent),
            VoiceStatus.listening =>
              v.micEnabled ? (s.listening, SafeStepColors.ok) : (s.micMuted, SafeStepColors.accent),
            VoiceStatus.thinking => (s.thinking, SafeStepColors.accent),
            VoiceStatus.speaking => (s.speaking, SafeStepColors.ok),
            VoiceStatus.disconnected || VoiceStatus.failed => (s.offline, SafeStepColors.danger),
          };
    final modeLabel = c.mode == AppMode.navigation ? s.modeNavigation : s.modeHazard;
    final subtitle = [
      modeLabel,
      if (c.agentVoiceMuted) s.agentMuted,
      if (c.hazards?.minorSilenced ?? false) s.minorQuiet,
    ].join('. ');

    return Scaffold(
      body: Semantics(
        label: '$title. $subtitle',
        hint: s.screenHint,
        onTap: _doubleTap, // TalkBack double tap
        onLongPress: _longPress,
        customSemanticsActions: {
          CustomSemanticsAction(label: s.agentMuted): _swipeDown,
          if (widget.onOpenDemo != null) CustomSemanticsAction(label: s.demoMode): widget.onOpenDemo!,
        },
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _doubleTap,
          onLongPress: _longPress,
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 600) _swipeDown();
          },
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  StatusCard(title: title, subtitle: subtitle, color: color),
                  const SizedBox(height: 32),
                  Text(s.screenHint, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
                  if (widget.onOpenDemo != null) ...[
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: widget.onOpenDemo,
                      child: Text(s.demoMode, style: const TextStyle(fontSize: 22, color: SafeStepColors.accent)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
