/// The five SafeStep languages. Codes match agent/safestep_agent/languages.py.
enum AppLanguage {
  en('en', 'English', 'English'),
  pcm('pcm', 'Pidgin', 'Naija'),
  yo('yo', 'Yoruba', 'Yorùbá'),
  ha('ha', 'Hausa', 'Hausa'),
  ig('ig', 'Igbo', 'Igbo');

  const AppLanguage(this.code, this.englishName, this.nativeName);

  final String code;
  final String englishName;
  final String nativeName;

  /// Tap-count order used during onboarding: 1 = English ... 5 = Igbo.
  int get tapCount => index + 1;

  static AppLanguage? fromCode(String? code) {
    for (final l in values) {
      if (l.code == code) return l;
    }
    return null;
  }

  static AppLanguage? fromTapCount(int taps) =>
      taps >= 1 && taps <= values.length ? values[taps - 1] : null;
}

/// Words a speech recogniser may return for each language name. Recognisers often
/// mis-spell non-English words, so this list is deliberately loose.
const Map<AppLanguage, List<String>> _languageKeywords = {
  AppLanguage.en: ['english', 'inglish', 'oyinbo', 'one'],
  AppLanguage.pcm: ['pidgin', 'pigin', 'pidgen', 'pigeon', 'naija', 'broken', 'two'],
  AppLanguage.yo: ['yoruba', 'yorùbá', 'yooba', 'yoroba', 'yorba', 'yarba', 'three'],
  AppLanguage.ha: ['hausa', 'ausa', 'house a', 'howsa', 'four'],
  AppLanguage.ig: ['igbo', 'ìgbò', 'ibo', 'eebo', 'egbo', 'five'],
};

/// Match a recogniser transcript to a language, or null if nothing matches.
/// If several match, the first word spoken wins.
AppLanguage? matchLanguage(String? transcript) {
  if (transcript == null) return null;
  final text = ' ${transcript.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')} ';
  AppLanguage? best;
  var bestPos = 1 << 30;
  _languageKeywords.forEach((lang, words) {
    for (final w in words) {
      final pos = text.indexOf(' $w ');
      if (pos >= 0 && pos < bestPos) {
        bestPos = pos;
        best = lang;
      }
    }
  });
  if (best == null) {
    final digit = RegExp(r'\b([1-5])\b').firstMatch(text);
    if (digit != null) return AppLanguage.fromTapCount(int.parse(digit.group(1)!));
  }
  return best;
}
