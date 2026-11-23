import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/models/language.dart';

void main() {
  test('matches language names, loose spellings and native names', () {
    expect(matchLanguage('English please'), AppLanguage.en);
    expect(matchLanguage('pigin'), AppLanguage.pcm);
    expect(matchLanguage('Naija'), AppLanguage.pcm);
    expect(matchLanguage('Yorùbá'), AppLanguage.yo);
    expect(matchLanguage('I want Hausa.'), AppLanguage.ha);
    expect(matchLanguage('ibo'), AppLanguage.ig);
  });

  test('numbers map to tap order', () {
    expect(matchLanguage('3'), AppLanguage.yo);
    expect(matchLanguage('five'), AppLanguage.ig);
  });

  test('first spoken language wins; nothing heard is null', () {
    expect(matchLanguage('Igbo not English'), AppLanguage.ig);
    expect(matchLanguage(''), isNull);
    expect(matchLanguage(null), isNull);
    expect(matchLanguage('good morning'), isNull);
  });

  test('tap counts', () {
    expect(AppLanguage.fromTapCount(1), AppLanguage.en);
    expect(AppLanguage.fromTapCount(5), AppLanguage.ig);
    expect(AppLanguage.fromTapCount(6), isNull);
  });
}
