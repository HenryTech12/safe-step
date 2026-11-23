import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/demo/demo_source.dart';
import 'package:safestep/hazard/hazard_classes.dart';
import 'package:safestep/l10n/strings.dart';
import 'package:safestep/models/app_mode.dart';
import 'package:safestep/models/language.dart';
import 'package:safestep/services/prefs_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> readJson(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('every hazard class and side has an alert line in all five languages', () {
    final alerts = readJson('assets/alerts/alerts.json');
    final ids = [...HazardClass.values.map((c) => c.wire), 'side_left', 'side_right', 'side_ahead'];
    for (final id in ids) {
      for (final l in AppLanguage.values) {
        expect((alerts[id] as Map?)?[l.code], isA<String>(), reason: '$id/${l.code}');
      }
    }
  });

  test('onboarding prompts used after language choice exist in all languages', () {
    final p = readJson('assets/onboarding/prompts.json');
    for (final id in ['welcome', 'language_confirmed', 'camera_location', 'permissions_denied', 'tips_offer', 'tips']) {
      for (final l in AppLanguage.values) {
        expect((p[id] as Map)[l.code], isA<String>(), reason: '$id/${l.code}');
      }
    }
    for (final id in ['mic_request', 'mic_denied', 'choose_language', 'language_not_heard']) {
      expect((p[id] as Map)['en'], isA<String>());
    }
  });

  test('all UI strings exist in every language', () {
    for (final l in AppLanguage.values) {
      final s = Strings.of(l);
      for (final v in [s.connecting, s.listening, s.thinking, s.speaking, s.offline, s.micMuted, s.modeHazard,
          s.modeNavigation, s.screenHint, s.hazardModeOn, s.navNeedsNetwork, s.minorQuiet, s.allWarningsOn,
          s.notUnderstood, s.agentMuted, s.agentUnmuted, s.demoMode]) {
        expect(v, isNotEmpty);
      }
    }
  });

  test('model asset is present and plausible', () {
    final f = File('assets/models/yolov8n.tflite');
    expect(f.existsSync(), isTrue);
    expect(f.lengthSync(), greaterThan(3 * 1024 * 1024));
  });

  test('demo manifest parsing', () {
    final m = DemoManifest.parse('{"fps": 6, "frames": ["a.jpg", "b.jpg"]}');
    expect(m.fps, 6);
    expect(m.frames, ['a.jpg', 'b.jpg']);
    expect(DemoManifest.parse('{"frames": ["a.jpg"]}').fps, 5);
    expect(() => DemoManifest.parse('{"frames": []}'), throwsFormatException);
  });

  test('prefs: defaults, round trip, stable install id, saved places', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await PrefsService.load();
    expect(p.onboarded, isFalse);
    expect(p.language, AppLanguage.en);
    expect(p.lastMode, AppMode.hazardDetection);
    await p.setLanguage(AppLanguage.ha);
    await p.setLastMode(AppMode.navigation);
    await p.setSavedPlaces(const [SavedPlace(name: 'home', lat: 6.4, lng: 3.4)]);
    final id = p.installId;
    expect(RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(id), isTrue);
    final p2 = PrefsService(await SharedPreferences.getInstance());
    expect(p2.language, AppLanguage.ha);
    expect(p2.lastMode, AppMode.navigation);
    expect(p2.installId, id);
    expect(p2.savedPlaces.single.name, 'home');
  });
}
