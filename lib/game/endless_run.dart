import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../achievements/ach_logic.dart';
import '../models/leaderboard_model.dart';
import '../models/player_prefs.dart';
import '../services/settings_service.dart';
import '../services/music_service.dart';
import '../screens/run_select.dart';
import '../texty.dart';
import '../models/lang.dart';
import '../widgets/parallax_bg.dart';
import 'game_base.dart' show GamePlayingScope;

// ─────────────────────────────────────────────────────────────
// Konstanty
// ─────────────────────────────────────────────────────────────
const double _kSpeed        = 572.0;
const double _kGravity      = 2200.0;
const double _kJumpVelocity = -820.0;
const double _kRunnerR      = 36.0;
const double _kGroundYFrac  = 0.90;
const double _kSpeedMps     = 6.0;
const double _kReactionSec  = 0.4; // kratší – pro mezery mezi platformami
const double _kFloorH       = _kFloorStepY;          // výška patra = _kFloorStepY
const double _kPlatformH    = _kRunnerR;              // výška platformy = výška runnera (vyplní prostor red→green)
const double _kMidW         = 48.0;                  // šířka jednoho bloku EN_mid (1365*36/1024)
const double _kMaxFloors    = 4; // max floor = 6 (kamera sleduje runnera)

// ── Tuning – mezery mezi platformami ─────────────────────────
// Mezera mezi platformami v ose X (vzdálenost mezi koncem jedné a začátkem další)
const double _kPlatGapMin   = 150.0; // minimální mezera v px
const double _kPlatGapMax   = 240.0; // maximální mezera v px
// Mezera v ose Y (výška jednoho patra v pixelech)
const double _kFloorStepY   = 100.0; // výška jednoho patra
// Délka platformy v blocích EN_mid
const int    _kPlatMinCols  = 5;     // minimum bloků
const int    _kPlatMaxCols  = 10;    // maximum bloků

// ─────────────────────────────────────────────────────────────
// Datové modely
// ─────────────────────────────────────────────────────────────
enum _PlatformType { normal, crossroads }

class _Platform {
  final double x;
  final double width;
  final int floor;
  final _PlatformType type;

  const _Platform({
    required this.x,
    required this.width,
    required this.floor,
    this.type = _PlatformType.normal,
  });

  double worldY(double screenH) {
    final groundY = screenH * _kGroundYFrac;
    // floor=0: spodní hrana platformy na red line → top = groundY - _kPlatformH
    // floor=1: o _kFloorH výš, atd.
    return groundY - _kPlatformH - floor * _kFloorH;
  }
}

// ─────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────
class EndlessRun extends StatefulWidget {
  const EndlessRun({super.key});

  static const String _seedKey       = 'level_seed_ENDLESS';
  static const String _checkpointKey = 'last_checkpoint_ENDLESS';
  static const String _elapsedKey    = 'last_elapsed_ms_ENDLESS';
  static const String _cpCountKey    = 'last_checkpoint_count_ENDLESS';
  static const String _bestKey       = 'best_worldx_v3_ENDLESS';

  @override
  State<EndlessRun> createState() => _EndlessRunState();
}

// ─────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────
class _EndlessRunState extends State<EndlessRun>
    with SingleTickerProviderStateMixin {

  // ── Herní stav ──────────────────────────────────────────────
  late Random _rng;
  late Timer _loop;
  late DateTime _startTime;
  Duration _lastTick = Duration.zero;

  double _worldX     = 0;
  double _runnerY    = 0;
  double _vy         = 0;
  bool   _grounded   = true;

  double _cameraY       = 0;
  double _targetCameraY = 0;

  // ── Platformy ────────────────────────────────────────────────
  final List<_Platform> _platforms = [];
  int  _genLastFloor  = 0;
  bool _genLastWasPit = false;

  // ── Checkpointy ──────────────────────────────────────────────
  double   _lastCheckpointX = 0;
  int      _checkpoints     = 0;
  Duration _nextCheckpoint  = const Duration(seconds: 30);

  // ── Score ────────────────────────────────────────────────────
  double _bestMeters    = 0;
  double _runMeters     = 0;
  int    _savedElapsedMs = 0;

  // ── Flow ─────────────────────────────────────────────────────
  bool      _awaitFirstTap  = true;
  bool      _isRestoring   = false; // true = obnovení seedu, false = nový seed
  bool      _gameRunning   = false;
  bool      _loading       = true;
  bool      _fell          = false;
  bool      _dead          = false;   // čelní náraz = death sekvence
  bool      _deadLanded    = false;
  bool      _forcedStick   = false; // ignoruj notTooLow při stickToGround
  bool      _wasJumping    = false;
  int       _currentFloor   = 0;    // aktuální floor na kterém runner stojí
  DateTime? _deadAt;
  int       _deadPhase     = 0;       // 0=death.png, 1=grounded.png, 2=pád
  bool      _introRunning  = false;
  String    _introSprite  = '';   // aktuální intro sprite (Ready/Set/Go)
  DateTime? _fellAt;
  DateTime? _lastGroundedAt;
  DateTime? _jumpBufferAt;
  int _groundLogFrame = 0;
  _Platform? _groundSource;
  int _lastLoggedFloor = -1;

  // ── Sprite ────────────────────────────────────────────────────
  int    _runFrame = 0;
  Timer? _runAnimTimer;

  static const List<String> _runCycle = [
    'assets/images/run/Run1.png', 'assets/images/run/Run2.png',
    'assets/images/run/Run3.png', 'assets/images/run/Run4.png',
    'assets/images/run/Run5.png', 'assets/images/run/Run6.png',
    'assets/images/run/Run7.png', 'assets/images/run/Run8.png',
  ];
  static const String _jumpImg     = 'assets/images/run/Jump1.png';
  static const String _readyImg    = 'assets/images/run/Ready.png';
  static const String _deathImg    = 'assets/images/run/Death.png';
  static const String _groundedImg = 'assets/images/run/Grounded.png';
  static const String _gearIcon    = 'assets/images/icon_settings.png';
  static const String _platformMid = 'assets/images/endless/EN_mid.png';

  // ── Parallax ─────────────────────────────────────────────────
  final ValueNotifier<bool> _bgPlaying = ValueNotifier(false);

  // ── Helpers ──────────────────────────────────────────────────
  double get _screenH      => MediaQuery.of(context).size.height;
  double get _screenW      => MediaQuery.of(context).size.width;
  double get _runnerScreenX => _screenW * 0.22;
  double get _runnerWorldX  => _worldX + 40;
  double get _groundY       => _screenH * _kGroundYFrac;

  // ─────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _loop = Timer.periodic(const Duration(milliseconds: 16), _tick);
    _startRunAnim();
    _loadOrGenerate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precache();
  }

  @override
  void dispose() {
    _loop.cancel();
    _runAnimTimer?.cancel();
    _bgPlaying.dispose();
    MusicService.I.stopGame();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // Precache
  // ─────────────────────────────────────────────────────────────
  bool _precached = false;
  Future<void> _precache() async {
    if (_precached) return;
    _precached = true;
    final ctx = context;
    for (final p in [
      ..._runCycle.map((s) => AssetImage(s)),
      const AssetImage(_jumpImg),
      const AssetImage(_readyImg),
      const AssetImage(_gearIcon),
      const AssetImage(_platformMid),
      const AssetImage('assets/images/endless/EN_bg1.png'),
      const AssetImage('assets/images/endless/EN_bg2.png'),
      const AssetImage('assets/images/endless/EN_bg3.png'),
    ]) { await precacheImage(p, ctx); }

    await Future.delayed(const Duration(seconds: 4));
    if (mounted) setState(() => _loading = false);
  }

  // ─────────────────────────────────────────────────────────────
  // Seed / persistence
  // ─────────────────────────────────────────────────────────────
  Future<void> _loadOrGenerate() async {
    final prefs = await SharedPreferences.getInstance();
    _bestMeters = prefs.getDouble(EndlessRun._bestKey) ?? 0;
    final saved = prefs.getInt(EndlessRun._seedKey);
    if (saved != null) {
      _isRestoring = true;
      _rng = Random(saved);
      final cp    = prefs.getDouble(EndlessRun._checkpointKey) ?? 0;
      final cpCnt = prefs.getInt(EndlessRun._cpCountKey) ?? 0;
      final elMs  = prefs.getInt(EndlessRun._elapsedKey) ?? 0;
      _lastCheckpointX = cp;
      _checkpoints     = cpCnt;
      _savedElapsedMs  = elMs;
      _worldX = 0;
      _generate(cp + 4000);
      _worldX = _spawnOnPlatform(cp);
      _runMeters = _worldX / _kSpeed * _kSpeedMps;
      if (mounted) _stickToGround();
    } else {
      final s = DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF;
      await prefs.setInt(EndlessRun._seedKey, s);
      _rng = Random(s);
      _generate(4000);
    }
    MusicService.I.stopMenuMusic();
    MusicService.I.onNewSeed(newSeed: _rng.nextInt(0x7FFFFFFF));
    if (SettingsService.I.musicOn) MusicService.I.playGameTrackForLockedSeed();
    if (mounted) setState(() {});
  }

  Future<void> _saveCheckpoint() async {
    final prefs = await SharedPreferences.getInstance();
    final elapsed = _gameRunning
        ? DateTime.now().difference(_startTime).inMilliseconds
        : _savedElapsedMs;
    await prefs.setDouble(EndlessRun._checkpointKey, _lastCheckpointX);
    await prefs.setInt(EndlessRun._cpCountKey, _checkpoints);
    await prefs.setInt(EndlessRun._elapsedKey, elapsed);
    debugPrint('SAVED checkpoint: worldX=${_lastCheckpointX.round()} elapsed=${elapsed}ms cp#$_checkpoints');
  }

  Future<void> _clearSave() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in [
      EndlessRun._seedKey, EndlessRun._checkpointKey,
      EndlessRun._cpCountKey, EndlessRun._elapsedKey, EndlessRun._bestKey,
    ]) { await prefs.remove(k); }
  }

  // ─────────────────────────────────────────────────────────────
  // Generátor
  // ─────────────────────────────────────────────────────────────
  void _generate(double targetX) {
    // Balistika – dosah skoku
    final v0       = _kJumpVelocity.abs();
    final airT     = (v0 / _kGravity) * 2.0;
    final maxReach = airT * _kSpeed; // max horizontální dosah skoku

    // Reakcní gap – min mezera aby hráč viděl překážku
    final reactionGap = _kReactionSec * _kSpeed;

    // Cursor = konec poslední platformy
    double cursor = _platforms.isEmpty
        ? 0
        : _platforms.last.x + _platforms.last.width;

    // ── První platforma vždy na ground ──────────────────────────
    if (_platforms.isEmpty) {
      final startW = 10 * _kMidW; // vždy 10 bloků
      _platforms.add(_Platform(x: 0, width: startW, floor: 0));
      cursor        = startW;
      _genLastFloor = 0;
      _genLastWasPit = false;
      debugPrint('=== ENDLESS GENERATE START ===');
      debugPrint('maxReach=$maxReach reactionGap=$reactionGap');
      debugPrint('startW=$startW cursor=$cursor targetX=$targetX');
    }

    int _safetyCount = 0;
    while (cursor < targetX && _safetyCount < 10000) {
      _safetyCount++;
      final lastFloor = _genLastFloor;

      // ── Propast: max 25% šance, jen na floor 0–1, ne dvakrát za sebou ──
      // Propast min 3000px od startu a ne hned po první platformě
      final canPit = !_genLastWasPit && lastFloor <= 1 && cursor > 3000;
      if (canPit && _rng.nextDouble() < 0.25) {
        // Max 75% dosahu skoku
        // Propast: 1–2 bloky = jistě přeskočitelná
        final pitW = _kMidW * (1 + _rng.nextInt(2)).toDouble(); // 48 nebo 96px
        cursor += pitW;
        _genLastWasPit = true;
        _genLastFloor  = 0; // po propasti vždy ground
        debugPrint('  PIT x=${(cursor-pitW).round()} w=${pitW.round()} maxReach=${maxReach.round()} pct=${(pitW/maxReach*100).round()}%');
        continue;
      }
      _genLastWasPit = false;

      // ── Směr: vždy ±1 patro ─────────────────────────────────────
      int nextFloor;
      if (lastFloor == 0) {
        // Ze ground – vždy nahoru o 1
        nextFloor = 1;
      } else if (lastFloor >= _kMaxFloors.toInt()) {
        // Z maxima – vždy dolů o 1
        nextFloor = lastFloor - 1;
      } else {
        // Uprostřed: 55% nahoru, 45% dolů (vždy ±1)
        nextFloor = _rng.nextDouble() < 0.55 ? lastFloor + 1 : lastFloor - 1;
      }

      // ── Rozcestí: 12% šance (ne na ground nebo max) ─────────────
      final isCrossroads = nextFloor > 0 &&
          nextFloor < _kMaxFloors.toInt() &&
          _rng.nextDouble() < 0.12;

      // ── Šířka platformy: 1–10 bloků, dynamická ──────────────────
      // Vyšší patro = kratší tendence, nižší = delší tendence
      final cols = _kPlatMinCols + _rng.nextInt(_kPlatMaxCols - _kPlatMinCols + 1);
      final platW = cols * _kMidW;

      // ── Mezera ───────────────────────────────────────────────────
      final floorDiff = (nextFloor - lastFloor);
      double gap;

      if (floorDiff > 0) {
        // Přechod nahoru: mezera pro skok
        // Musí být přeskočitelná: gap < maxReach
        // Gap počítáme od konce walkable plochy, ale slope přesahuje o _kFloorH
        // Přičti _kFloorH aby efektivní gap (za slope) byl aspoň _kPlatGapMin
        final effectiveMin = _kPlatGapMin + _kFloorH;
        final effectiveMax = _kPlatGapMax + _kFloorH;
        gap = effectiveMin + _rng.nextDouble() * (effectiveMax - effectiveMin);
        gap = gap.clamp(effectiveMin, effectiveMax.clamp(effectiveMin, maxReach * 0.85));
      } else if (floorDiff < 0) {
        // Přechod dolů: hráč může slézt po slope nebo skočit
        // Cílová platforma musí být dostatečně dlouhá → zajištěno platW
        // Mezera: kratší (slope dostihne) nebo delší (skok)
        final slopeOrJump = _rng.nextDouble() < 0.60; // 60% slope, 40% skok
        if (slopeOrJump) {
          // Slope: mezera = slope délka = přibližně floorDiff * _kFloorH
          // Slope: mezera musí být aspoň _kFloorH (délka slope)
          gap = (_kFloorH * floorDiff.abs()) * (0.8 + _rng.nextDouble() * 0.4);
          gap = gap.clamp(_kFloorH.toDouble(), _kPlatGapMax);
        } else {
          // Skok dolů: větší mezera
          gap = reactionGap * (1.0 + _rng.nextDouble() * 1.0);
          gap = gap.clamp(_kPlatGapMin, (_kPlatGapMax).clamp(_kPlatGapMin, maxReach * 0.75));
        }
      } else {
        // Stejné patro: normální mezera
        final effectiveMinS = _kPlatGapMin + _kFloorH;
        final effectiveMaxS = _kPlatGapMax + _kFloorH;
        gap = effectiveMinS + _rng.nextDouble() * (effectiveMaxS - effectiveMinS);
        gap = gap.clamp(effectiveMinS, effectiveMaxS.clamp(effectiveMinS, maxReach * 0.60));
      }

      final placeX = cursor + gap;

      // ── Přidej platformu ─────────────────────────────────────────
      _platforms.add(_Platform(
        x: placeX, width: platW, floor: nextFloor,
        type: isCrossroads ? _PlatformType.crossroads : _PlatformType.normal,
      ));

      // Rozcestí – T-křižovatka:
      // Spodní platforma normální délky (už přidána výše)
      // Horní platforma začíná uprostřed spodní → runner má čas se rozhodnout
      if (isCrossroads) {
        final upperFloor = (nextFloor + 2).clamp(0, _kMaxFloors.toInt());
        final clearance = _kFloorStepY * (upperFloor - nextFloor);
        if (clearance >= _kRunnerR * 2 + 20) {
          // Horní platforma začíná uprostřed spodní
          final upperStartX = placeX + platW * 0.5;
          final upperCols = (_kPlatMinCols + _rng.nextInt(_kPlatMaxCols - _kPlatMinCols + 1));
          final upperW = upperCols * _kMidW;
          _platforms.add(_Platform(
            x: upperStartX,
            width: upperW,
            floor: upperFloor,
            type: _PlatformType.crossroads,
          ));
          debugPrint('  CROSSROADS: lower x=${placeX.round()} w=${platW.round()} upper x=${upperStartX.round()} w=${upperW.round()} floor=$upperFloor');
        }
      }

      cursor        = placeX + platW;
      _genLastFloor = nextFloor;
      // Pojistka: cursor musí postoupit
      if (cursor <= _platforms.last.x + _kPlatGapMin) {
        cursor = _platforms.last.x + platW + _kPlatGapMin;
      }
      // Debug log všech platforem
      final actualCols = (platW / _kMidW).round();
      debugPrint('  plat[${_platforms.length}] x=${placeX.round()} w=${platW.round()} floor=$nextFloor gap=${gap.round()} cols=$cols actual=${actualCols}blk (${platW.round()}px)');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Fyzika
  // ─────────────────────────────────────────────────────────────
  // Najde Y pozici další platformy o patro níže než pl (bez cameraY)
  // Vrátí 99999 pokud žádná taková platforma není (= propast)
  double _nextPlatformTopY(_Platform pl, double screenH) {
    final targetFloor = pl.floor - 1;
    final slopeEnd = pl.x + pl.width + _kFloorH;
    for (final other in _platforms) {
      if (other == pl) continue;
      if (other.floor != targetFloor) continue;
      // Platforma musí začínat v oblasti slope
      if (other.x > slopeEnd + _kPlatGapMax) continue;
      if (other.x + other.width < pl.x + pl.width) continue;
      return other.worldY(screenH);
    }
    return 99999.0;
  }

  // Vrací fyzikální Y (BEZ _cameraY) – konzistentní s _runnerY
  // Renderer přidává _cameraY sám při kreslení platforem
  double _effectiveGroundY() {
    const noPlatform = 99999.0;
    _groundSource = null;
    final runnerBottom = _runnerY + _kRunnerR;
    double ground = noPlatform;

    for (final pl in _platforms) {
      if (pl.x > _runnerWorldX + 100) break;
      if (pl.x + pl.width < _runnerWorldX - 100) continue;
      if (_runnerWorldX < pl.x) continue;
      if (_runnerWorldX > pl.x + pl.width + _kFloorH + _kRunnerR) continue;

      // Fyzikální Y bez _cameraY
      final platTopY   = pl.worldY(_screenH); // BEZ _cameraY
      final slopeStart = pl.x + pl.width;
      final slopeEnd   = pl.x + pl.width + _kFloorH;

      double candidateY = noPlatform;

      if (_runnerWorldX <= slopeStart) {
        final tooHigh    = platTopY < runnerBottom - _kFloorStepY - _kRunnerR;
        final fallingDown = _vy >= -100;
        final notTooLow = _forcedStick || _runnerY <= platTopY;
        // Platforma smí chytit runnera pokud je runner nad ní nebo forcedStick
        final canLand = _forcedStick || (fallingDown && notTooLow);
        if ((_forcedStick || !tooHigh) && canLand) candidateY = platTopY;
      } else if (_runnerWorldX <= slopeEnd) {
        // Slope: chytí runnera jen pokud padá dolů (vy >= 0)
        // Pokud runner letí nahoru přes slope, ignoruj ji – nechej ho letět
        if (_vy >= 0 || _forcedStick) {
          final t = (_runnerWorldX - slopeStart) / (slopeEnd - slopeStart);
          final slopeY = platTopY + t * _kFloorH;
          final tooHighSlope = slopeY < runnerBottom - _kFloorStepY - _kRunnerR;
          if (!tooHighSlope) candidateY = slopeY;
        }
      }

      if (candidateY < ground) {
        ground = candidateY;
        _groundSource = pl;
      }
    }

    // Detekuj neočekávaný skok na vyšší platformu
    if (_gameRunning && _groundSource != null) {
      final newFloor = _groundSource!.floor;
      if (_lastLoggedFloor >= 0 && newFloor > _lastLoggedFloor && _vy >= -50) {
        final platTopDbg = _groundSource!.worldY(_screenH);
        final onWalkable = _runnerWorldX <= _groundSource!.x + _groundSource!.width;
        debugPrint('⚠️ UNEXPECTED FLOOR JUMP: floor $_lastLoggedFloor → $newFloor wx=${_runnerWorldX.round()} vy=${_vy.round()} grounded=$_grounded area=${onWalkable ? "WALKABLE" : "SLOPE"}');
        debugPrint('   runnerY=${_runnerY.round()} runnerBottom=${runnerBottom.round()} platTopPhys=${platTopDbg.round()} cameraY=${_cameraY.round()}');
        debugPrint('   notTooLow: runnerY=${_runnerY.round()} <= platTop+30=${(platTopDbg+_kFloorStepY*0.3).round()}');
        for (final pl in _platforms) {
          if ((pl.x - _runnerWorldX).abs() < 500) {
            debugPrint('   nearby plat: x=${pl.x.round()} w=${pl.width.round()} floor=${pl.floor}');
          }
        }
      }
      _lastLoggedFloor = newFloor;
    }

    // Aktualizuj _currentFloor
    if (ground < 9999 && _groundSource != null) {
      _currentFloor = _groundSource!.floor;
    }

    // Log každých 30 framů
    _groundLogFrame++;
    if (_groundLogFrame % 30 == 0 && _gameRunning) {
      final wx = _runnerWorldX.round();
      if (ground < 9999 && _groundSource != null) {
        final pl = _groundSource!;
        final onSlope = _runnerWorldX > pl.x + pl.width;
        final posOnPlat = (_runnerWorldX - pl.x).round();
        final platEnd = (pl.x + pl.width).round();
        debugPrint('RUN wx=$wx floor=${pl.floor} y=${ground.round()} '
            'onSlope=$onSlope vy=${_vy.round()} grounded=$_grounded '
            'platX=${pl.x.round()}..${platEnd} posOnPlat=${posOnPlat}px '
            'wasJumping=$_wasJumping');
      } else {
        debugPrint('RUN wx=$wx NO_PLATFORM vy=${_vy.round()} '
            'runnerY=${_runnerY.round()} lastFloor=$_currentFloor');
      }
    }
    return ground;
  }


  void _stickToGround() {
    _forcedStick = true;
    final g = _effectiveGroundY();
    _forcedStick = false;
    final prevY = _runnerY;
    _runnerY = (g >= 9999 ? _groundY : g) - _kRunnerR;
    debugPrint('STICK: g=${g < 9999 ? g.round() : "none"} prevRunnerY=${prevY.round()} newRunnerY=${_runnerY.round()} groundSource=${_groundSource?.floor} wx=${_runnerWorldX.round()}');
    _vy      = 0;
    _grounded = true;
  }

  void _applyPhysics(double dtSec) {
    _vy      += _kGravity * dtSec;
    _vy       = _vy.clamp(-2000.0, 2000.0); // max rychlost pádu (anti-tunneling)
    _runnerY += _vy * dtSec;

    final groundY = _effectiveGroundY();
    if (groundY >= 9999) {
      _grounded = false;
      return;
    }

    final localGround = groundY - _kRunnerR;
    final onSlope = _groundSource != null &&
        _runnerWorldX > _groundSource!.x + _groundSource!.width;

    // Na slope: omez silný skok ale JEN pokud runner stojí na slope
    if (onSlope && _grounded && _vy < -200) {
      debugPrint('SLOPE_LIMIT wx=${_runnerWorldX.round()} vy_before=${_vy.round()} → 0 '
          'floor=$_currentFloor runnerY=${_runnerY.round()}');
      _vy = 0;
    }

    // Na slope: aktualizuj _lastGroundedAt aby coyote time fungoval po opuštění slope
    if (onSlope) {
      _lastGroundedAt = DateTime.now();
      if (!_grounded) {
        // Runner letí přes slope ve vzduchu – IGNORUJ slope Y, nech fyziku
        // ale zabrání slope akceleraci nahoru (slope nesmí přidat vertikální rychlost)
        // Slope Y klesá → kdyby runner "přistál" na slope, byl by vytlačen nahoru
        // Řešení: pokud je runner nad slope Y, nechej ho letět normálně
        // Slope jen poskytne ground když runner padá NA ni (vy > 0)
        if (_vy < 0) {
          // Runner letí nahoru přes slope – odstraň slope z ground výpočtu
          // tím že necháme ground = 99999 pro slope oblast při letu nahoru
          // (implementováno v _effectiveGroundY níže)
        }
      }
    }

    // Přistání: runner musí být dostatečně blízko povrchu
    final snapTol = (_vy.abs() * 0.016).clamp(2.0, 30.0);

    if (_runnerY >= localGround) {
      _runnerY = localGround;
      _vy      = 0;
      if (!_grounded) _lastGroundedAt = DateTime.now();
      _grounded = true;
      // Reset _wasJumping jen na walkable ploše, ne na slope
      final onSlopeNow = _groundSource != null &&
          _runnerWorldX > _groundSource!.x + _groundSource!.width;
      if (!onSlopeNow) _wasJumping = false;
    } else if (_runnerY >= localGround - snapTol && _vy >= 0) {
      _runnerY = localGround;
      _vy      = 0;
      if (!_grounded) _lastGroundedAt = DateTime.now();
      _grounded = true;
      final onSlopeNow = _groundSource != null &&
          _runnerWorldX > _groundSource!.x + _groundSource!.width;
      if (!onSlopeNow) _wasJumping = false;
    } else {
      _grounded = false;
    }
  }

  bool _isFalling() => _runnerY - _kRunnerR > _screenH + 20;

  bool _collidesWithPlatform() {
    final front = _runnerWorldX + _kRunnerR * 0.8;
    final rTop  = _runnerY - _kRunnerR;
    final rBot  = _runnerY + _kRunnerR;

    for (final pl in _platforms) {
      if (pl.x > front + 50) break;
      if (pl.x + pl.width < front - 200) continue;

      // Fyzikální Y bez _cameraY
      final platTopY = pl.worldY(_screenH);
      final platBotY = platTopY + _kPlatformH;

      if (rBot <= platTopY + 6) continue;
      if (rTop >= platBotY) continue;
      if (_grounded && _runnerY <= platTopY) continue;
      // Přeskoč platformu na které runner stojí
      if (_groundSource == pl) continue;

      final hitFront = front >= pl.x && front <= pl.x + _kRunnerR * 1.5;
      if (hitFront) {
        debugPrint('COLLIDE wx=${_runnerWorldX.round()} front=${front.round()} '
            'pl.x=${pl.x.round()} floor=${pl.floor} '
            'platTop=${platTopY.round()} rTop=${rTop.round()} rBot=${rBot.round()} '
            'grounded=$_grounded groundSource=${_groundSource?.floor}');
        return true;
      }
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────
  // Safe spawn
  // ─────────────────────────────────────────────────────────────
  void _updateCamera() {
    final targetRunnerScreenY = _screenH * 0.65;
    _targetCameraY = targetRunnerScreenY - _runnerY;
    if (_targetCameraY < 0) _targetCameraY = 0;
    _cameraY += (_targetCameraY - _cameraY) * 0.10;
  }

  double _spawnOnPlatform(double spawnX) {
    for (final pl in _platforms) {
      if (pl.x + pl.width < spawnX) continue;
      final minGap = _kReactionSec * _kSpeed;
      final safeX = pl.x + minGap;
      if (safeX < pl.x + pl.width - minGap) {
        return safeX - 40;
      }
    }
    return _safeSpawnX(spawnX);
  }

  double _safeSpawnX(double spawnX) {
    final minGap = _kReactionSec * _kSpeed * 2.0;
    for (int i = 0; i < 50; i++) {
      final front = spawnX + 40;
      bool safe = true;
      for (final pl in _platforms) {
        if (pl.x + pl.width < front) continue;
        if (pl.x > front + minGap) break;
        if (pl.x > front && pl.x - front < minGap) {
          spawnX = pl.x - minGap - 40;
          safe = false;
          break;
        }
      }
      if (safe) break;
    }
    return spawnX;
  }

  // ─────────────────────────────────────────────────────────────
  // Tick
  // ─────────────────────────────────────────────────────────────
  void _tick(Timer t) {
    if (!_gameRunning && !_dead) return;

    final now   = DateTime.now();
    final dt    = now.difference(_startTime) - _lastTick;
    _lastTick  += dt;
    final dtSec = dt.inMicroseconds / 1e6;
    if (dtSec <= 0) return;

    // Death sekvence po čelním nárazu
    if (_dead) {
      final sinceDeadMs = _deadAt == null ? 0 : now.difference(_deadAt!).inMilliseconds;
      if (_deadPhase == 0) {
        if (sinceDeadMs >= 800) {
          _vy = 0;
          _grounded = false;
          _deadPhase = 1;
          debugPrint('DEAD → phase 1: runnerY=${_runnerY.round()} (pád z death pozice)');
          setState(() {});
        }
      } else if (_deadPhase == 1) {
        _vy += _kGravity * dtSec;
        _vy = _vy.clamp(-2000.0, 2000.0);
        _runnerY += _vy * dtSec;
        final g = _effectiveGroundY();
        debugPrint('DEAD phase1: runnerY=${_runnerY.round()} vy=${_vy.round()} groundY=${g < 9999 ? g.round() : "none"} screenBottom=${_screenH.round()}');

        // Přistání na walkable platformě
        _Platform? landPlat;
        double landGroundY = 0;
        for (final pl in _platforms) {
          if (_runnerWorldX < pl.x || _runnerWorldX > pl.x + pl.width) continue;
          final platTopY = pl.worldY(_screenH);
          if (platTopY > landGroundY) {
            landGroundY = platTopY;
            landPlat = pl;
          }
        }
        if (landPlat != null && _runnerY + _kRunnerR >= landGroundY) {
          _runnerY = landGroundY - _kRunnerR;
          _vy = 0;
          _grounded = true;
          _deadPhase = 2;
          _deadLanded = true;
          debugPrint('DEAD_LANDED floor=${landPlat.floor} runnerY=${_runnerY.round()} groundY=${landGroundY.round()} wx=${_runnerWorldX.round()} cameraY=${_cameraY.round()}');
        } else if (_runnerY > _screenH + 60) {
          _deadPhase = 2;
          debugPrint('DEAD → phase 2 (off screen runnerY=${_runnerY.round()} > ${(_screenH+60).round()})');
        }
      }
      setState(() {});
      return;
    }

    // Pád – čekej na tap
    if (_fell) {
      setState(() {});
      return;
    }

    _worldX    += _kSpeed * dtSec;
    _runMeters  = _worldX / _kSpeed * _kSpeedMps;

    _generate(_worldX + 4000);

    // Checkpoint každých 30s
    _nextCheckpoint -= dt;
    if (_nextCheckpoint <= Duration.zero) {
      _checkpoints++;
      _nextCheckpoint = const Duration(seconds: 30);
      if (_grounded && _effectiveGroundY() < 9999) {
        final safeX = (_worldX - _kPlatGapMin * 2).clamp(0.0, _worldX);
        _lastCheckpointX = safeX;
        _saveCheckpoint();
        debugPrint('CHECKPOINT #$_checkpoints at worldX=${safeX.round()}');
      } else {
        debugPrint('CHECKPOINT #$_checkpoints SKIPPED (not grounded)');
      }
      PlayerProfile.I.addMiles(5);
      AchLogic.I.onEndlessBanner();
      LeaderboardModel.I.updatePlayer(
        SettingsService.I.username, PlayerProfile.I.milesTotal, km: _bestMeters,
      );
    }

    _applyPhysics(dtSec);

    // Jump buffer
    if (_jumpBufferAt != null && _grounded) {
      final sinceBuffer = now.difference(_jumpBufferAt!).inMilliseconds;
      if (sinceBuffer <= 180) {
        _vy = _kJumpVelocity;
        _grounded = false;
        _wasJumping = true;
        _lastGroundedAt = null;
      }
      _jumpBufferAt = null;
    }

    // Čelní náraz = death sekvence
    if (_collidesWithPlatform()) {
      debugPrint('COLLISION → DEAD wx=${_worldX.round()} runnerY=${_runnerY.round()} floor=$_currentFloor cameraY=${_cameraY.round()} vy=${_vy.round()}');
      for (final pl in _platforms) {
        if ((pl.x - _runnerWorldX).abs() < 300) {
          debugPrint('  near plat: x=${pl.x.round()} w=${pl.width.round()} floor=${pl.floor} platTop=${pl.worldY(_screenH).round()}');
        }
      }
      _dead        = true;
      _deadAt      = now;
      _deadPhase   = 0;
      _gameRunning = false;
      _bgPlaying.value = false;
      setState(() {});
      return;
    }

    // Pád do propasti (jen bez death sekvence)
    if (!_dead && _isFalling()) {
      _fell        = true;
      _fellAt      = now;
      _gameRunning = false;
      _bgPlaying.value = false;
      setState(() {});
      return;
    }

    // Score
    final currentM = _runMeters.floorToDouble();
    if (currentM > _bestMeters) {
      _bestMeters = currentM;
      SharedPreferences.getInstance().then((p) =>
          p.setDouble(EndlessRun._bestKey, _bestMeters));
      LeaderboardModel.I.updatePlayer(
        SettingsService.I.username, PlayerProfile.I.milesTotal, km: _bestMeters,
      );
    }

    _updateCamera();
    setState(() {});
  }

  // ─────────────────────────────────────────────────────────────
  // Respawn
  // ─────────────────────────────────────────────────────────────
  void _respawn() {
    debugPrint('RESPAWN: lastCheckpointX=${_lastCheckpointX.round()} platforms=${_platforms.length}');
    _worldX        = _spawnOnPlatform(_lastCheckpointX);
    _runMeters     = _worldX / _kSpeed * _kSpeedMps;
    _cameraY       = 0;
    _targetCameraY = 0;
    _vy = 0;
    _stickToGround();
    debugPrint('RESPAWN after stick: runnerY=${_runnerY.round()} grounded=$_grounded worldX=${_worldX.round()}');
    _fell          = false;
    _fellAt        = null;
    _dead          = false;
    _deadAt        = null;
    _deadPhase     = 0;
    _deadLanded    = false;
    _lastGroundedAt = null;
    _wasJumping    = false;
    _startTime     = DateTime.now().subtract(
      const Duration(seconds: 20) * _checkpoints,
    );
    _nextCheckpoint  = const Duration(seconds: 30);
    _bgPlaying.value = true;
    setState(() => _gameRunning = true);
  }

  // ─────────────────────────────────────────────────────────────
  // Ovládání
  // ─────────────────────────────────────────────────────────────
  void _jump() {
    if (_loading) return;

    if (_dead) {
      final offScreen = _runnerY > _screenH + 20;
      if (_deadPhase == 2 || offScreen) _respawn();
      return;
    }

    if (_fell) {
      _respawn();
      return;
    }

    if (_awaitFirstTap) {
      _awaitFirstTap = false;
      _startIntro();
      return;
    }

    if (!_gameRunning) return;

    _jumpBufferAt = DateTime.now();

    final sinceGrounded = _lastGroundedAt == null
        ? 9999
        : DateTime.now().difference(_lastGroundedAt!).inMilliseconds;
    final canCoyote = !_grounded && sinceGrounded <= 120;

    if (_grounded || canCoyote) {
      debugPrint('JUMP wx=${_runnerWorldX.round()} floor=$_currentFloor runnerY=${_runnerY.round()} cameraY=${_cameraY.round()} coyote=$canCoyote');
      setState(() {
        _vy             = _kJumpVelocity;
        _grounded       = false;
        _lastGroundedAt = null;
        _jumpBufferAt   = null;
        _wasJumping     = true;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Intro
  // ─────────────────────────────────────────────────────────────
  static const String _setImg = 'assets/images/run/Set.png';
  static const String _goImg  = 'assets/images/run/Go.png';

  void _startIntro() {
    if (_introRunning) return;
    _introRunning = true;
    _introSprite  = _readyImg;
    _stickToGround();
    setState(() {});

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => _introSprite = _setImg);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        setState(() => _introSprite = _goImg);
        Future.delayed(const Duration(milliseconds: 700), () {
          if (!mounted) return;
          _stickToGround();
          _startTime = _savedElapsedMs > 0
              ? DateTime.now().subtract(Duration(milliseconds: _savedElapsedMs))
              : DateTime.now();
          _lastTick = _savedElapsedMs > 0
              ? Duration(milliseconds: _savedElapsedMs)
              : Duration.zero;
          _savedElapsedMs = 0;
          _introRunning   = false;
          _introSprite    = '';
          _bgPlaying.value = true;
          setState(() => _gameRunning = true);
        });
      });
    });
  }

  // ─────────────────────────────────────────────────────────────
  // Run animace
  // ─────────────────────────────────────────────────────────────
  void _startRunAnim() {
    _runAnimTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted) return;
      if (_loading || (_gameRunning && _grounded)) {
        setState(() => _runFrame = (_runFrame + 1) % _runCycle.length);
      }
    });
  }

  // ─────────────────────────────────────────────────────────────
  // Navigace
  // ─────────────────────────────────────────────────────────────
  void _goMenu() {
    _saveCheckpoint();
    MusicService.I.stopGame().then((_) => MusicService.I.ensureMenuMusic());
    Navigator.of(context).pop();
  }

  void _newSeed() async {
    await _clearSave();
    final s = DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(EndlessRun._seedKey, s);
    _rng           = Random(s);
    _platforms.clear();
    _worldX        = 0;
    _checkpoints   = 0;
    _lastCheckpointX = 0;
    _bestMeters    = 0;
    _runMeters     = 0;
    _cameraY       = 0;
    _targetCameraY = 0;
    _genLastFloor  = 0;
    _genLastWasPit = false;
    _awaitFirstTap = true;
    _gameRunning   = false;
    _bgPlaying.value = false;
    _generate(4000);
    _stickToGround();
    setState(() {});
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_runnerY == 0 || (_awaitFirstTap && !_introRunning)) {
      final g = _effectiveGroundY();
      _runnerY = (g >= 9999 ? _screenH * _kGroundYFrac : g) - _kRunnerR;
    }

    String sprite = _runCycle[_runFrame];
    if (_awaitFirstTap) {
      sprite = _readyImg;
    } else if (_introRunning) {
      sprite = _introSprite.isEmpty ? _readyImg : _introSprite;
    } else if (_dead) {
      sprite = _deadPhase == 0 ? _deathImg : _groundedImg;
    } else if (_fell || !_grounded) {
      sprite = _jumpImg;
    }

    final runnerScreenX = _runnerScreenX;
    final runnerScreenY = _runnerY + _cameraY;

    return GamePlayingScope(
      notifier: _bgPlaying,
      child: Scaffold(
        backgroundColor: Colors.black,
        floatingActionButton: _buildDevMenu(),
        body: GestureDetector(
          onTapDown: (_) => _jump(),
          onLongPressStart: (_) => _jump(),
          child: Stack(
            children: [
              Positioned.fill(
                child: Builder(builder: (ctx) {
                  final playing = GamePlayingScope.of(ctx);
                  return ParallaxBackground(
                    backgroundAsset: 'assets/images/endless/EN_bg1.png',
                    playing: playing,
                    layers: const [
                      ParallaxLayerConfig.scroll(
                        asset: 'assets/images/endless/EN_bg2.png',
                        duration: Duration(seconds: 25),
                        fit: BoxFit.contain,
                      ),
                      ParallaxLayerConfig.scroll(
                        asset: 'assets/images/endless/EN_bg3.png',
                        duration: Duration(seconds: 10),
                        topFraction: 0.35,
                      ),
                    ],
                  );
                }),
              ),
              Positioned.fill(
                child: Container(color: Colors.black.withOpacity(0.25)),
              ),
              CustomPaint(
                painter: _EndlessDebugPainter(
                  platforms: _platforms,
                  worldX: _worldX,
                  cameraY: _cameraY,
                  runnerX: runnerScreenX,
                  runnerY: runnerScreenY,
                  screenH: _screenH,
                  pits: _computePits(),
                ),
                child: const SizedBox.expand(),
              ),
              ..._buildPlatforms(runnerScreenX),
              Positioned(
                left: 0, right: 0,
                top: _groundY + _cameraY,
                child: Container(height: 2, color: Colors.red.withOpacity(0.4)),
              ),
              Builder(builder: (ctx) {
                final isRunAnim = !_awaitFirstTap && !_introRunning && !_fell && _grounded;
                final spriteOffset = _deadLanded ? 3.0 : 2.0;
                return Positioned(
                  left:   runnerScreenX - _kRunnerR * 2,
                  top:    runnerScreenY - _kRunnerR * spriteOffset,
                  width:  _kRunnerR * 4,
                  height: _kRunnerR * 4,
                  child: IgnorePointer(
                    child: Image.asset(sprite,
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomCenter,
                    ),
                  ),
                );
              }),
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatSteps(_bestMeters),
                      style: TextStyle(
                        fontFamily: 'Augarix',
                        fontSize: _screenH * 0.045,
                        color: const Color(0xFF555555),
                        shadows: const [Shadow(
                          color: Color(0x88000000),
                          offset: Offset(1, 1), blurRadius: 3,
                        )],
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: _goMenu,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.30),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withOpacity(0.30)),
                        ),
                        child: Text(T.backToMenu(),
                          style: const TextStyle(
                            fontFamily: 'Augarix', fontSize: 16, color: Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 8,
                child: Image.asset(_gearIcon, width: 65, height: 65),
              ),
              if (_loading)
                Positioned.fill(
                  child: AbsorbPointer(
                    child: Container(
                      color: Colors.black,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 160, height: 160,
                              child: Image.asset(_runCycle[_runFrame], fit: BoxFit.contain,
                                  alignment: Alignment.bottomCenter),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              _isRestoring
                                  ? (SettingsService.I.lang == Lang.cz ? 'Obnovuji level...' : 'Restoring level...')
                                  : (SettingsService.I.lang == Lang.cz ? 'Generuji level...' : 'Generating level...'),
                              style: const TextStyle(
                                fontFamily: 'Augarix', color: Colors.white70, fontSize: 16,
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
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Renderer platforem
  // ─────────────────────────────────────────────────────────────
  List<(double, double)> _computePits() {
    final result = <(double, double)>[];
    final floor0 = _platforms.where((p) => p.floor == 0).toList()
      ..sort((a, b) => a.x.compareTo(b.x));
    for (int i = 0; i < floor0.length - 1; i++) {
      final end   = floor0[i].x + floor0[i].width;
      final start = floor0[i + 1].x;
      if (start - end > 10) result.add((end, start));
    }
    return result;
  }

  List<Widget> _buildPlatforms(double runnerScreenX) {
    final children = <Widget>[];
    final step = _kMidW * 0.90;

    for (final pl in _platforms) {
      final dx      = pl.x - _worldX;
      final screenX = runnerScreenX + dx;
      final screenY = pl.worldY(_screenH) + _cameraY;

      if (screenX > _screenW + 256 || screenX + pl.width < -256) continue;
      if (screenY > _screenH + 64  || screenY + _kPlatformH < -64) continue;

      children.add(Positioned(
        left:   screenX,
        top:    screenY,
        width:  pl.width,
        height: _kPlatformH,
        child: Image.asset(_platformMid,
          fit: BoxFit.fitHeight,
          alignment: Alignment.centerLeft,
          repeat: ImageRepeat.repeatX,
          errorBuilder: (_, __, ___) => Container(color: Colors.blueGrey.withOpacity(0.8)),
        ),
      ));

      if (pl.type == _PlatformType.crossroads) {
        children.add(Positioned(
          left: screenX, top: screenY - 2,
          width: pl.width, height: 2,
          child: Container(color: Colors.yellow.withOpacity(0.6)),
        ));
      }
    }
    return children;
  }

  // ─────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────
  static const double _stepsPerMile = 1000.0;
  String _formatSteps(double meters) {
    final isCz = SettingsService.I.lang == Lang.cz;
    if (meters < _stepsPerMile) {
      return isCz ? '${meters.round()} kroků' : '${meters.round()} steps';
    }
    return isCz
        ? '${(meters / _stepsPerMile).toStringAsFixed(1)} mil'
        : '${(meters / _stepsPerMile).toStringAsFixed(1)} miles';
  }

  // ─────────────────────────────────────────────────────────────
  // DEV menu
  // ─────────────────────────────────────────────────────────────
  Widget _buildDevMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.small(
          heroTag: 'en_regen',
          backgroundColor: const Color(0xFFB03030),
          onPressed: () async {
            await _clearSave();
            if (mounted) {
              MusicService.I.stopGame().then((_) => MusicService.I.ensureMenuMusic());
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const RunSelectScreen()),
              );
            }
          },
          child: const Icon(Icons.refresh, size: 18),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.small(
          heroTag: 'en_new',
          backgroundColor: const Color(0xFF307030),
          onPressed: _newSeed,
          child: const Icon(Icons.shuffle, size: 18),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Debug painter
// ─────────────────────────────────────────────────────────────
class _EndlessDebugPainter extends CustomPainter {
  final List<_Platform> platforms;
  final double worldX;
  final double cameraY;
  final double runnerX;
  final double runnerY;
  final double screenH;
  final List<(double, double)> pits;

  const _EndlessDebugPainter({
    required this.platforms,
    required this.worldX,
    required this.cameraY,
    required this.runnerX,
    required this.runnerY,
    required this.screenH,
    required this.pits,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final groundY = screenH * _kGroundYFrac + cameraY;

    // Fialové čáry = propasti
    final pitPaint = Paint()
      ..color = const Color(0xCCAA00FF)
      ..strokeWidth = 3.0;
    for (final pit in pits) {
      final sx = runnerX + (pit.$1 - worldX);
      final ex = runnerX + (pit.$2 - worldX);
      if (ex < -100 || sx > size.width + 100) continue;
      final pitY = groundY - _kPlatformH - 10;
      canvas.drawLine(Offset(sx, pitY), Offset(ex, pitY), pitPaint);
    }

    // Runner hitbox (fialový trojúhelník)
    final triPaint = Paint()
      ..color = const Color(0xCCAA00FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final rTopY = runnerY - _kRunnerR;
    final rBotY = runnerY + _kRunnerR;
    final path = Path()
      ..moveTo(runnerX - _kRunnerR, rTopY)
      ..lineTo(runnerX + 10.0, rTopY)
      ..lineTo(runnerX, rBotY)
      ..close();
    canvas.drawPath(path, triPaint);

    final walkPaint = Paint()
      ..color = const Color(0xCC00FF88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final slopePaint = Paint()
      ..color = const Color(0xCCFFAA00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final hitPaint = Paint()
      ..color = const Color(0xCCFF2020)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (final pl in platforms) {
      final dx      = pl.x - worldX;
      final screenX = runnerX + dx;
      final platTopY = pl.worldY(screenH) + cameraY;

      if (screenX > size.width + 300 || screenX + pl.width < -300) continue;

      canvas.drawRect(
        Rect.fromLTWH(screenX, platTopY, pl.width, _kPlatformH),
        hitPaint,
      );

      final slopeStartX = screenX + pl.width;
      canvas.drawLine(
        Offset(screenX, platTopY),
        Offset(slopeStartX, platTopY),
        walkPaint,
      );

      final slopeEndX = screenX + pl.width + _kFloorH;
      canvas.drawLine(
        Offset(slopeStartX, platTopY),
        Offset(slopeEndX, platTopY + _kFloorH),
        slopePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EndlessDebugPainter old) => true;
}