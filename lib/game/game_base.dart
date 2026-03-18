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

  /// Prefix grafické sady dlaždic: 'MT' → MT_start.png, MT_mid.png atd.
  /// HL = hills (easy), MT = mountains (medium), CT = city (hard), EN = endless
  final String spritePrefix;

  /// Minimální reakční čas mezi koncem překážky a začátkem další (v sekundách).
  /// Garantuje že hráč má dost času zareagovat.
  /// EASY=1.2s, MEDIUM=0.8s, HARD=0.5s, ENDLESS=0.8s
  final double reactionTimeSec;

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
    required this.spritePrefix,
    required this.reactionTimeSec,
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

  // Dlaždice – sprite rozměry (px, nativní velikost assetů)
  static const double _tileStartW = 16.0;  // MT_start / MT_end šířka
  static const double _tileEndW   = 16.0;
  static const double _tileMidW   = 25.0;  // MT_mid / MT_Fill šířka
  static const double _tileH      = 19.0;  // výška jedné řady

  // ── Škálování vizuálu ──────────────────────────────────────────
  // 1.0 = nativní, 2.0 = dvojnásobné, 0.5 = poloviční.
  // Hitboxy (fyzika, kolize) nejsou ovlivněny.
  static const double tileScale   = 1.25; // +25 % dle požadavku
  static const double runnerScale = 1.0;
  static const double spikeScale  = 3.25; // škálování spike (nezávislé na tileScale)

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
  DateTime? _lastGroundedAt; // ⏱ coyote time – čas posledního dotyku země

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

  // 🔁 Continuous jump při longpress
  Timer? _longJumpTimer;

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
      const AssetImage('assets/images/spike.png'),
      // Dlaždice aktuálního game modu (dle spritePrefix)
      AssetImage('assets/images/${widget.spritePrefix}_start.png'),
      AssetImage('assets/images/${widget.spritePrefix}_mid.png'),
      AssetImage('assets/images/${widget.spritePrefix}_fill.png'),
      AssetImage('assets/images/${widget.spritePrefix}_end.png'),
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
    _longJumpTimer?.cancel();
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
      if (!_gameRunning && !_loading) return;
      if (!grounded && !_loading) return;
      // Pokud game loop běží, setState přijde z _tick() – nezdvojujeme
      _runFrame = (_runFrame + 1) % _runCycle.length;
      if (!_gameRunning || _loading) setState(() {});
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

    // ── Mezery garantující reakční čas ────────────────────────
    // Minimální mezera = reactionTimeSec × speed (hráč musí mít čas zareagovat)
    // Mix krátkých (1.0–1.3×) a dlouhých (1.3–2.2×) mezer pro variabilitu levelu
    final reactionGap = widget.reactionTimeSec * speed;
    final maxFairW    = max(48.0, reach * 0.55 - runnerRadius * 2.2);

    // Výška překážky = počet vrstev × výška dlaždice
    // Vrstvy 2–5, ale před překážkou s vrstvami 4–5 musí být 1–2 vrstvy
    const minLayers = 2;
    const maxLayers = 5;
    const highThreshold = 4;   // 4–5 vrstev = "vysoká"
    const sTileHGen = _tileH * tileScale; // výška jedné vrstvy (px)

    // ── Tracking předchozí překážky ───────────────────────────
    int    lastLayers   = 1;    // vrstvy předchozí překážky (1 = jako zem)
    bool   lastWasBox   = true; // true = předchozí je BOX (lze odrazit)
    bool   lastWasSpike = false; // true = předchozí je spike → vynuť reakční mezeru
    int    lastMidCols  = 99;   // počet mid sloupců předchozí překážky
    double lastObEndX   = 0;    // světová X konce předchozí překážky

    // Balistika – dosah skoku z dané výšky (světové px)
    // fromHeight = výška odrazového místa nad zemí (px)
    // toHeight   = výška cílového místa nad zemí (px), 0 = zem
    // Vrátí horizontální dosah v px
    double _jumpReach(double fromHeight, double toHeight) {
      final screenH = _screenH;
      final groundY = screenH * groundYFrac;
      final fromY = (groundY - fromHeight) - runnerRadius;
      final toY   = toHeight > 0
          ? (groundY - toHeight) - runnerRadius
          : groundY - runnerRadius;
      final a = 0.5 * gravity;
      final b = jumpVelocity;
      final c = fromY - toY;
      final disc = b * b - 4 * a * c;
      if (disc < 0) return 0;
      final t = (-b + sqrt(disc)) / (2 * a);
      return t > 0 ? speed * t : 0;
    }

    // Počet mid sloupců pro danou šířku překážky
    int _midCols(double obWidth) {
      final sStartW = _tileStartW * tileScale;
      final sEndW   = _tileEndW   * tileScale;
      final sMidW   = _tileMidW   * tileScale;
      final inner   = obWidth - sStartW - sEndW;
      return inner > 0 ? (inner / sMidW).round().clamp(0, 999) : 0;
    }

    // ✅ max 8 překážek per volání – zabrání blokování herní smyčky
    int _genCount = 0;
    while (cursor < endX && _genCount < 8) {

      // ── Krok 1: Vygeneruj kandidáta překážky ──────────────────
      // (mezeru rozhodneme až po tom co víme co generujeme)
      final int maxAllowed = lastLayers >= highThreshold ? 2 : maxLayers;
      final int layers     = minLayers + rng.nextInt(maxAllowed - minLayers + 1);
      double obH           = layers * sTileHGen; // spike může přepsat

      final canSpike      = lastLayers < highThreshold && lastWasBox;
      final makeSpike     = canSpike && rng.nextDouble() < 0.20;
      final makePlatform  = !makeSpike && rng.nextDouble() < 0.30;

      double obW;
      ObstacleType obType;
      if (makeSpike) {
        // Spike šířka = spikeCount * sSpikeW aby hitbox přesně odpovídal vizuálu
        final sSpikeW    = _tileH * spikeScale;
        final rawW       = (30.0 + rng.nextDouble() * 50.0).clamp(24.0, maxFairW * 0.6);
        final spikeCount = (rawW / sSpikeW).round().clamp(1, 4);
        obW    = spikeCount * sSpikeW;        // přesná vizuální šířka
        obH    = _tileH * spikeScale;         // hitbox výška = vizuální výška spike
        obType = ObstacleType.spike;
      } else if (makePlatform) {
        obW    = (80.0 + rng.nextDouble() * 120.0).clamp(48.0, maxFairW * 1.2);
        obType = ObstacleType.box;
      } else {
        obW    = (40.0 + rng.nextDouble() * 60.0).clamp(32.0, maxFairW);
        obType = ObstacleType.box;
      }

      final obMidCols = obType == ObstacleType.box ? _midCols(obW) : 0;
      final obHasMid  = obMidCols > 0;

      // ── Krok 2: Rozhodnutí o mezeře ───────────────────────────
      // 70% šance na situaci B (skok z předchozí překážky)
      // 30% šance na situaci A (skok ze země)
      //
      // Situace B je validní pokud:
      //   B1: z vrcholu prev runner dosáhne na mid cílové překážky
      //   B2/B3: z vrcholu prev runner přeletí celou cílovou překážku
      // Situace A: vždy bezpečná (reactionGap + mezera)

      // Po spike je vždy vynucena situace A s plnou reakční mezerou
      final wantB   = !lastWasSpike && lastWasBox && rng.nextDouble() < 0.70;
      double clearGap;

      if (wantB) {
        // Zkus najít krátkou mezeru kde B1 nebo B2/B3 platí
        // Generuj mezeru 0.6–1.2× reactionGap (kratší než A)
        final gapB   = reactionGap * (0.6 + rng.nextDouble() * 0.6);
        final prevTopH = lastLayers * sTileHGen; // výška vrcholu prev překážky

        // Dosah z vrcholu předchozí na mid cílové (B1)
        final midOfTarget  = obH; // výška mid vrstvy = výška překážky
        final reachToMid   = _jumpReach(prevTopH, midOfTarget);
        // Dosah z vrcholu předchozí přes celou cílovou překážku (B2/B3)
        final reachOverAll = _jumpReach(prevTopH, 0.0);

        // Vzdálenost od konce prev k začátku mid cílové (za start dlaždicí)
        final sStartW = _tileStartW * tileScale;
        final sEndW   = _tileEndW   * tileScale;
        final midStartOffset = sStartW; // kde začíná mid v cílové překážce

        // B1: runner dosáhne na mid → gapB + midStartOffset <= reachToMid
        //     a zároveň gapB < reachToMid (nepřelétne celou)
        final b1ok = obHasMid &&
            (gapB + midStartOffset) <= reachToMid;

        // B2/B3: runner přeletí celou překážku → reachOverAll > gapB + obW
        final b2ok = reachOverAll > gapB + obW;

        if (b1ok || b2ok) {
          clearGap = gapB; // B situace validována
        } else if (obHasMid) {
          // Nemůžeme B s tímto gapB – prodluž mezeru aby B1 fungovalo
          final needed = reachToMid - midStartOffset;
          clearGap = needed.clamp(reactionGap * 0.6, reactionGap * 1.2);
        } else {
          // Cíl nemá mid a runner ho nepřelétne → fallback na A
          clearGap = reactionGap * (1.3 + rng.nextDouble() * 0.9);
        }
      } else {
        // Situace A: skok ze země, bezpečná mezera
        // Po spike vynuť minimálně 1.3× reactionGap (žádná zkratka)
        final minMult = lastWasSpike ? 1.3 : (1.3 + rng.nextDouble() * 0.9);
        final maxMult = lastWasSpike ? 1.3 + rng.nextDouble() * 0.7 : minMult;
        clearGap = reactionGap * (lastWasSpike ? maxMult : minMult);
      }

      final placeX = cursor + clearGap;

      if (placeX <= introLimitX) {
        cursor = placeX + 1;
        continue;
      }

      // ── Krok 3: Přidej překážku ────────────────────────────────
      obstacles.add(Obstacle(
        x: placeX, width: obW, height: obH,
        fromFloor: true, type: obType,
      ));
      cursor       = placeX + obW;
      lastObEndX   = cursor;
      lastLayers   = obType == ObstacleType.spike ? highThreshold : layers;
      lastWasBox   = obType == ObstacleType.box;
      lastWasSpike = obType == ObstacleType.spike;
      lastMidCols  = obMidCols;
      _genCount++;

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

    // Spike check – runner přistál shora na spike
    if (_touchingSpike()) {
      _onDeath();
      return;
    }

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

  // „Zem“ z platforem: BOX je walkable na celé šířce (včetně start/end vizulních dlazdic).
  // End dlazdice má stejný vršok jako mid → figurka po ní může běžat i seběhnout.
  double _effectiveGroundY(double screenH, double runnerWorldX) {
    final baseGround = screenH * groundYFrac;
    double ground = baseGround;

    for (final ob in obstacles) {
      if (!ob.fromFloor || ob.type != ObstacleType.box) continue;

      final obTop      = baseGround - ob.height;
      final sEndW      = _tileEndW * tileScale;
      // End dlaždice začíná zde (pravý okraj mid oblasti)
      final endStart   = ob.x + ob.width - sEndW;
      // Walkable oblast končí zde (runner může být ještě na end)
      final rightEdge  = ob.x + ob.width + runnerRadius;

      // Walkable oblast začíná až ZA start dlaždicí (start je smrtící)
      final sStartW  = _tileStartW * tileScale;
      final midStart = ob.x + sStartW; // začátek mid oblasti

      if (runnerWorldX < midStart || runnerWorldX > rightEdge) continue;

      if (runnerWorldX <= endStart) {
        // Plná výška (na mid části)
        if (obTop < ground) ground = obTop;
      } else {
        // End oblast – postupné klesání (úhel ~45°)
        final t = (runnerWorldX - endStart) / (rightEdge - endStart);
        final slope = obTop + t * (baseGround - obTop);
        if (slope < ground) ground = slope;
      }
    }
    return ground;
  }

  // Detekce spike kolize pro runner přistávající shora
  // Vrátí true pokud runner vstoupil do spike oblasti
  bool _touchingSpike() {
    final runnerWorldFront = worldX + 40;
    final h = _screenH;
    final baseGround = h * groundYFrac;
    final rBottom = runnerY + runnerRadius;
    final rTop    = runnerY - runnerRadius;
    final rLeft   = runnerWorldFront - runnerRadius;
    final rRight  = runnerWorldFront + runnerRadius;

    for (final ob in obstacles) {
      if (!ob.fromFloor || ob.type != ObstacleType.spike) continue;
      if (ob.x > runnerWorldFront + 80) break;
      if (ob.x + ob.width < runnerWorldFront - 200) continue;

      final top    = baseGround - ob.height;
      final bottom = baseGround;
      final overlapX = rRight >= ob.x && rLeft <= ob.x + ob.width;
      final overlapY = rBottom >= top && rTop <= bottom;
      if (overlapX && overlapY) return true;
    }
    return false;
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
        if (!grounded) _lastGroundedAt = DateTime.now(); // coyote time reset
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
        if (!grounded) _lastGroundedAt = DateTime.now(); // coyote time reset
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
        // 1) stojíme na téhle překážce (včetně slope end oblasti)? → OK
        // Pokud je runner grounded a effectiveGround odpovídá této překážce
        final currentGroundTop = _effectiveGroundY(h, _runnerWorldX);
        // currentGroundTop může být slope (end oblast) – porovnej s celým rozsahem ob
        final onThisOb = grounded &&
            currentGroundTop >= top - 1 &&
            currentGroundTop <= baseGround + 1;
        if (onThisOb) {
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
    _longJumpTimer?.cancel(); // zastav continuous jump při smrti
    _longJumpTimer = null;
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

    // Skok: okamžitá reakce bez čekání na tick.
    // Zkontroluj grounded přímo – žádné coyote time, žádné buffery.
    if (grounded) {
      setState(() {
        vy = gravityFlipped ? jumpVelocity.abs() : jumpVelocity;
        grounded = false;
        _lastGroundedAt = null;
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

  // Sprite cesty – složeny z prefixu předaného každým game modem.
  // Formát: assets/images/XX_start.png / XX_mid.png / XX_fill.png / XX_end.png
  ({String start, String mid, String fill, String end}) get _boxSprites {
    final p = widget.spritePrefix;
    return (
    start: 'assets/images/${p}_start.png',
    mid:   'assets/images/${p}_mid.png',
    fill:  'assets/images/${p}_fill.png',
    end:   'assets/images/${p}_end.png',
    );
  }

  // SPIKE: jeden řádek, bez fill vrstev
  static const _spikeSprites = (
  start: 'assets/images/spike.png',
  mid:   'assets/images/spike.png',
  fill:  'assets/images/spike.png',
  end:   'assets/images/spike.png',
  );

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
  // Progress bar
  // ———————————————————————————————————————————————————————————
  Widget _buildProgressBar(Size size) {
    // Pergamenová/béžová paleta
    const bgColor     = Color(0xBBD4B896);  // béžová s průhledností
    const fillColor   = Color(0xFF8B6914);  // tmavě zlatohnědá
    const borderColor = Color(0xFF6B4F0A);  // tmavší okraj
    const textColor   = Color(0xFF3B2A05);  // velmi tmavá béžová

    final barW = size.width * 0.60;
    const barH = 14.0;
    const radius = Radius.circular(7);

    // Progress 0..1 (ENDLESS = podle checkpointů, ostatní = čas)
    double progress;
    String label;
    if (widget.modeName == 'ENDLESS') {
      // Endless: zobraz počet checkpointů
      progress = (checkpoints % 10) / 10.0; // pulzuje každých 10 CP
      label = '${checkpoints} CP';
    } else {
      // Při smrti (_deadFrozen) zachovej progress na hodnotě z posledního ticku
      // Po respawnu (_respawnToCheckpoint) se startTime přepočítá dle checkpointu
      final elapsedMs = _gameRunning
          ? DateTime.now().difference(startTime).inMilliseconds
          : lastTick.inMilliseconds; // zmrazený čas = poslední tick před smrtí
      final total = widget.length.inMilliseconds;
      progress = (elapsedMs / total).clamp(0.0, 1.0);
      final pct = (progress * 100).round();
      label = '$pct %';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Bar
        Container(
          width: barW,
          height: barH,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.all(radius),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.all(radius),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress,
              child: Container(color: fillColor),
            ),
          ),
        ),
        const SizedBox(height: 2),
        // Label
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Augarix',
            fontSize: 10,
            color: textColor,
            shadows: [Shadow(color: Color(0x88FFFFFF), offset: Offset(0, 1), blurRadius: 2)],
          ),
        ),
      ],
    );
  }

  // ———————————————————————————————————————————————————————————
  // Build
  // ———————————————————————————————————————————————————————════
  @override
  Widget build(BuildContext context) {
    if (runnerY == 0) {
      runnerY = MediaQuery.of(context).size.height * groundYFrac - runnerRadius;
    }

    final size = MediaQuery.of(context).size;
    // Runner posunut dozadu (0.22) – více času reagovat na překážky
    final runnerScreenX = mirroring ? size.width * 0.78 : size.width * 0.22;

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
        onTapDown: (_) => _jump(),
        // Longpress = continuous jump (spam skoků dokud drží prst)
        onLongPressStart: (_) {
          _longJumpTimer?.cancel();
          _jump(); // okamžitý první skok
          _longJumpTimer = Timer.periodic(
            const Duration(milliseconds: 280),
                (_) => _jump(),
          );
        },
        onLongPressEnd: (_) {
          _longJumpTimer?.cancel();
          _longJumpTimer = null;
        },
        onLongPressCancel: () {
          _longJumpTimer?.cancel();
          _longJumpTimer = null;
        },
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

            // Postavička – škálovaná přes runnerScale
            Positioned(
              left: runnerScreenX - (runnerRadius * 2 * runnerScale),
              top:  runnerY       - (runnerRadius * 2 * runnerScale),
              width:  runnerRadius * 4 * runnerScale,
              height: runnerRadius * 4 * runnerScale,
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

            // ── Progress bar nahoře uprostřed ──────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: size.width * 0.20,
              right: size.width * 0.20,
              child: _buildProgressBar(size),
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

    // Škálované rozměry dlaždic (box)
    final sStartW = _tileStartW * tileScale;
    final sEndW   = _tileEndW   * tileScale;
    final sMidW   = _tileMidW   * tileScale;
    final sFillW  = _tileMidW   * tileScale;
    final sTileH  = _tileH      * tileScale;

    // Spike používá vlastní scale (spike.png je čtvercový – šířka = výška)
    final sSpikeW = _tileH * spikeScale;
    final sSpikeH = _tileH * spikeScale;

    for (final ob in obstacles) {
      final sp = ob.type == ObstacleType.box ? _boxSprites : _spikeSprites;
      final isSpike = ob.type == ObstacleType.spike;

      // Projekce do obrazovky – X pozice vrchní (mid) řady
      final dx = ob.x - worldX;
      final worldOffset = mirroring ? (size.width - runnerScreenX) : runnerScreenX;
      final screenX0 = mirroring
          ? (size.width - (worldOffset + dx))
          : (worldOffset + dx);

      // ── Spike: jednoduchý rendering (1 vrstva, vlastní scale) ──
      if (isSpike) {
        final spikeCount = max(1, (ob.width / sSpikeW).round());
        final actualW = spikeCount * sSpikeW;
        final spikeTop = groundY - sSpikeH;
        if (screenX0 > size.width + 256 || screenX0 + actualW < -256) continue;
        for (int s = 0; s < spikeCount; s++) {
          children.add(Positioned(
            left: screenX0 + s * sSpikeW,
            top: spikeTop,
            width: sSpikeW,
            height: sSpikeH,
            child: _safeImage(sp.mid, fit: BoxFit.fill),
          ));
        }
        continue; // spike hotový, přeskoč box rendering
      }

      // ── Box: počet mid dlaždic a fill řad ─────────────────────
      final midCols = max(1, ((ob.width - sStartW - sEndW) / sMidW).round());
      final fillRowCount = max(0, ((ob.height - sTileH) / sTileH).ceil());

      // Culling – použij nejlevější bod (spodní řada pyramidy)
      final leftmost  = screenX0 - fillRowCount * sFillW;
      final rightmost = screenX0 + sStartW + midCols * sMidW + sEndW;
      if (leftmost > size.width + 256 || rightmost < -256) continue;

      // ── Pyramid rendering: mid nahoře, fill řady dolů k zemi ──
      // mid (vrchol/nejužší): top = groundY - (fillRowCount+1)*sTileH
      // fill řada fillRowCount (těsně pod mid): top = groundY - fillRowCount*sTileH
      // fill řada 1 (základna/nejširší): top = groundY - sTileH

      // ── Řada 0: mid vrchol (start + mid×n + end) ──────────────
      final midTop = groundY - (fillRowCount + 1) * sTileH;
      double x = screenX0;
      children.add(Positioned(
        left: x, top: midTop, width: sStartW, height: sTileH,
        child: _safeImage(sp.start, fit: BoxFit.fill),
      ));
      x += sStartW;
      for (int m = 0; m < midCols; m++) {
        children.add(Positioned(
          left: x, top: midTop, width: sMidW, height: sTileH,
          child: _safeImage(sp.mid, fit: BoxFit.fill),
        ));
        x += sMidW;
      }
      children.add(Positioned(
        left: x, top: midTop, width: sEndW, height: sTileH,
        child: _safeImage(sp.end, fit: BoxFit.fill),
      ));

      // ── Fill řady: od mid dolů k základně ─────────────────────
      // Řada 1 (těsně pod mid) → řada fillRowCount (základna u země)
      // Každá řada dolů je širší o 1 fill na levé straně.
      // fill počet = celkový počet dlaždic řady nad ní
      int prevRowTotal = 1 + midCols + 1;

      for (int row = 1; row <= fillRowCount; row++) {
        // row=1 je těsně pod mid, row=fillRowCount je základna u země
        final rowY      = groundY - (fillRowCount - row + 1) * sTileH;
        final rowX      = screenX0 - row * sFillW;
        final fillCount = prevRowTotal;

        double fx = rowX;
        children.add(Positioned(
          left: fx, top: rowY, width: sStartW, height: sTileH,
          child: _safeImage(sp.start, fit: BoxFit.fill),
        ));
        fx += sStartW;
        for (int f = 0; f < fillCount; f++) {
          children.add(Positioned(
            left: fx, top: rowY, width: sFillW, height: sTileH,
            child: _safeImage(sp.fill, fit: BoxFit.fill),
          ));
          fx += sFillW;
        }
        children.add(Positioned(
          left: fx, top: rowY, width: sEndW, height: sTileH,
          child: _safeImage(sp.end, fit: BoxFit.fill),
        ));

        prevRowTotal = 1 + fillCount + 1;
      }
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
    // Painter záměrně prázdný – debug vizuály odstraněny
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