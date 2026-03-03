import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:gif/gif.dart'; // ⬅️ pauzovatelné GIF pozadí

import '../achievements/ach_logic.dart';
import '../models/player_prefs.dart';
import '../models/leaderboard_model.dart';
import '../services/settings_service.dart';
import '../texty.dart';
import '../models/lang.dart'; // ← používáme jednotný Lang
import '../screens/ingame_settings.dart';
import '../services/music_service.dart'; // 🎵 MUSIC
import '../screens/run_select.dart';     // ⬅️ přechod na výběr obtížnosti

// ———————————————————————————————————————————————————————————
// Intro a typy
// ———————————————————————————————————————————————————————————
enum IntroPhase { ready, set, go, none }
enum ObstacleType { box, spike }

// ———————————————————————————————————————————————————————————
// Obstacle datový model
// ———————————————————————————————————————————————————————————
class Obstacle {
  final double x;            // světová X pozice levého okraje
  final double width;        // celková šířka
  final double height;       // výška (z "podlahy" vzhůru)
  final bool fromFloor;      // true = stojí na zemi (zatím vše)
  final ObstacleType type;   // BOX (walkable top, lethal on left side) / SPIKE (lethal always)

  const Obstacle({
    required this.x,
    required this.width,
    required this.height,
    required this.fromFloor,
    required this.type,
  });
}

class FlipMarker { final double atX; const FlipMarker(this.atX); }
class MirrorMarker { final double atX; final double untilX; const MirrorMarker(this.atX, this.untilX); }

// ———————————————————————————————————————————————————————————
// Base widget
// ———————————————————————————————————————————————————————————
abstract class GameBase extends StatefulWidget {
  final String modeName;           // EASY / MEDIUM / HARD / ENDLESS
  final Duration minIntro;
  final Duration length;
  final int milesOnFinish;
  final Duration checkpointFreq;
  final int speedPercent;

  /// Když true, po smrti hra zamrzne na místě a čeká na tap pro respawn.
  final bool stayDead;

  const GameBase({
    super.key,
    required this.modeName,
    required this.minIntro,
    required this.length,
    required this.milesOnFinish,
    required this.checkpointFreq,
    required this.speedPercent,
    this.stayDead = false,
  });
}

class GameBaseState<TW extends GameBase> extends State<TW>
    with SingleTickerProviderStateMixin {
  // ——— tuning & assets ———
  static const double baseSpeedPxPerSec = 520;
  static const double runnerRadius = 36;        // 2×
  static const double groundYFrac = 0.90;       // 10 % od spodku
  static const double ceilYFrac   = 0.10;       // 10 % od horní hrany

  // 🎞️ Pozadí – jeden GIF, který umíme play/pause
  static const String _bgGif  = 'assets/images/main_background.gif';

  static const String _readyImg    = 'assets/images/run/Ready.png';
  static const String _setImg      = 'assets/images/run/Set.png';
  static const String _goImg       = 'assets/images/run/Go.png';
  static const List<String> _runCycle = [
    'assets/images/run/Run1.png',
    'assets/images/run/Run2.png',
    'assets/images/run/Run3.png',
  ];
  static const String _jumpImg     = 'assets/images/run/Jump1.png';
  static const String _deathImg    = 'assets/images/run/Death.png';
  static const String _groundedImg = 'assets/images/run/Grounded.png'; // ⬅️ přidat do pubspec.yaml
  static const String _gearIcon    = 'assets/images/placeholder.png';  // tlačítko vpravo nahoře

  // Dlaždice
  static const double _tileW = 64.0;

  double gravity = 2200;
  double jumpVelocity = -820;
  bool gravityFlipped = false;

  late double speed;

  late int seed;
  late Random rng;
  late Timer loop;
  late DateTime startTime;
  Duration lastTick = Duration.zero;

  double worldX = 0;
  double lastCheckpointWorldX = 0;
  Duration nextCheckpointIn = Duration.zero;
  int checkpoints = 0;
  int deaths = 0;
  bool flawless = true;
  bool finished = false;
  bool paused = false;

  double runnerY = 0;
  double vy = 0;
  bool grounded = true;

  final List<Obstacle> obstacles = [];
  final List<FlipMarker> flips = [];
  final List<MirrorMarker> mirrors = [];
  bool mirroring = false;
  double mirrorUntilX = 0;

  IntroPhase _intro = IntroPhase.none; // první tap teprve spustí READY/SET/GO
  Timer? _introTimer;

  int _runFrame = 0;
  Timer? _runAnimTimer;

  DateTime? _lastDeathAt;

  // stayDead runtime
  bool _deadFrozen = false;

  // start flow
  bool _awaitFirstTap = true;
  bool _gameRunning = false;
  bool _queuedJump = false;

  // 🎞️ GIF controller
  late final GifController _bgGifCtrl;

  // ⛔️→🙂 Death → Grounded přepínač
  Timer? _deathStageTimer;

  // 🔥 precache guard + loading overlay
  bool _precached = false;
  bool _loading = true;

  bool get _shouldBgPlay =>
      _gameRunning && !paused && _intro == IntroPhase.none && !_deadFrozen && !finished;

  void _syncBgAnim() {
    if (!mounted) return;
    if (_shouldBgPlay) {
      // Normalizovaný rozsah 0..1, perioda celé smyčky:
      _bgGifCtrl.repeat(min: 0, max: 1, period: const Duration(seconds: 6));
    } else {
      // „pauza“ = stop na aktuálním frame
      _bgGifCtrl.stop();
    }
  }

  // ⤵️ precache všech důležitých assetů (běží jednou po mountu)
  Future<void> _precacheAll() async {
    if (_precached) return;
    _precached = true;

    final ctx = context;
    final providers = <ImageProvider>[
      const AssetImage(_bgGif),
      const AssetImage(_readyImg),
      const AssetImage(_setImg),
      const AssetImage(_goImg),
      const AssetImage(_jumpImg),
      const AssetImage(_deathImg),
      const AssetImage(_groundedImg),
      const AssetImage(_gearIcon),
      const AssetImage('assets/images/MT_start.png'),
      const AssetImage('assets/images/MT_mid.png'),
      const AssetImage('assets/images/MT_end.png'),
      ..._runCycle.map((p) => AssetImage(p)),
    ];

    for (final p in providers) {
      await precacheImage(p, ctx);
    }

    // Maskování načítání – celkem cca 7 s (5 s + 2 s navíc)
    await Future.delayed(const Duration(seconds: 7));
    if (mounted) setState(() => _loading = false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Zahřátí cache – zobrazí se pozadí i sprite bez zpoždění.
    _precacheAll();
  }

  @override
  void initState() {
    super.initState();
    _bgGifCtrl = GifController(vsync: this); // <- bez 'value'
    _bgGifCtrl.value = 0;                    // (volitelné) start na 0
    _bgGifCtrl.stop();                       // ať je na začátku pauza

    speed = baseSpeedPxPerSec * (widget.speedPercent / 100.0);
    _newSeed();     // 🎵 MUSIC: uvnitř lock + play herní hudby
    _start();       // timer jede, ale _gameRunning drží simulaci
    _startRunCycle();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncBgAnim());
  }

  @override
  void dispose() {
    _deathStageTimer?.cancel();
    _introTimer?.cancel();
    _runAnimTimer?.cancel();
    loop.cancel();
    _bgGifCtrl.dispose();
    // 🎵 MUSIC: ukonči herní hudbu
    // ignore: discarded_futures
    MusicService.I.stopGame();
    super.dispose();
  }

  // ———————————————————————————————————————————————————————————
  // Intro
  // ———————————————————————————————————————————————————————————
  void _startIntro() {
    setState(() => _intro = IntroPhase.ready);
    _syncBgAnim();
    _introTimer?.cancel();
    _introTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => _intro = IntroPhase.set);
      _syncBgAnim();
      _introTimer = Timer(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        setState(() => _intro = IntroPhase.go);
        _syncBgAnim();
        _introTimer = Timer(const Duration(milliseconds: 700), () {
          if (!mounted) return;
          _stickToGround();
          setState(() {
            _intro = IntroPhase.none;
            _gameRunning = true;
            startTime = DateTime.now();
            lastTick = Duration.zero;
          });
          _syncBgAnim();
          if (_queuedJump) {
            _queuedJump = false;
            _jump(); // provede se hned po GO
          }
        });
      });
    });
  }

  void _startRunCycle() {
    _runAnimTimer?.cancel();
    _runAnimTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted) return;
      if (finished || paused) return;
      if (_intro != IntroPhase.none) return;
      // Během loading overlaye animujeme běh kvůli efektu:
      if (!_gameRunning && !_loading) return;
      if (!grounded && !_loading) return;
      setState(() => _runFrame = (_runFrame + 1) % _runCycle.length);
    });
  }

  // ———————————————————————————————————————————————————————————
  // Seed a start smyčky
  // ———————————————————————————————————————————————————————————
  void _newSeed() {
    seed = DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF;
    rng = Random(seed);
    obstacles.clear();
    flips.clear();
    mirrors.clear();
    worldX = 0;
    lastCheckpointWorldX = 0;
    checkpoints = 0;
    deaths = 0;
    flawless = true;
    finished = false;
    nextCheckpointIn = widget.checkpointFreq;
    gravityFlipped = false;
    mirroring = false;
    mirrorUntilX = 0;

    _deadFrozen = false;
    _awaitFirstTap = true;
    _gameRunning = false;
    _queuedJump = false;
    _intro = IntroPhase.none;

    // 🎵 MUSIC: nový seed → nová skladba dle stylu, a hned přehrát herní track
    Future.microtask(() async {
      await MusicService.I.stopMenuMusic();
      await MusicService.I.onNewSeed(newSeed: seed);
      if (SettingsService.I.musicOn) {
        await MusicService.I.playGameTrackForLockedSeed();
      }
    });

    _syncBgAnim();
  }

  void _start() {
    startTime = DateTime.now();
    lastTick = Duration.zero;
    vy = 0;
    loop = Timer.periodic(const Duration(milliseconds: 16), _tick);
  }

  // ———————————————————————————————————————————————————————————
  // Generátor překážek: BOX & SPIKE s dlážděním start/mid/end
  // ———————————————————————————————————————————————————————————
  void _ensureGeneratedAhead(double targetX) {
    double genToX = obstacles.isEmpty ? 0 : obstacles.last.x + obstacles.last.width;
    if (genToX < targetX) genToX = targetX;

    final double endX = worldX + 4000;
    double cursor = genToX;

    final introMs = widget.minIntro.inMilliseconds;
    final totalMs = widget.length.inMilliseconds;
    final introFrac = totalMs == 0 ? 0.0 : introMs / totalMs;
    final introLimitX = introFrac * totalMs * (speed / 1000.0);

    // balistika
    final v0 = (-jumpVelocity).abs();
    final g = gravity.abs();
    final airT = (v0 / g) * 2.0;
    final reach = airT * speed;
    final apex = (v0 * v0) / (2.0 * g);

    // mezery
    const safety = 28.0;
    final minGapEasy = reach * 0.70 + safety;
    final maxGapEasy = minGapEasy * 1.6;

    // ✅ OPRAVA 4: max 8 překážek per volání – zabrání blokování herní smyčky
    int _genCount = 0;
    while (cursor < endX && _genCount < 8) {
      final placeX = cursor +
          (widget.modeName == 'EASY'
              ? (minGapEasy + rng.nextDouble() * (maxGapEasy - minGapEasy))
              : (120 + rng.nextInt(220)).toDouble());

      if (placeX <= introLimitX) {
        cursor = placeX + 1;
        continue;
      }

      // Rozhodnutí: platforma / překážka, box vs spike
      final makePlatform = rng.nextDouble() < 0.35; // delší BOX platforma
      if (makePlatform) {
        // BOX – delší běhatelný segment
        final w = 280.0 + rng.nextDouble() * 360.0;
        final h = 44.0 + rng.nextDouble() * 22.0;
        obstacles.add(Obstacle(
          x: placeX, width: w, height: h,
          fromFloor: true, type: ObstacleType.box,
        ));
        cursor = placeX + w * (0.6 + rng.nextDouble() * 0.5);
        _genCount++;
      } else {
        // Kratší překážka → BOX nebo SPIKE (SPIKE ~ 35 %), přitom férové limity
        final sideClear = runnerRadius * 2;
        final footClear = runnerRadius / 2;

        final maxFairW = max(48.0, reach * 0.60 - sideClear);
        final maxFairH = max(24.0, apex - footClear);

        double w = 96.0 + rng.nextDouble() * 64.0;   // 96..160
        double h = 44.0 + rng.nextDouble() * 20.0;   // 44..64
        w = w.clamp(48.0, maxFairW);
        h = h.clamp(24.0, maxFairH);

        final isSpike = rng.nextDouble() < 0.35;
        obstacles.add(Obstacle(
          x: placeX, width: w, height: h,
          fromFloor: true, type: isSpike ? ObstacleType.spike : ObstacleType.box,
        ));
        cursor = placeX + w * (0.6 + rng.nextDouble() * 0.5);
        _genCount++;
      }

      // HARD speciály (zachováno)
      if (widget.modeName == 'HARD') {
        if (rng.nextDouble() < 0.12) {
          flips.add(FlipMarker(placeX + 180.0 + rng.nextInt(220)));
        }
        if (rng.nextDouble() < 0.10) {
          final at = placeX + 240.0 + rng.nextInt(440);
          final len = 400.0 + rng.nextInt(600);
          mirrors.add(MirrorMarker(at.toDouble(), (at + len).toDouble()));
        }
      }
    }
  }

  // ———————————————————————————————————————————————————————————
  // Simulace
  // ———————————————————————————————————————————————————————————
  void _tick(Timer t) {
    if (paused || finished) return;
    if (!_gameRunning) return;

    final now = DateTime.now();
    final dt = now.difference(startTime) - lastTick;
    lastTick += dt;
    final dtSec = dt.inMicroseconds / 1e6;
    if (dtSec <= 0) return;

    worldX += speed * dtSec;

    if (widget.modeName == 'HARD') {
      for (final m in mirrors) {
        if (!mirroring && worldX >= m.atX && worldX < m.untilX) {
          mirroring = true;
          mirrorUntilX = m.untilX;
          break;
        }
      }
      if (mirroring && worldX >= mirrorUntilX) {
        mirroring = false;
        mirrorUntilX = 0;
      }
    }

    _ensureGeneratedAhead(worldX);

    nextCheckpointIn -= dt;
    if (nextCheckpointIn <= Duration.zero) {
      checkpoints++;
      lastCheckpointWorldX = worldX;
      nextCheckpointIn = widget.checkpointFreq;
      _onBanner();
    }

    // fyzika
    final gNow = gravity * (gravityFlipped ? -1.0 : 1.0);
    vy += gNow * dtSec;
    runnerY += vy * dtSec;
    _applyGroundCeilClamp();

    if (_collides()) {
      _onDeath();
      return;
    }

    if (now.difference(startTime) >= widget.length && widget.modeName != 'ENDLESS') {
      _finish();
      return;
    }

    if (widget.modeName == 'HARD') {
      for (final f in flips) {
        if (!gravityFlipped && worldX >= f.atX) {
          gravityFlipped = true;
          _stickToCeil();
        } else if (gravityFlipped && worldX >= f.atX + 240) {
          gravityFlipped = false;
          _stickToGround();
        }
      }
    }

    setState(() {});
  }

  // ———————————————————————————————————————————————————————————
  // „přilepení“
  // ———————————————————————————————————————————————————————————
  void _stickToGround() {
    final h = _screenH;
    final effective = _effectiveGroundY(h, _runnerWorldX);
    runnerY = effective - runnerRadius;
    vy = 0;
    grounded = true;
  }

  void _stickToCeil() {
    final h = _screenH;
    final ceil = _effectiveCeilY(h); // konstantní strop (10 %)
    runnerY = ceil + runnerRadius;
    vy = 0;
    grounded = true;
  }

  double get _runnerWorldX => worldX + 40;

  // „Zem“ z platforem: POUZE BOX (walkable)
  double _effectiveGroundY(double screenH, double runnerWorldX) {
    final baseGround = screenH * groundYFrac;
    double ground = baseGround;
    for (final ob in obstacles) {
      if (!ob.fromFloor || ob.type != ObstacleType.box) continue;
      if (runnerWorldX >= ob.x && runnerWorldX <= ob.x + ob.width) {
        final top = baseGround - ob.height;
        if (top < ground) ground = top;
      }
    }
    return ground;
  }

  double _effectiveCeilY(double screenH) => screenH * ceilYFrac;

  void _applyGroundCeilClamp() {
    final h = _screenH;
    final localGround = _effectiveGroundY(h, _runnerWorldX) - runnerRadius;
    final localCeil   = _effectiveCeilY(h) + runnerRadius;

    if (!gravityFlipped) {
      if (runnerY >= localGround) {
        runnerY = localGround;
        vy = 0;
        grounded = true;
      } else {
        grounded = false;
      }
      if (runnerY < localCeil) {
        runnerY = localCeil;
        vy = 0;
      }
    } else {
      if (runnerY <= localCeil) {
        runnerY = localCeil;
        vy = 0;
        grounded = true;
      } else {
        grounded = false;
      }
      if (runnerY > localGround) {
        runnerY = localGround;
        vy = 0;
      }
    }
  }

  // ———————————————————————————————————————————————————————————
  // Kolize: BOX (left-side lethal, top walkable) / SPIKE (any lethal)
  // ———————————————————————————————————————————————————————————
  bool _collides() {
    final runnerWorldFront = worldX + 40;
    final h = _screenH;
    final baseGround = h * groundYFrac;

    final rTop = runnerY - runnerRadius;
    final rBottom = runnerY + runnerRadius;
    final rLeftWorld = runnerWorldFront - runnerRadius;
    final rRightWorld = runnerWorldFront + runnerRadius;

    for (final ob in obstacles) {
      if (!ob.fromFloor) continue;
      if (ob.x > runnerWorldFront + 80) break;
      if (ob.x + ob.width < runnerWorldFront - 200) continue;

      final top = baseGround - ob.height;
      final bottom = baseGround;
      final oLeft = ob.x;
      final oRight = ob.x + ob.width;

      final overlapX = (rRightWorld >= oLeft) && (rLeftWorld <= oRight);
      final overlapY = (rBottom >= top) && (rTop <= bottom);
      if (!(overlapX && overlapY)) continue;

      if (ob.type == ObstacleType.spike) {
        // SPIKE: jakýkoli kontakt je smrt
        return true;
      } else {
        // BOX:
        // 1) stojíme právě na téhle platformě? → OK
        final currentGroundTop = _effectiveGroundY(h, _runnerWorldX);
        if ((currentGroundTop - top).abs() < 0.5 && grounded) {
          continue;
        }
        // 2) těsně nad hranou (přelet shora)? → toleruj
        final feet = rBottom;
        if (feet <= top + 6) {
          continue;
        }
        // 3) boční náraz: ❗smrtící pouze zleva
        final sideHitFromLeft  = (rLeftWorld < oLeft) && (rRightWorld > oLeft + 1);
        if (sideHitFromLeft) {
          return true;
        }
      }
    }
    return false;
  }

  // ———————————————————————————————————————————————————————————
  // Death / respawn
  // ———————————————————————————————————————————————————————————
  void _armGroundedAfterDeath() {
    _deathStageTimer?.cancel();
    _deathStageTimer = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      if (_deadFrozen) {
        setState(() {
          // jen přerender – build z _lastDeathAt vybere Grounded.png
        });
      }
    });
  }

  Future<void> _onDeath() async {
    if (finished) return;
    deaths++;
    flawless = false;
    AchLogic.I.onDeath();
    _lastDeathAt = DateTime.now();

    // ❄️ kompletní stop – čekáme na tap (po chvíli Death → Grounded)
    setState(() {
      paused = true;
      _deadFrozen = true;
      _gameRunning = false;
    });
    _syncBgAnim();
    _armGroundedAfterDeath(); // ⬅️ spustí přepnutí na Grounded
  }

  void _respawnToCheckpoint() {
    _deathStageTimer?.cancel();
    worldX = lastCheckpointWorldX;
    startTime = DateTime.now().subtract(widget.checkpointFreq * checkpoints);
    nextCheckpointIn = widget.checkpointFreq;
    _stickToGround();
    setState(() {
      _deadFrozen = false;
      paused = false;
      _gameRunning = true;
      _lastDeathAt = null;
    });
    _syncBgAnim();
  }

  // ———————————————————————————————————————————————————————————
  // Checkpoint / finish
  // ———————————————————————————————————————————————————————————
  void _onBanner() {
    if (widget.modeName == 'ENDLESS') {
      PlayerProfile.I.addMiles(5);
      AchLogic.I.onEndlessBanner();
      LeaderboardModel.I.updatePlayer(SettingsService.I.username, PlayerProfile.I.milesTotal);
    }
  }

  void _finish() {
    if (finished) return;
    finished = true;
    loop.cancel();
    _syncBgAnim();

    if (widget.milesOnFinish > 0) {
      PlayerProfile.I.addMiles(widget.milesOnFinish);
    }

    switch (widget.modeName) {
      case 'EASY':
        final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
        AchLogic.I.onFinishEasy(flawless: flawless);
        if (elapsedMs < 100000) AchLogic.I.inc(AchId.speedRunnerEasy);
        break;
      case 'MEDIUM': AchLogic.I.onFinishMedium(flawless: flawless); break;
      case 'HARD':   AchLogic.I.onFinishHard(); break;
      case 'ENDLESS': break;
    }

    LeaderboardModel.I.updatePlayer(SettingsService.I.username, PlayerProfile.I.milesTotal);
    _showFinishDialog();
  }

  void _showFinishDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(T.congrats()),
        content: Text(T.finished()),
        actions: [
          TextButton(onPressed: _goMenu,      child: Text(T.backToMenu())),
          TextButton(onPressed: _newRun,      child: Text(T.newRun())),
          TextButton(onPressed: _changeMode,  child: Text(T.changeMode())),
        ],
      ),
    );
  }

  void _goMenu() {
    Navigator.of(context).pop();
    Navigator.of(context).pop();
  }

  void _newRun() {
    Navigator.of(context).pop();
    setState(() {
      _newSeed(); // 🎵 MUSIC: uvnitř lock + play
      startTime = DateTime.now();
      lastTick = Duration.zero;
      loop.cancel();
      loop = Timer.periodic(const Duration(milliseconds: 16), _tick);
      _stickToGround();
      _awaitFirstTap = true;
      _gameRunning = false;
      _intro = IntroPhase.none;
    });
    _syncBgAnim();
  }

  /// 🔁 Změna obtížnosti → přejdi na RunSelect + hudba menu.
  void _changeMode() {
    // ignore: discarded_futures
    MusicService.I.stopGame().then((_) => MusicService.I.ensureMenuMusic());
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RunSelectScreen()),
    );
  }

  // ———————————————————————————————————————————————————————————
  // Ovládání
  // ———————————————————————————————————————————————————————————
  void _jump() {
    if (_loading) return; // během načítání nic nespouštěj

    // čekáme po smrti na tap? → respawn
    if (_deadFrozen) {
      _respawnToCheckpoint();
      return;
    }

    // první tap → start intro + queued jump
    if (_awaitFirstTap) {
      _awaitFirstTap = false;
      _queuedJump = true;
      _startIntro();
      return;
    }

    if (!_gameRunning || _intro != IntroPhase.none) return;

    // ✅ OPRAVA 1: setState okamžitě – vizuální odezva bez čekání na příští tick
    if (grounded) {
      setState(() {
        vy = gravityFlipped ? jumpVelocity.abs() : jumpVelocity;
        grounded = false;
      });
    }
  }

  void _openIngame() {
    if (_loading) return; // během načítání neotvírat
    setState(() => paused = true);
    _syncBgAnim();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => IngameSettingsModal(onAction: (cmd) {
        Navigator.of(context).pop();
        switch (cmd) {
          case IngameCommand.menu:       _goMenu(); break;
          case IngameCommand.newRun:     _newRun(); break;
          case IngameCommand.changeMode: _changeMode(); break;
          case IngameCommand.resetSeed:
            setState(() {
              _newSeed();
              startTime = DateTime.now();
              lastTick = Duration.zero;
            });
            _syncBgAnim();
            break;
        }
      }),
    ).then((_) {
      if (mounted) {
        setState(() => paused = false);
        _syncBgAnim();
      }
    });
  }

  void _devInstantWin() { if (!finished) _finish(); }

  double get _screenH => MediaQuery.of(context).size.height;

  // ———————————————————————————————————————————————————————————
  // Pomocné: sprite sady pro překážky
  // ———————————————————————————————————————————————————————————

  // BOX: přesně dané cesty bez /run/ prefixu
  ({List<String> start, List<String> mid, List<String> end}) _spriteSetFor(ObstacleType t) {
    if (t == ObstacleType.box) {
      return (
      start: ['assets/images/MT_start.png'],
      mid:   ['assets/images/MT_mid.png'],
      end:   ['assets/images/MT_end.png'],
      );
    } else {
      // SPIKE: dočasně placeholder (všechny části stejné)
      return (
      start: ['assets/images/placeholder.png'],
      mid:   ['assets/images/placeholder.png'],
      end:   ['assets/images/placeholder.png'],
      );
    }
  }

  // Bezpečný obrázek – nikdy nehodí ErrorWidget (když asset chybí → prázdno)
  Widget _safeImage(String asset, {BoxFit fit = BoxFit.fill}) {
    return Image.asset(
      asset,
      fit: fit,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  // Vrstvený fallback: vykreslí první dostupný (ostatní „zmizí“)
  Widget _layeredImages(List<String> assets, {BoxFit fit = BoxFit.fill}) {
    return Stack(
      fit: StackFit.expand,
      children: assets.map((a) => _safeImage(a, fit: fit)).toList(),
    );
  }

  // ———————————————————————————————————————————————————————————
  // Build
  // ———————————————————————————————————————————————————————————
  @override
  Widget build(BuildContext context) {
    if (runnerY == 0) {
      runnerY = MediaQuery.of(context).size.height * groundYFrac - runnerRadius;
    }

    final size = MediaQuery.of(context).size;
    final runnerScreenX = mirroring ? size.width * 0.70 : size.width * 0.30;

    // sprite – default run / intro / death / grounded
    String playerSprite = _runCycle[_runFrame];
    if (_intro != IntroPhase.none) {
      playerSprite = _intro == IntroPhase.ready ? _readyImg
          : _intro == IntroPhase.set   ? _setImg
          : _goImg;
    } else if (_deadFrozen) {
      // po smrti chvilku Death, pak Grounded (stojíme a čekáme na tap)
      final since = _lastDeathAt == null ? Duration.zero : DateTime.now().difference(_lastDeathAt!);
      playerSprite = since.inMilliseconds >= 250 ? _groundedImg : _deathImg;
    } else if (_lastDeathAt != null &&
        DateTime.now().difference(_lastDeathAt!) < const Duration(milliseconds: 200)) {
      playerSprite = _deathImg;
    } else if (!grounded) {
      playerSprite = _jumpImg;
    }

    // viditelné překážky jako dlaždice
    final obstacleWidgets = _buildVisibleObstacleTiles(size, runnerScreenX);

    return Scaffold(
      backgroundColor: Colors.black,
      floatingActionButton: FloatingActionButton(
        tooltip: 'Dokončit seed (DEV)',
        onPressed: _devInstantWin,
        child: const Icon(Icons.crop_square),
      ),
      body: GestureDetector(
        onTapDown: (_) => _jump(), // ✅ OPRAVA 2: onTapDown – reaguje při dotyku, ne při zvednutí prstu
        onLongPress: _openIngame,
        child: Stack(
          children: [
            // 🎞️ pozadí – jeden widget řízený controllerem
            Positioned.fill(
              child: SizedBox.expand(
                child: Gif(
                  controller: _bgGifCtrl,
                  autostart: Autostart.no,
                  image: const AssetImage(_bgGif),
                  fit: BoxFit.fill, // ⬅️ STEJNĚ JAKO MAIN MENU
                ),
              ),
            ),

            // lehké ztmavení kvůli čitelnosti
            Positioned.fill(child: Container(color: Colors.black.withOpacity(0.35))),

            // HUD & linky (zem/strop + checkpointy)
            CustomPaint(
              painter: _RunnerPainter(
                mode: widget.modeName,
                worldX: worldX,
                checkpoints: checkpoints,
                runnerY: runnerY,
                gravityFlipped: gravityFlipped,
                mirroring: mirroring,
                lengthMs: widget.length.inMilliseconds,
                introMs: widget.minIntro.inMilliseconds,
                speedPxPerSec: speed,
              ),
              child: const SizedBox.expand(),
            ),

            // Překážky (dlaždicované obrázky)
            ...obstacleWidgets,

            // Postavička (2×)
            Positioned(
              left: runnerScreenX - 72,
              top: (runnerY - 72),
              width: 144,
              height: 144,
              child: IgnorePointer(
                ignoring: true,
                child: Image.asset(playerSprite, fit: BoxFit.contain),
              ),
            ),

            // pravý horní roh – tlačítko do ingame settings
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 8,
              child: GestureDetector(
                onTap: _openIngame,
                child: Image.asset(_gearIcon, width: 32, height: 32, fit: BoxFit.contain),
              ),
            ),

            // 🔲 LOADING OVERLAY – černá obrazovka s běžícím Augarixem (cca 7 s)
            if (_loading)
              Positioned.fill(
                child: AbsorbPointer(
                  absorbing: true,
                  child: Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 160,
                            height: 160,
                            child: Image.asset(
                              _runCycle[_runFrame],
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            SettingsService.I.lang == Lang.cz
                                ? 'Generuji...'
                                : 'Generating...',
                            style: const TextStyle(
                              fontFamily: 'Augarix',
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ———————————————————————————————————————————————————————————
  // Dlaždicování překážek do viditelného okna
  // ———————————————————————————————————————————————————————————
  List<Widget> _buildVisibleObstacleTiles(Size size, double runnerScreenX) {
    final groundY = size.height * groundYFrac;
    final List<Widget> children = [];

    for (final ob in obstacles) {
      // projekce do obrazovky
      final dx = ob.x - worldX;
      final worldOffset = mirroring ? (size.width - runnerScreenX) : runnerScreenX;
      final screenX = mirroring ? (size.width - (worldOffset + dx)) : (worldOffset + dx);

      if (screenX > size.width + 256 || screenX + ob.width < -256) continue;

      final top = groundY - ob.height;

      // sprite set pro typ
      final s = _spriteSetFor(ob.type);
      final tiles = <Widget>[];

      // kolik dlaždic? (start + k×mid + end)
      final totalTiles = max(2, (ob.width / _tileW).ceil());
      final scaledTileH = ob.height; // height škálujeme na ob.height
      final scaledTileW = ob.width / totalTiles;

      for (int i = 0; i < totalTiles; i++) {
        final candidates = (i == 0)
            ? s.start
            : (i == totalTiles - 1 ? s.end : s.mid);

        tiles.add(Positioned(
          left: screenX + i * scaledTileW,
          top: top,
          width: scaledTileW,
          height: scaledTileH,
          child: _layeredImages(candidates, fit: BoxFit.fill),
        ));
      }

      children.addAll(tiles);
    }

    return children;
  }
}

// ———————————————————————————————————————————————————————————
// Painter: zem/strop + CP + drobný HUD (bez překážek)
// ———————————————————————————————————————————————————————————
class _RunnerPainter extends CustomPainter {
  final String mode;
  final double worldX;
  final int checkpoints;
  final double runnerY;
  final bool gravityFlipped;
  final bool mirroring;
  final int lengthMs;
  final int introMs;
  final double speedPxPerSec;

  _RunnerPainter({
    required this.mode,
    required this.worldX,
    required this.checkpoints,
    required this.runnerY,
    required this.gravityFlipped,
    required this.mirroring,
    required this.lengthMs,
    required this.introMs,
    required this.speedPxPerSec,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = const Color(0x22FFFFFF)..strokeWidth = 3;
    final groundY = size.height * GameBaseState.groundYFrac;
    final ceilY   = size.height * GameBaseState.ceilYFrac;

    // Zem + strop (vizuální linky)
    canvas.drawLine(Offset(0, groundY), Offset(size.width, groundY), line);
    canvas.drawLine(Offset(0, ceilY),   Offset(size.width, ceilY),
        Paint()..color = const Color(0x11FFFFFF)..strokeWidth = 2);

    // runner "ghost"
    final ghost = Paint()..color = const Color(0x22FFFFFF);
    final runnerScreenX = mirroring ? size.width * 0.70 : size.width * 0.30;
    canvas.drawCircle(Offset(runnerScreenX, runnerY), GameBaseState.runnerRadius, ghost);

    // checkpoint „bannery“
    final bannerP = Paint()..color = const Color(0x44FFFFFF);
    for (int i = 0; i < checkpoints; i++) {
      final x = runnerScreenX + (i + 1) * 160.0;
      canvas.drawRect(Rect.fromLTWH(x - 4, groundY - 60, 8, 120), bannerP);
    }

    // intro pruh (vizuální)
    final introW = (introMs / 1000.0) * speedPxPerSec * 0.6;
    canvas.drawRect(Rect.fromLTWH(0, groundY - 40, introW, 80),
        Paint()..color = const Color(0x22FFFFFF));

    // HUD (stručně)
    final hud = const TextStyle(color: Colors.white70, fontFamily: 'Augarix', fontSize: 12);
    _t(canvas, '$_hudMode  •  mirror:${mirroring ? 'ON' : 'OFF'}',
        const Offset(12, 12), hud);
    _t(canvas, 'CP:$checkpoints', Offset(size.width - 80, 12), hud);
    _t(canvas, 'Tap=skok  LongPress=menu', Offset(size.width - 200, size.height - 18),
        const TextStyle(color: Colors.white38, fontFamily: 'Augarix', fontSize: 12));
  }

  String get _hudMode => mode;

  void _t(Canvas c, String s, Offset p, TextStyle st) {
    final tp = TextPainter(text: TextSpan(text: s, style: st), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, p);
  }

  @override
  bool shouldRepaint(covariant _RunnerPainter o) =>
      o.worldX != worldX ||
          o.runnerY != runnerY ||
          o.checkpoints != checkpoints ||
          o.gravityFlipped != gravityFlipped ||
          o.mirroring != mirroring;
}