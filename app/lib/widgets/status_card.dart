import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Large, high-contrast status card. TalkBack reads it as a live region so status
/// changes are announced.
class StatusCard extends StatelessWidget {
  const StatusCard({super.key, required this.title, required this.subtitle, required this.color});

  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        decoration: BoxDecoration(
          color: SafeStepColors.surface,
          border: Border.all(color: color, width: 6),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            Text(title, textAlign: TextAlign.center, style: t.displaySmall?.copyWith(color: color)),
            const SizedBox(height: 16),
            Text(subtitle, textAlign: TextAlign.center, style: t.titleLarge),
          ],
        ),
      ),
    );
  }
}
