import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/app_mode.dart';
import '../models/language.dart';

class SavedPlace {
  const SavedPlace({required this.name, required this.lat, required this.lng});
  final String name;
  final double lat;
  final double lng;

  Map<String, Object> toJson() => {'name': name, 'lat': lat, 'lng': lng};
  static SavedPlace fromJson(Map<String, dynamic> j) => SavedPlace(
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
      );
}

/// Local preferences. Replaces BlindSpot's Backboard memory; nothing leaves the phone.
class PrefsService {
  PrefsService(this._p);
  final SharedPreferences _p;

  static Future<PrefsService> load() async => PrefsService(await SharedPreferences.getInstance());

  static const _kOnboarded = 'onboarded';
  static const _kLanguage = 'language';
  static const _kMode = 'last_mode';
  static const _kInstallId = 'install_id';
  static const _kPlaces = 'saved_places';

  bool get onboarded => _p.getBool(_kOnboarded) ?? false;
  Future<void> setOnboarded(bool v) => _p.setBool(_kOnboarded, v);

  AppLanguage get language => AppLanguage.fromCode(_p.getString(_kLanguage)) ?? AppLanguage.en;
  Future<void> setLanguage(AppLanguage l) => _p.setString(_kLanguage, l.code);

  AppMode get lastMode => AppMode.fromWire(_p.getString(_kMode));
  Future<void> setLastMode(AppMode m) => _p.setString(_kMode, m.wire);

  /// Random per-install id used only for rate limiting on the token server.
  String get installId {
    var id = _p.getString(_kInstallId);
    if (id == null) {
      id = const Uuid().v4().replaceAll('-', '');
      _p.setString(_kInstallId, id);
    }
    return id;
  }

  List<SavedPlace> get savedPlaces {
    final raw = _p.getString(_kPlaces);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => SavedPlace.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> setSavedPlaces(List<SavedPlace> places) =>
      _p.setString(_kPlaces, jsonEncode(places.map((p) => p.toJson()).toList()));
}
