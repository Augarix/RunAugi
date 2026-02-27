// lib/models/leaderboard_model.dart
import 'dart:math';

class LBEntry {
  final String name;
  int miles;
  LBEntry(this.name, this.miles);
}

class LeaderboardModel {
  static final LeaderboardModel I = LeaderboardModel._();
  LeaderboardModel._() {
    _seedNames();
  }

  final List<LBEntry> entries = [];
  final _r = Random();

  // Cíl: ~100 záznamů v žebříčku
  static const int _targetCount = 100;

  // Kolik anonymních jmen min. přidat (zbytek doplní do 100)
  static const int _minAnonSeed = 30;

  /// Seed: mix původních „keltských“ přezdívek, civilních jmen a „Anonymní Kelt N“
  void _seedNames() {
    const baseCeltic = [
      'Augarix','Isara','Eran','Sarika','Vella','Belenos',
      'Torcos','Rian','Maeva','Nantos','Drun','Catha',
      'Lugus','Ogmios','Cern','Nia','Alaun','Briana'
    ];

    // Civilní jména (CZ/EN mix + pár mezinárodních, ať to vypadá „živě“)
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

    // Helper: přidá unikátní jméno se skóre
    void _addUnique(String name, int miles) {
      if (taken.add(name)) {
        entries.add(LBEntry(name, miles));
      }
    }

    // 1) Přidej „keltské“ přezdívky s vyšším rozptylem
    for (final n in baseCeltic) {
      _addUnique(n, _randMiles(topBias: 0.7));
    }

    // 2) Přidej civilní jména – různorodé skóre
    final civShuffled = civilian.toList()..shuffle(_r);
    for (final n in civShuffled) {
      _addUnique(n, _randMiles(topBias: 0.35));
      if (entries.length >= _targetCount - _minAnonSeed) break;
    }

    // 3) Přidej minimálně `_minAnonSeed` anonymů
    int addedAnon = 0;
    while (addedAnon < _minAnonSeed) {
      final candidate = _anonName(rand: _r);
      if (!taken.contains(candidate)) {
        _addUnique(candidate, _randMiles(topBias: 0.2));
        addedAnon++;
      }
    }

    // 4) Doplň do 100 záznamů anonymními jmény (unikátními)
    while (entries.length < _targetCount) {
      final candidate = _anonName(rand: _r);
      if (!taken.contains(candidate)) {
        _addUnique(candidate, _randMiles(topBias: 0.25));
      }
    }

    // 5) Pro „živější“ top: pár náhodných hráčů posuň výš
    _boostSomeTop(5, minMiles: 180, maxMiles: 320);

    _sort();
  }

  /// Náhodné míle s možností „bias“ k vyšším hodnotám (0..1)
  int _randMiles({double topBias = 0.3}) {
    // Směs uniform + lehká exponenciální preference k vyšším číslům
    final base = _r.nextDouble();
    final biased = pow(base, 1.0 - topBias); // vyšší bias => víc velkých čísel
    // Rozsah rozumných mil (tady 0..300)
    return (biased * 300).round();
  }

  /// Náhodně vybere pár záznamů a posune je do „vyšší ligy“
  void _boostSomeTop(int count, {int minMiles = 180, int maxMiles = 320}) {
    if (entries.isEmpty) return;
    final idx = List.generate(entries.length, (i) => i)..shuffle(_r);
    for (var i = 0; i < count && i < idx.length; i++) {
      final e = entries[idx[i]];
      e.miles = minMiles + _r.nextInt((maxMiles - minMiles).clamp(1, 10000));
    }
  }

  /// Vygeneruje unikátní "Anonymní Kelt N" (1..1000)
  String generateDefaultAnonymousName() {
    final taken = entries.map((e) => e.name).toSet();
    int start = 1 + _r.nextInt(1000);
    for (int i = 0; i < 1000; i++) {
      final n = ((start + i - 1) % 1000) + 1;
      final candidate = 'Anonymní Kelt $n';
      if (!taken.contains(candidate)) return candidate;
    }
    // fallback (kdyby byly všechny 1..1000 zabrané)
    int suffix = 1001;
    while (taken.contains('Anonymní Kelt $suffix')) {
      suffix++;
    }
    return 'Anonymní Kelt $suffix';
  }

  /// Zajistí, že hráč je v žebříčku. Pokud `playerName` je prázdné,
  /// vygeneruje "Anonymní Kelt N" a ten vrátí. Zároveň nastaví míle a seřadí.
  ///
  /// Returns: skutečné použité jméno (může být doplněné/nahrazené).
  String ensurePlayer(String playerName, int miles) {
    final effectiveName =
    (playerName.trim().isEmpty) ? generateDefaultAnonymousName() : playerName.trim();

    // Najdi / přidej hráče
    final i = entries.indexWhere((e) => e.name == effectiveName);
    if (i >= 0) {
      entries[i].miles = miles;
    } else {
      entries.add(LBEntry(effectiveName, miles));
    }

    _sort();

    // Udrž velikost na 100, ale NIKDY nesmaž hráče
    if (entries.length > _targetCount) {
      _trimKeeping(effectiveName);
    }

    return effectiveName;
  }

// Smaže nejnižší položku, která NENÍ 'keepName'
  void _trimKeeping(String keepName) {
    // Jdeme odspodu (nejnižší skóre) a smažeme první, který není hráč
    for (int idx = entries.length - 1; idx >= 0; idx--) {
      if (entries[idx].name != keepName) {
        entries.removeAt(idx);
        return;
      }
    }
    // Fallback: kdyby náhodou byl v listu jen hráč, nedělej nic
  }

  /// Klasický update (ponechán kvůli kompatibilitě)
  void updatePlayer(String playerName, int miles) {
    ensurePlayer(playerName, miles);
  }

  /// Index hráče v aktuálně seřazeném žebříčku; -1 když není
  int indexOf(String playerName) {
    return entries.indexWhere((e) => e.name == playerName);
  }

  void _sort() {
    entries.sort((a, b) {
      final byMiles = b.miles.compareTo(a.miles);
      if (byMiles != 0) return byMiles;
      // tie-breaker: abecedně
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  // Pomůcka: sestaví anonymní jméno
  static String _anonName({Random? rand}) {
    final r = rand ?? Random();
    final n = 1 + r.nextInt(1000); // 1..1000
    return 'Anonymní Kelt $n';
    // Alternativa s nulami: 'Anonymní Kelt ${n.toString().padLeft(4,'0')}'
  }
}
