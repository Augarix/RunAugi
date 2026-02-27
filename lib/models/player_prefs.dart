import 'dart:math';

class PlayerProfile {
  static final PlayerProfile I = PlayerProfile._();
  PlayerProfile._();

  int milesTotal = 0;

  String randomDivisionHex = _genHex();
  static String _genHex() {
    final r = Random();
    const chars = '0123456789abcdef';
    return List.generate(6, (_) => chars[r.nextInt(16)]).join();
  }

  void addMiles(int m) {
    milesTotal += m;
  }
}
