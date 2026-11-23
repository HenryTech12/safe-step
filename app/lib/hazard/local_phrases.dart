/// Fixed phrases the phone understands by itself, so mode switching works with no network.
/// Matching is whole-word phrase search on the recogniser's transcript. Yoruba/Hausa/Igbo phrases
/// NEED NATIVE-SPEAKER REVIEW and real recogniser testing.
enum LocalCommand { hazardMode, navigationMode, quietMinor, allWarnings, repeat }

const Map<LocalCommand, List<String>> _phrases = {
  LocalCommand.quietMinor: [
    'stop warning', 'stop warnings', 'quiet', 'be quiet', 'too much warning',
    'stop to dey warn', 'no dey warn me', 'stop dey warn',
    'dákẹ́', 'dake', 'ma kilo mo', 'daina gargadi', 'yi shiru', 'kwusi idọ aka', 'kwusi ido aka',
  ],
  LocalCommand.allWarnings: [
    'warn me again', 'all warnings', 'warnings on', 'start warning',
    'dey warn me again', 'kilo fun mi', 'ci gaba da gargadi', 'dọọ m aka', 'doo m aka',
  ],
  LocalCommand.hazardMode: [
    'warnings only', 'warning only', 'hazard mode', 'hazard detection', 'just warn', 'only warning',
    'na only warning', 'only danger', 'ikilo nikan', 'gargadi kawai', 'naanị ịdọ aka', 'naani ido aka',
  ],
  LocalCommand.navigationMode: [
    'navigation', 'take me to', 'direction', 'show me road', 'show me the way', 'carry me go',
    'mu mi lo', 'kai ni', 'duru m', 'kpọrọ m gaa', 'kporo m gaa',
  ],
  LocalCommand.repeat: ['repeat', 'say again', 'talk am again', 'tun so', 'sake fada', 'kwughachi'],
};

/// Returns the command in [transcript], or null. Earlier-listed commands win on ties, so
/// "stop warning" beats the generic "warning only".
LocalCommand? matchLocalCommand(String? transcript) {
  if (transcript == null) return null;
  final cleaned = transcript.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
  final t = ' ${cleaned.replaceAll(RegExp(r'\s+'), ' ').trim()} ';
  for (final entry in _phrases.entries) {
    for (final p in entry.value) {
      if (t.contains(' $p ')) return entry.key; // whole words only
    }
  }
  return null;
}
