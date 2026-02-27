// Denní achievementy (3 viditelné + možnost přidat 2 navíc – bez reklamní logiky)
// Mile bonusy se přičítají při splnění.

import 'dart:math';
import '../models/player_prefs.dart';

enum AchId {
  finishEasy,          // 2
  finishMedium,        // 5
  finishHard,          // 25
  flawlessEasy,        // 5
  flawlessMedium,      // 10
  allInOneDay,         // 100
  fiveAchievements,    // 10 (progres 5)
  firstBlood,          // 1 (poprvé zemři)
  immortal,            // 10 (100x zemři)
  endlessBanners20,    // 10 (20 bannerů)
  speedRunnerEasy,     // 4 (Easy < 100 s)
}

class AchDef {
  final AchId id;
  final String nameCZ;
  final String nameEN;
  final String descCZ;
  final String descEN;
  final int milesReward;
  final int target; // 1 = binární

  AchDef(
      this.id,
      this.nameCZ,
      this.nameEN,
      this.descCZ,
      this.descEN,
      this.milesReward, {
        this.target = 1,
      });
}

class AchProgress {
  int value;
  final int target;
  AchProgress({this.value = 0, this.target = 1});
  bool get done => value >= target;
}

class AchLogic {
  static final AchLogic I = AchLogic._();
  AchLogic._() {
    _initDefs();
    rollToday();
  }

  final _r = Random();
  final Map<AchId, AchDef> defs = {};
  final Map<AchId, AchProgress> progress = {};
  List<AchId> today = [];
  bool _extrasUnlocked = false;

  void _initDefs() {
    void add(AchDef d) {
      defs[d.id] = d;
      // DŮLEŽITÉ: progress musí znát target z definice
      progress[d.id] = AchProgress(target: d.target);
    }

    add(AchDef(AchId.finishEasy, 'Dokonči lehkou', 'Finish Easy',
        'Dokonči level Easy.', 'Finish Easy level.', 2));
    add(AchDef(AchId.finishMedium, 'Dokonči střední', 'Finish Medium',
        'Dokonči level Medium.', 'Finish Medium level.', 5));
    add(AchDef(AchId.finishHard, 'Dokonči těžkou', 'Finish Hard',
        'Dokonči level Hard.', 'Finish Hard level.', 25));
    add(AchDef(AchId.flawlessEasy, 'Lehká bez ztráty života', 'Easy without death',
        'Dokonči Easy bez smrti.', 'Finish Easy without death.', 5));
    add(AchDef(AchId.flawlessMedium, 'Střední bez ztráty života', 'Medium without death',
        'Dokonči Medium bez smrti.', 'Finish Medium without death.', 10));
    add(AchDef(AchId.allInOneDay, 'Vše v jeden den', 'All difficulties in one day',
        'Dokonči Easy+Medium+Hard v jeden den.',
        'Finish Easy+Medium+Hard in one day.', 100));
    add(AchDef(AchId.fiveAchievements, 'Pět achievementů', 'Five achievements',
        'Dokonči 5 achievementů dnes.', 'Complete 5 achievements today.', 10,
        target: 5));
    add(AchDef(AchId.firstBlood, 'První krev', 'First blood', 'Poprvé zemři.',
        'Die for the first time.', 1));
    add(AchDef(AchId.immortal, 'Nesmrtelný', 'Immortal', 'Zemři 100×.',
        'Die 100 times.', 10,
        target: 100));
    add(AchDef(AchId.endlessBanners20, 'Běžec nekonečna', 'Endless runner',
        'Získej 20 bannerů v Endless.', 'Reach 20 banners in Endless.', 10,
        target: 20));
    add(AchDef(AchId.speedRunnerEasy, 'Speedrunner (Easy)', 'Speedrunner (Easy)',
        'Dokonči Easy do 100 s.', 'Finish Easy under 100 s.', 4));
  }

  void rollToday() {
    final pool = AchId.values.toList()..shuffle(_r);
    today = pool.take(3).toList();
    _extrasUnlocked = false;
    // reset pouze hodnot, cílové targety zůstávají
    for (final p in progress.values) {
      p.value = 0;
    }
  }

  List<AchId> visibleToday() {
    if (_extrasUnlocked && today.length < 5) {
      final pool =
      AchId.values.where((id) => !today.contains(id)).toList()..shuffle(_r);
      today = [...today, ...pool.take(2)];
    }
    return today;
  }

  // Volání této metody jen zapne 2 navíc bez reklam (dle požadavku: zatím vynechat reklamy)
  Future<void> unlockTwoExtraNoAds() async {
    if (_extrasUnlocked) return;
    _extrasUnlocked = true;
  }

  Future<void> restartOneNoAds(AchId id) async {
    final p = progress[id];
    if (p != null) p.value = 0;
  }

  void inc(AchId id, {int by = 1}) {
    final p = progress[id];
    if (p == null || p.done) return;
    p.value += by;
    if (p.done) {
      final def = defs[id];
      if (def != null) {
        PlayerProfile.I.addMiles(def.milesReward);
      }
    }
  }

  // Hooky:
  void onDeath() {
    inc(AchId.firstBlood);
    inc(AchId.immortal);
  }

  void onFinishEasy({required bool flawless}) {
    inc(AchId.finishEasy);
    if (flawless) inc(AchId.flawlessEasy);
    _checkAllInOneDay();
  }

  void onFinishMedium({required bool flawless}) {
    inc(AchId.finishMedium);
    if (flawless) inc(AchId.flawlessMedium);
    _checkAllInOneDay();
  }

  void onFinishHard() {
    inc(AchId.finishHard);
    _checkAllInOneDay();
  }

  void onEndlessBanner() {
    inc(AchId.endlessBanners20);
  }

  void _checkAllInOneDay() {
    if (progress[AchId.finishEasy]!.done &&
        progress[AchId.finishMedium]!.done &&
        progress[AchId.finishHard]!.done) {
      inc(AchId.allInOneDay);
    }
  }
}
