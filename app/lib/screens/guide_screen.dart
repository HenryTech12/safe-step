import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/strings.dart';
import '../models/app_mode.dart';
import '../models/language.dart';
import '../services/livekit_service.dart';
import '../services/prefs_service.dart';
import '../theme.dart';
import '../widgets/status_card.dart';

/// Main screen. Phase 1: connects to the agent and shows its state.
/// Gestures: double tap = mic on/off (or retry when offline).
/// Phase 4 adds swipe down to mute and long press to repeat.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key, required this.voice, required this.prefs});

  final LiveKitService voice;
  final PrefsService prefs;

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  late final AppLanguage _lang = widget.prefs.language;
  late AppMode _mode = widget.prefs.lastMode;

  @override
  void initState() {
    super.initState();
    widget.voice
      ..addListener(_onChange)
      ..onModeFromAgent = (m) {
        widget.prefs.setLastMode(m);
        setState(() => _mode = m);
      };
    _connect();
  }

  Future<void> _connect() => widget.voice.connect(language: _lang, mode: _mode);

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _onDoubleTap() async {
    HapticFeedback.mediumImpact();
    final v = widget.voice;
    if (!v.isConnected) {
      await _connect();
    } else {
      await v.setMicEnabled(!v.micEnabled);
    }
  }

  @override
  void dispose() {
    widget.voice.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(_lang);
    final v = widget.voice;
    final (String title, Color color) = switch (v.status) {
      VoiceStatus.connecting || VoiceStatus.waitingForAgent => (s.connecting, SafeStepColors.accent),
      VoiceStatus.listening => v.micEnabled ? (s.listening, SafeStepColors.ok) : (s.micMuted, SafeStepColors.accent),
      VoiceStatus.thinking => (s.thinking, SafeStepColors.accent),
      VoiceStatus.speaking => (s.speaking, SafeStepColors.ok),
      VoiceStatus.disconnected || VoiceStatus.failed => (s.offline, SafeStepColors.danger),
    };
    final modeLabel = _mode == AppMode.navigation ? s.modeNavigation : s.modeHazard;

    return Scaffold(
      body: Semantics(
        button: true,
        label: '$title. $modeLabel',
        hint: s.screenHint,
        onTap: _onDoubleTap, // TalkBack's double tap activates this
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _onDoubleTap,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  StatusCard(title: title, subtitle: modeLabel, color: color),
                  const SizedBox(height: 32),
                  Text(s.screenHint,
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
