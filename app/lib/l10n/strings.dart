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
  String get hazardModeOn => _t['hazardModeOn']!;
  String get navNeedsNetwork => _t['navNeedsNetwork']!;
  String get minorQuiet => _t['minorQuiet']!;
  String get allWarningsOn => _t['allWarningsOn']!;
  String get notUnderstood => _t['notUnderstood']!;
  String get agentMuted => _t['agentMuted']!;
  String get agentUnmuted => _t['agentUnmuted']!;
  String get demoMode => _t['demoMode']!;

  static const Map<AppLanguage, Map<String, String>> _all = {
    AppLanguage.en: {
      'hazardModeOn': 'Hazard warnings only.',
      'navNeedsNetwork': 'Directions need the internet. Hazard warnings are on.',
      'minorQuiet': 'Minor warnings off. Gutters, manholes and okadas will still be announced.',
      'allWarningsOn': 'All warnings on.',
      'notUnderstood': 'Sorry, I did not get that.',
      'agentMuted': 'Voice muted. Danger alerts stay on.',
      'agentUnmuted': 'Voice on.',
      'demoMode': 'Demo mode',
      'connecting': 'Connecting',
      'listening': 'Listening',
      'thinking': 'Thinking',
      'speaking': 'Speaking',
      'offline': 'No connection. Double tap to retry.',
      'micMuted': 'Microphone off. Double tap to talk.',
      'modeHazard': 'Hazard warnings',
      'modeNavigation': 'Navigation',
      'screenHint': 'Double tap to talk. Swipe down to mute my voice. Hold to repeat.',
    },
    AppLanguage.pcm: {
      'hazardModeOn': 'Na only danger warning now.',
      'navNeedsNetwork': 'Direction need network. Danger warning still dey on.',
      'minorQuiet': 'I don stop small small warning. I go still warn you for gutter, manhole and okada.',
      'allWarningsOn': 'All warning don on.',
      'notUnderstood': 'Sorry, I no hear am well.',
      'agentMuted': 'I don off my voice. Danger warning still dey.',
      'agentUnmuted': 'My voice don on.',
      'demoMode': 'Demo mode',
      'connecting': 'I dey connect',
      'listening': 'I dey hear you',
      'thinking': 'I dey think',
      'speaking': 'I dey talk',
      'offline': 'Network no dey. Touch two times make we try again.',
      'micMuted': 'Microphone don off. Touch two times make you talk.',
      'modeHazard': 'Danger warning',
      'modeNavigation': 'Direction',
      'screenHint': 'Touch two times to talk. Drag down to off my voice. Hold am make I repeat.',
    },
    AppLanguage.yo: {
      'hazardModeOn': 'Ìkìlọ̀ ewu nìkan.',
      'navNeedsNetwork': 'Ìtọ́sọ́nà nílò íńtánẹ́ẹ̀tì. Ìkìlọ̀ ewu ṣì wà.',
      'minorQuiet': 'Mo ti pa ìkìlọ̀ kéékèèké. Mo ṣì máa kìlọ̀ nípa kòtò, ihò àti ọ̀kadà.',
      'allWarningsOn': 'Gbogbo ìkìlọ̀ ti tàn.',
      'notUnderstood': 'Ẹ má bínú, mi ò gbọ́ ọ.',
      'agentMuted': 'Ohùn ti pa. Ìkìlọ̀ ewu ṣì wà.',
      'agentUnmuted': 'Ohùn ti tàn.',
      'demoMode': 'Ipò àfihàn',
      'connecting': 'Ó ń sopọ̀',
      'listening': 'Mo ń gbọ́ yín',
      'thinking': 'Mo ń ronú',
      'speaking': 'Mo ń sọ̀rọ̀',
      'offline': 'Kò sí ìsopọ̀. Tẹ ẹ̀ẹ̀mejì láti tún gbìyànjú.',
      'micMuted': 'Gbohùngbohùn ti pa. Tẹ ẹ̀ẹ̀mejì láti sọ̀rọ̀.',
      'modeHazard': 'Ìkìlọ̀ ewu',
      'modeNavigation': 'Ìtọ́sọ́nà',
      'screenHint': 'Tẹ ẹ̀ẹ̀mejì láti sọ̀rọ̀. Fà sísàlẹ̀ láti pa ohùn mi. Di mú kí n tún sọ.',
    },
    AppLanguage.ha: {
      'hazardModeOn': 'Gargadin haɗari kawai.',
      'navNeedsNetwork': 'Jagora yana buƙatar intanet. Gargadin haɗari yana nan.',
      'minorQuiet': 'An kashe ƙananan gargadi. Za a ci gaba da gargadi game da kwalbati, rami da okada.',
      'allWarningsOn': 'Duk gargadi sun kunna.',
      'notUnderstood': 'Yi haƙuri, ban ji ba.',
      'agentMuted': 'An kashe murya. Gargadin haɗari yana nan.',
      'agentUnmuted': 'Murya ta kunna.',
      'demoMode': 'Yanayin nuni',
      'connecting': 'Ana haɗawa',
      'listening': 'Ina sauraronka',
      'thinking': 'Ina tunani',
      'speaking': 'Ina magana',
      'offline': 'Babu haɗi. Taɓa sau biyu don sake gwadawa.',
      'micMuted': 'An kashe makirufo. Taɓa sau biyu don magana.',
      'modeHazard': 'Gargadin haɗari',
      'modeNavigation': 'Jagora',
      'screenHint': 'Taɓa sau biyu don magana. Ja ƙasa don kashe muryata. Riƙe don maimaitawa.',
    },
    AppLanguage.ig: {
      'hazardModeOn': 'Naanị ịdọ aka ná ntị maka ihe egwu.',
      'navNeedsNetwork': 'Nduzi chọrọ ịntanetị. Ịdọ aka ná ntị ka dị.',
      'minorQuiet': 'Agbanyụọla m obere ịdọ aka ná ntị. M ka ga-adọ gị aka ná ntị maka olulu mmiri, oghere na okada.',
      'allWarningsOn': 'Ịdọ aka ná ntị niile agbanwuola.',
      'notUnderstood': 'Ndo, anụghị m ya.',
      'agentMuted': 'Agbanyụọla olu. Ịdọ aka ná ntị ka dị.',
      'agentUnmuted': 'Olu agbanwuola.',
      'demoMode': 'Ọnọdụ ngosi',
      'connecting': 'Ọ na-ejikọ',
      'listening': 'Ana m anụ gị',
      'thinking': 'Ana m eche echiche',
      'speaking': 'Ana m ekwu okwu',
      'offline': 'Enweghị njikọ. Pịa ugboro abụọ ka ịnwaa ọzọ.',
      'micMuted': 'Igwe okwu agbanyụọla. Pịa ugboro abụọ ka ikwuo okwu.',
      'modeHazard': 'Ịdọ aka ná ntị',
      'modeNavigation': 'Nduzi',
      'screenHint': 'Pịa ugboro abụọ ka ikwuo okwu. Dọda ala ka igbanyụọ olu m. Jide ka m kwughachi.',
    },
  };
}
