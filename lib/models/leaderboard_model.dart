// lib/models/leaderboard_model.dart
import 'dart:math';

class LBEntry {
  final String name;
  int miles;
  double km; // přesná vzdálenost v km (3 desetinná místa)
  LBEntry(this.name, this.miles, {this.km = 0.0});
}

class LeaderboardModel {
  static final LeaderboardModel I = LeaderboardModel._();
  LeaderboardModel._() {
    _seedNames();
  }

  final List<LBEntry> entries = [];
  final _r = Random();

  static const int _targetCount = 100;
  static const int _minAnonSeed = 30;

  void _seedNames() {
    const baseCeltic = [
      'Augarix','Isara','Eran','Sarika','Vella','Belenos',
      'Torcos','Rian','Maeva','Nantos','Drun','Catha',
      'Lugus','Ogmios','Cern','Nia','Alaun','Briana'
    ];

    const civilian = [
      'Jan Novák','Petr Svoboda','Lucie Dvořáková','Tomáš Král','Kateřina Horáková',
      'Martin Procházka','Anna Černá','Marek Jelínek','Tereza Malá','Jakub Veselý',
      'David Pokorný','Veronika Kovářová','Michaela Hájková','Filip Beneš','Barbora Sedláčková',
      'Jiří Kolář','Adéla Ševčíková','Ondřej Fiala','Eliška Smetanová','Matěj Holý',
      'Daniela Růžičková','Roman Blaha','Kristýna Urbanová','Vojtěch Havel','Nikola Kubíčková',
      'Pavel Beneš','Zuzana Doležalová','Richard Kučera','Monika Krátká','Štěpán Konečný',
      'John Miller','Emily Clark','Michael Brown','Olivia Davis','James Wilson',
      'Sophia Taylor','Daniel Anderson','Emma Thomas','William Moore','Ava Martin',
      'Noah Thompson','Isabella Garcia','Liam Martinez','Mia Robinson','Ethan Walker',
      'Amelia Young','Lucas Allen','Charlotte King','Benjamin Wright','Harper Scott',
      'Mateo Green','Chloe Baker','Leo Adams','Grace Nelson','Sofia Carter',
      'Oskar Kowalski','Anna Nowak','Lars Eriksen','Marta Johansson','Sven Karlsson'
    ];

    final taken = <String>{};

    void _addUnique(String name, int miles) {
      if (taken.add(name)) {
        // seed km: stejný rozsah jako miles ale jako km přímé (0–300 km by bylo moc)
        // Seed hráči mají 0–30 km – rozumný rozsah pro začátek hry
        final km = miles * 10.0; // seed: 0–300 → 0–3000 m (0–3 km)
        entries.add(LBEntry(name, miles, km: km));
      }
    }

    for (final n in baseCeltic) {
      _addUnique(n, _randMiles(topBias: 0.7));
    }

    final civShuffled = civilian.toList()..shuffle(_r);
    for (final n in civShuffled) {
      _addUnique(n, _randMiles(topBias: 0.35));
      if (entries.length >= _targetCount - _minAnonSeed) break;
    }

    int addedAnon = 0;
    while (addedAnon < _minAnonSeed) {
      final candidate = _anonName(rand: _r);
      if (!taken.contains(candidate)) {
        _addUnique(candidate, _randMiles(topBias: 0.2));
        addedAnon++;
      }
    }

    while (entries.length < _targetCount) {
      final candidate = _anonName(rand: _r);
      if (!taken.contains(candidate)) {
        _addUnique(candidate, _randMiles(topBias: 0.25));
      }
    }

    _boostSomeTop(5, minMiles: 180, maxMiles: 320);
    _sort();
  }

  int _randMiles({double topBias = 0.3}) {
    final base = _r.nextDouble();
    final biased = pow(base, 1.0 - topBias);
    return (biased * 300).round();
  }

  void _boostSomeTop(int count, {int minMiles = 180, int maxMiles = 320}) {
    if (entries.isEmpty) return;
    final idx = List.generate(entries.length, (i) => i)..shuffle(_r);
    for (var i = 0; i < count && i < idx.length; i++) {
      final e = entries[idx[i]];
      e.miles = minMiles + _r.nextInt((maxMiles - minMiles).clamp(1, 10000));
      e.km = e.miles * 10.0; // metry
    }
  }

  String generateDefaultAnonymousName() {
    final taken = entries.map((e) => e.name).toSet();
    int start = 1 + _r.nextInt(1000);
    for (int i = 0; i < 1000; i++) {
      final n = ((start + i - 1) % 1000) + 1;
      final candidate = 'Anonymní Kelt $n';
      if (!taken.contains(candidate)) return candidate;
    }
    int suffix = 1001;
    while (taken.contains('Anonymní Kelt $suffix')) suffix++;
    return 'Anonymní Kelt $suffix';
  }

  /// Aktualizuje hráče s přesnou vzdáleností v km.
  /// [miles] = pro PlayerProfile kompatibilitu
  /// [km] = přesná vzdálenost pro zobrazení v žebříčku
  String ensurePlayer(String playerName, int miles, {double? km}) {
    final effectiveName =
    (playerName.trim().isEmpty) ? generateDefaultAnonymousName() : playerName.trim();

    // km MUSÍ být předáno explicitně – žádný fallback na miles konverzi
    // Pokud km není předáno, zachovej stávající hodnotu nebo 0
    final i = entries.indexWhere((e) => e.name == effectiveName);
    if (i >= 0) {
      entries[i].miles = miles;
      if (km != null) entries[i].km = km; // aktualizuj km jen pokud přišlo
    } else {
      entries.add(LBEntry(effectiveName, miles, km: km ?? 0.0));
    }

    _sort();

    if (entries.length > _targetCount) {
      _trimKeeping(effectiveName);
    }

    return effectiveName;
  }

  void _trimKeeping(String keepName) {
    for (int idx = entries.length - 1; idx >= 0; idx--) {
      if (entries[idx].name != keepName) {
        entries.removeAt(idx);
        return;
      }
    }
  }

  /// Zpětně kompatibilní update – bez km (použije miles → km konverzi)
  void updatePlayer(String playerName, int miles, {double? km}) {
    ensurePlayer(playerName, miles, km: km);
  }

  int indexOf(String playerName) {
    return entries.indexWhere((e) => e.name == playerName);
  }

  void _sort() {
    entries.sort((a, b) {
      final byKm = b.km.compareTo(a.km); // řadit dle přesné vzdálenosti
      if (byKm != 0) return byKm;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  static String _anonName({Random? rand}) {
    final r = rand ?? Random();
    final n = 1 + r.nextInt(1000);
    return 'Anonymní Kelt $n';
  }
}