import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlayerProfile {
  static final PlayerProfile I = PlayerProfile._();
  PlayerProfile._();

  int milesTotal = 0;

  /// Kumulativní součet VŠECH nově nachozených metrů napříč obtížnostmi.
  /// Sčítá jen nově získané metry (rekordy), ne opakovaně ujeté úseky.
  /// Toto je hodnota zobrazená v leaderboardu (km sloupec).
  double metersTotal = 0;

  static const String _kMilesTotal   = 'player_miles_total';
  static const String _kMetersTotal  = 'player_meters_total_v1';

  String randomDivisionHex = _genHex();
  static String _genHex() {
    final r = Random();
    const chars = '0123456789abcdef';
    return List.generate(6, (_) => chars[r.nextInt(16)]).join();
  }

  /// Načti perzistované hodnoty (volat při startu appky).
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    milesTotal  = prefs.getInt(_kMilesTotal) ?? milesTotal;
    metersTotal = prefs.getDouble(_kMetersTotal) ?? metersTotal;
  }

  void addMiles(int m) {
    milesTotal += m;
    SharedPreferences.getInstance().then((p) => p.setInt(_kMilesTotal, milesTotal));
  }

  /// Přičti nově nachozené metry ke kumulativnímu součtu a perzistuj.
  void addMeters(double m) {
    if (m <= 0) return;
    final before = metersTotal;
    metersTotal += m;
    debugPrint('[METERS] addMeters(+$m) $before → $metersTotal');
    SharedPreferences.getInstance().then((p) => p.setDouble(_kMetersTotal, metersTotal));
  }
}