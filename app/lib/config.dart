/// Build-time settings. NO SECRETS here: the app only knows the token server URL.
///
///   flutter run --dart-define=TOKEN_URL=http://192.168.1.20:8765
library;

/// Base URL of the SafeStep token server (agent/token_server). 10.0.2.2 is the host machine
/// as seen from the Android emulator.
const String tokenServerUrl = String.fromEnvironment(
  'TOKEN_URL',
  defaultValue: 'http://10.0.2.2:8765',
);

/// Build with --dart-define=DEMO=true to show the demo-mode entry on the guide screen.
const bool demoEnabled = bool.fromEnvironment('DEMO', defaultValue: false);

/// How long to listen for a spoken language name during onboarding.
const Duration languageListenWindow = Duration(seconds: 6);

/// Pause after the last tap before a tap count is final.
const Duration tapCountWindow = Duration(milliseconds: 1200);
