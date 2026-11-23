import '../models/language.dart';

/// On-screen and TalkBack strings for the guide screen.
/// Yoruba, Hausa and Igbo NEED NATIVE-SPEAKER REVIEW.
class Strings {
  const Strings._(this._t);
  final Map<String, String> _t;

  static Strings of(AppLanguage lang) => Strings._(_all[lang]!);

  String get connecting => _t['connecting']!;
  String get listening => _t['listening']!;
  String get thinking => _t['thinking']!;
  String get speaking => _t['speaking']!;
  String get offline => _t['offline']!;
  String get micMuted => _t['micMuted']!;
  String get modeHazard => _t['modeHazard']!;
  String get modeNavigation => _t['modeNavigation']!;
  String get screenHint => _t['screenHint']!;

  static const Map<AppLanguage, Map<String, String>> _all = {
    AppLanguage.en: {
      'connecting': 'Connecting',
      'listening': 'Listening',
      'thinking': 'Thinking',
      'speaking': 'Speaking',
      'offline': 'No connection. Double tap to retry.',
      'micMuted': 'Microphone off. Double tap to talk.',
      'modeHazard': 'Hazard warnings',
      'modeNavigation': 'Navigation',
      'screenHint': 'Double tap to turn the microphone on or off.',
    },
    AppLanguage.pcm: {
      'connecting': 'I dey connect',
      'listening': 'I dey hear you',
      'thinking': 'I dey think',
      'speaking': 'I dey talk',
      'offline': 'Network no dey. Touch two times make we try again.',
      'micMuted': 'Microphone don off. Touch two times make you talk.',
      'modeHazard': 'Danger warning',
      'modeNavigation': 'Direction',
      'screenHint': 'Touch two times to on or off the microphone.',
    },
    AppLanguage.yo: {
      'connecting': 'Ó ń sopọ̀',
      'listening': 'Mo ń gbọ́ yín',
      'thinking': 'Mo ń ronú',
      'speaking': 'Mo ń sọ̀rọ̀',
      'offline': 'Kò sí ìsopọ̀. Tẹ ẹ̀ẹ̀mejì láti tún gbìyànjú.',
      'micMuted': 'Gbohùngbohùn ti pa. Tẹ ẹ̀ẹ̀mejì láti sọ̀rọ̀.',
      'modeHazard': 'Ìkìlọ̀ ewu',
      'modeNavigation': 'Ìtọ́sọ́nà',
      'screenHint': 'Tẹ ẹ̀ẹ̀mejì láti tan tàbí pa gbohùngbohùn.',
    },
    AppLanguage.ha: {
      'connecting': 'Ana haɗawa',
      'listening': 'Ina sauraronka',
      'thinking': 'Ina tunani',
      'speaking': 'Ina magana',
      'offline': 'Babu haɗi. Taɓa sau biyu don sake gwadawa.',
      'micMuted': 'An kashe makirufo. Taɓa sau biyu don magana.',
      'modeHazard': 'Gargadin haɗari',
      'modeNavigation': 'Jagora',
      'screenHint': 'Taɓa sau biyu don kunna ko kashe makirufo.',
    },
    AppLanguage.ig: {
      'connecting': 'Ọ na-ejikọ',
      'listening': 'Ana m anụ gị',
      'thinking': 'Ana m eche echiche',
      'speaking': 'Ana m ekwu okwu',
      'offline': 'Enweghị njikọ. Pịa ugboro abụọ ka ịnwaa ọzọ.',
      'micMuted': 'Igwe okwu agbanyụọla. Pịa ugboro abụọ ka ikwuo okwu.',
      'modeHazard': 'Ịdọ aka ná ntị',
      'modeNavigation': 'Nduzi',
      'screenHint': 'Pịa ugboro abụọ iji gbanwuo ma ọ bụ gbanyụọ igwe okwu.',
    },
  };
}
