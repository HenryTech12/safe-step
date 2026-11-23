# SafeStep app (Android)

See the root README for how to run it. Structure:

- `lib/main.dart`: bootstrap; picks onboarding or the guide screen
- `lib/onboarding/`: voice-only onboarding flow (pure logic, unit tested)
- `lib/screens/`: onboarding and guide screens (full-screen gestures, TalkBack labels)
- `lib/services/`: token client, LiveKit, prefs, prompt player, permissions, recogniser
- `lib/l10n/strings.dart`: status strings in five languages
- `assets/onboarding/prompts.json`: onboarding speech; clips go in `assets/onboarding/<lang>/`
