import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lang.dart';

/// Styl hudby pro menu i hru.
enum MusicStyle { traditional, modern }

class SettingsService with ChangeNotifier {
  static final SettingsService I = SettingsService._();
  SettingsService._();

  // Defaults
  Lang _lang = Lang.cz;
  bool _musicOn = true;
  bool _vibrationOn = true;
  String _username = 'Anonymní Kelt #0001';
  String _version = '0.1.0+1';
  String? _characterId = 'augi';
  MusicStyle _musicStyle = MusicStyle.traditional; // ⬅️ NOVÉ: default

  // Keys
  static const _kLang = 'lang';
  static const _kMusicOn = 'musicOn';
  static const _kVibrationOn = 'vibrationOn';
  static const _kUsername = 'username';
  static const _kCharacterId = 'characterId';
  static const _kVersion = 'version';
  static const _kMusicStyle = 'musicStyle'; // ⬅️ NOVÉ

  // Migrace
  static const _kMusicDefaultMigratedV1 = 'music_default_migrated_v1';
  static const _kMusicForceOnMigratedV2 = 'music_force_on_migrated_v2';

  // Getters
  Lang get lang => _lang;
  bool get musicOn => _musicOn;
  bool get vibrationOn => _vibrationOn;
  String get username => _username;
  String get version => _version;
  String? get characterId => _characterId;
  MusicStyle get musicStyle => _musicStyle; // ⬅️ NOVÉ

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    // LANG
    final langRaw = prefs.get(_kLang);
    _lang = _parseLang(langRaw) ?? _lang;

    // MUSIC ON/OFF
    final hasMusicKey = prefs.containsKey(_kMusicOn);
    final musicRaw = prefs.get(_kMusicOn);
    final musicVal = _parseBool(musicRaw);

    if (!hasMusicKey) {
      // čistá instalace → default ON + uložit
      _musicOn = true;
      await prefs.setBool(_kMusicOn, true);
    } else if (musicVal != null) {
      _musicOn = musicVal;
    }

    // Migrace V1 – historický bug (vynutit ON jednou)
    final migratedV1 = prefs.getBool(_kMusicDefaultMigratedV1) ?? false;
    if (!migratedV1) {
      _musicOn = true;
      await prefs.setBool(_kMusicOn, true);
      await prefs.setBool(_kMusicDefaultMigratedV1, true);
    }

    // Migrace V2 – pokud i tak zůstala hudba vypnutá ve starých instancích, jednorázově ON
    final migratedV2 = prefs.getBool(_kMusicForceOnMigratedV2) ?? false;
    if (!migratedV2 && _musicOn == false) {
      _musicOn = true;
      await prefs.setBool(_kMusicOn, true);
      await prefs.setBool(_kMusicForceOnMigratedV2, true);
    }

    // MUSIC STYLE (Tradiční/Moderní) — default traditional
    final msRaw = prefs.get(_kMusicStyle);
    final ms = _parseMusicStyle(msRaw);
    if (ms != null) _musicStyle = ms;

    // VIBRATION
    final vibRaw = prefs.get(_kVibrationOn);
    final vibVal = _parseBool(vibRaw);
    if (vibVal != null) _vibrationOn = vibVal;

    // USERNAME
    final userRaw = prefs.get(_kUsername);
    final userStr = _parseString(userRaw);
    if (userStr != null && userStr.trim().isNotEmpty) {
      _username = userStr.trim();
    }

    // CHARACTER
    final charRaw = prefs.get(_kCharacterId);
    if (charRaw is String && charRaw.isNotEmpty) {
      _characterId = charRaw;
    } else if (charRaw is int) {
      _characterId = 'augi';
      await prefs.setString(_kCharacterId, _characterId!);
    }

    // VERSION
    final verRaw = prefs.get(_kVersion);
    final verStr = _parseString(verRaw);
    if (verStr != null && verStr.isNotEmpty) _version = verStr;

    // Persist v novém formátu (pro jistotu)
    await prefs.setString(_kLang, _lang == Lang.cz ? 'cz' : 'en');
    await prefs.setBool(_kMusicOn, _musicOn);
    await prefs.setBool(_kVibrationOn, _vibrationOn);
    await prefs.setString(_kUsername, _username);
    if (_characterId != null) {
      await prefs.setString(_kCharacterId, _characterId!);
    }
    await prefs.setString(_kVersion, _version);
    await prefs.setString(_kMusicStyle, // ⬅️ NOVÉ
        _musicStyle == MusicStyle.modern ? 'modern' : 'traditional');

    notifyListeners();
  }

  // Setters
  Future<void> setLang(Lang v) async {
    _lang = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLang, v == Lang.cz ? 'cz' : 'en');
    notifyListeners();
  }

  Future<void> setVibration(bool v) async {
    _vibrationOn = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kVibrationOn, v);
    notifyListeners();
  }

  Future<void> setMusic(bool v) async {
    _musicOn = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMusicOn, v);
    notifyListeners();
  }

  /// Nastaví styl hudby (tradiční/moderní) a uloží do SharedPreferences.
  Future<void> setMusicStyle(MusicStyle style) async {
    _musicStyle = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kMusicStyle,
      style == MusicStyle.modern ? 'modern' : 'traditional',
    );
    notifyListeners();
  }

  Future<void> setUsername(String v) async {
    _username = v.trim().isEmpty ? _username : v.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUsername, _username);
    notifyListeners();
  }

  Future<void> setCharacterId(String? id) async {
    _characterId = (id == null || id.isEmpty) ? 'augi' : id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCharacterId, _characterId!);
    notifyListeners();
  }

  // Helpers
  Lang? _parseLang(Object? raw) {
    if (raw == null) return null;
    if (raw is String) {
      switch (raw.toLowerCase()) {
        case 'cz':
        case 'cs':
          return Lang.cz;
        case 'en':
          return Lang.en;
      }
    }
    if (raw is int) return raw == 0 ? Lang.cz : Lang.en;
    return null;
  }

  bool? _parseBool(Object? raw) {
    if (raw == null) return null;
    if (raw is bool) return raw;
    if (raw is int) return raw != 0;
    if (raw is String) {
      final v = raw.toLowerCase().trim();
      if (v == 'true' || v == '1' || v == 'yes') return true;
      if (v == 'false' || v == '0' || v == 'no') return false;
    }
    return null;
  }

  String? _parseString(Object? raw) {
    if (raw == null) return null;
    if (raw is String) return raw;
    if (raw is int) return raw.toString();
    if (raw is bool) return raw ? 'true' : 'false';
    return null;
  }

  MusicStyle? _parseMusicStyle(Object? raw) {
    if (raw == null) return null;
    if (raw is MusicStyle) return raw;
    if (raw is String) {
      switch (raw.toLowerCase().trim()) {
        case 'modern':
          return MusicStyle.modern;
        case 'traditional':
        case 'tradicional':
        case 'tradicni':
        case 'tradiční':
        default:
          return MusicStyle.traditional;
      }
    }
    return null;
  }
}
