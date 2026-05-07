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
const double _kMaxFloors    = 6; // max floor = 6 (kamera sleduje runnera)

// ── Tuning – mezery mezi platformami ─────────────────────────
// Mezera mezi platformami v ose X (vzdálenost mezi koncem jedné a začátkem další)
const double _kPlatGapMin   = 100.0; // minimální mezera v px
const double _kPlatGapMax   = 180.0; // maximální mezera v px
// Mezera v ose Y (výška jednoho patra v pixelech)
const double _kFloorStepY   = 100.0; // výška jednoho patra
// Délka platformy v blocích EN_mid
const int    _kPlatMinCols  = 3;     // minimum bloků
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
  Duration _nextCheckpoint  = const Duration(seconds: 20);

  // ── Score ────────────────────────────────────────────────────
  double _bestMeters    = 0;
  double _runMeters     = 0;
  int    _savedElapsedMs = 0;

  // ── Flow ─────────────────────────────────────────────────────
  bool      _awaitFirstTap = true;
  bool      _gameRunning   = false;
  bool      _loading       = true;
  bool      _fell          = false;
  bool      _introRunning  = false;
  String    _introSprite  = '';   // aktuální intro sprite (Ready/Set/Go)
  DateTime? _fellAt;
  DateTime? _lastGroundedAt;
  DateTime? _jumpBufferAt;
  int _groundLogFrame = 0;
  _Platform? _groundSource;

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
        // Propast: 2–3 šířky bloku EN_mid (max 375px < maxReach 426px)
        final pitW = _kMidW * (2 + _rng.nextInt(2)).toDouble(); // 2 nebo 3 bloky
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
        gap = _kPlatGapMin + _rng.nextDouble() * (_kPlatGapMax - _kPlatGapMin);
        gap = gap.clamp(_kPlatGapMin, (_kPlatGapMax).clamp(_kPlatGapMin, maxReach * 0.85));
      } else if (floorDiff < 0) {
        // Přechod dolů: hráč může slézt po slope nebo skočit
        // Cílová platforma musí být dostatečně dlouhá → zajištěno platW
        // Mezera: kratší (slope dostihne) nebo delší (skok)
        final slopeOrJump = _rng.nextDouble() < 0.60; // 60% slope, 40% skok
        if (slopeOrJump) {
          // Slope: mezera = slope délka = přibližně floorDiff * _kFloorH
          gap = (_kFloorH * floorDiff.abs()) * (0.8 + _rng.nextDouble() * 0.4);
          gap = gap.clamp(0, _kPlatGapMax);
        } else {
          // Skok dolů: větší mezera
          gap = reactionGap * (1.0 + _rng.nextDouble() * 1.0);
          gap = gap.clamp(_kPlatGapMin, (_kPlatGapMax).clamp(_kPlatGapMin, maxReach * 0.75));
        }
      } else {
        // Stejné patro: normální mezera
        gap = _kPlatGapMin + _rng.nextDouble() * (_kPlatGapMax - _kPlatGapMin);
        gap = gap.clamp(_kPlatGapMin, (_kPlatGapMax).clamp(_kPlatGapMin, maxReach * 0.60));
      }

      final placeX = cursor + gap;

      // ── Přidej platformu ─────────────────────────────────────────
      _platforms.add(_Platform(
        x: placeX, width: platW, floor: nextFloor,
        type: isCrossroads ? _PlatformType.crossroads : _PlatformType.normal,
      ));

      // Rozcestí: horní platforma musí být o 2 patra výš
      // aby mezera pro průchod byla >= runner výška + rezerva
      // (_kFloorStepY * 2 = 200px >> _kRunnerR*2+20 = 92px)
      if (isCrossroads) {
        final upperFloor = (nextFloor + 2).clamp(0, _kMaxFloors.toInt());
        // Generuj jen pokud je skutečně mezera pro průchod
        final clearance = _kFloorStepY * (upperFloor - nextFloor);
        if (clearance >= _kRunnerR * 2 + 20) {
          final upperCols = (_kPlatMinCols + _rng.nextInt(_kPlatMaxCols - _kPlatMinCols + 1));
          _platforms.add(_Platform(
            x: placeX,
            width: upperCols * _kMidW,
            floor: upperFloor,
            type: _PlatformType.crossroads,
          ));
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

  double _effectiveGroundY() {
    const noPlatform = 99999.0;
    double ground = noPlatform;

    for (final pl in _platforms) {
      if (pl.x > _runnerWorldX + 100) break;
      if (pl.x + pl.width < _runnerWorldX - 100) continue;
      // Zahrnuj i slope oblast (pl.width až pl.width + _kFloorH)
      if (_runnerWorldX < pl.x || _runnerWorldX > pl.x + pl.width + _kFloorH + _kRunnerR) continue;

      final platTopY   = pl.worldY(_screenH) + _cameraY;
      // Slope začíná na pravém okraji platformy
      final slopeStart = pl.x + pl.width;
      final slopeEnd   = pl.x + pl.width + _kFloorH;

      if (_runnerWorldX <= slopeStart) {
        if (platTopY < ground) { ground = platTopY; _groundSource = pl; }
      } else if (_runnerWorldX <= slopeEnd) {
        final t = (_runnerWorldX - slopeStart) / (slopeEnd - slopeStart);
        final slopeBottomY = platTopY + _kFloorH;
        final slopeY = platTopY + t * (slopeBottomY - platTopY);
        if (slopeY < ground) { ground = slopeY; _groundSource = pl; }
        // Po konci slope: ground = 99999 → runner padá volně
      }
      // Za slopeEnd: žádný ground z této platformy → runner padá
    }
    // Log každých 30 framů
    _groundLogFrame++;
    if (_groundLogFrame % 30 == 0 && _gameRunning) {
      final wx = _runnerWorldX.round();
      if (ground >= 9999) {
        debugPrint('GROUND[$wx]: NO PLATFORM → falling vy=${_vy.round()}');
      } else {
        final onSlope = _groundSource != null && _runnerWorldX > _groundSource!.x + _groundSource!.width;
        debugPrint('GROUND[$wx]: floor=${_groundSource?.floor} y=${ground.round()} onSlope=$onSlope vy=${_vy.round()} grounded=$_grounded');
      }
    }
    return ground;
  }

  void _stickToGround() {
    final g = _effectiveGroundY();
    _runnerY = (g >= 9999 ? _groundY : g) - _kRunnerR;
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
    const snapTol     = 8.0;

    // Ignoruj platformy výše než runner pokud padá (po slope)
    if (localGround < _runnerY - _kRunnerR * 2 && _vy > 100) {
      _grounded = false;
      return;
    }

    if (_runnerY >= localGround) {
      _runnerY = localGround;
      _vy      = 0;
      if (!_grounded) _lastGroundedAt = DateTime.now();
      _grounded = true;
    } else if (_runnerY >= localGround - snapTol && _vy >= 0) {
      _runnerY = localGround;
      _vy      = 0;
      if (!_grounded) _lastGroundedAt = DateTime.now();
      _grounded = true;
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

      final platTopY = pl.worldY(_screenH) + _cameraY;
      final platBotY = platTopY + _kPlatformH;

      if (rBot <= platTopY + 6) continue;
      if (rTop >= platBotY) continue;
      if (_grounded && _runnerY <= platTopY) continue;

      if (front >= pl.x && front <= pl.x + _kRunnerR * 1.5) return true;
    }
    return false;
  }

  void _updateCamera() {
    // Runner vždy na 65% výšky obrazovky
    final targetRunnerScreenY = _screenH * 0.65;
    // cameraY posouvá celý svět tak aby runner byl na targetRunnerScreenY
    _targetCameraY = targetRunnerScreenY - _runnerY;
    // Nikdy níž než 0 (ground nesmí jít pod obrazovku)
    if (_targetCameraY < 0) _targetCameraY = 0;
    // Plynulý lerp
    _cameraY += (_targetCameraY - _cameraY) * 0.10;
  }

  // Najde X pozici na walkable části platformy nejblíže spawnX
  // = střed platformy mínus reakční gap (aby byl čas reagovat na konec)
  double _spawnOnPlatform(double spawnX) {
    // Najdi první platformu která obsahuje spawnX nebo je za ním
    for (final pl in _platforms) {
      if (pl.x + pl.width < spawnX) continue; // platforma je za runnerem
      // Spawn na levé walkable části platformy (s reaction gap od kraje)
      final minGap = _kReactionSec * _kSpeed;
      final safeX = pl.x + minGap;
      // Pokud se spawn vejde na platformu → použij ho
      if (safeX < pl.x + pl.width - minGap) {
        return safeX - 40; // -40 = runnerWorldX offset
      }
      // Platforma příliš krátká → zkus další
    }
    return _safeSpawnX(spawnX); // fallback
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
          safe   = false;
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
    if (!_gameRunning) return;

    final now   = DateTime.now();
    final dt    = now.difference(_startTime) - _lastTick;
    _lastTick  += dt;
    final dtSec = dt.inMicroseconds / 1e6;
    if (dtSec <= 0) return;

    // Pád – čekej na tap
    if (_fell) {
      setState(() {});
      return;
    }

    _worldX    += _kSpeed * dtSec;
    _runMeters  = _worldX / _kSpeed * _kSpeedMps;

    _generate(_worldX + 4000);

    // Checkpoint
    _nextCheckpoint -= dt;
    if (_nextCheckpoint <= Duration.zero) {
      _checkpoints++;
      _lastCheckpointX = _worldX;
      _nextCheckpoint  = const Duration(seconds: 20);
      _saveCheckpoint();
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
        _vy       = _kJumpVelocity;
        _grounded = false;
        _lastGroundedAt = null;
      }
      _jumpBufferAt = null;
    }

    // Pád nebo kolize
    if (_isFalling() || _collidesWithPlatform()) {
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
    _worldX        = _safeSpawnX(_lastCheckpointX);
    _runMeters     = _worldX / _kSpeed * _kSpeedMps;
    _cameraY       = 0;
    _targetCameraY = 0;
    _vy = 0; // reset velocity před stickToGround aby nedošlo k tunelingu
    _stickToGround();
    _fell          = false;
    _fellAt        = null;
    _lastGroundedAt = null;
    _startTime     = DateTime.now().subtract(
      const Duration(seconds: 20) * _checkpoints,
    );
    _nextCheckpoint  = const Duration(seconds: 20);
    _bgPlaying.value = true;
    setState(() => _gameRunning = true);
  }

  // ─────────────────────────────────────────────────────────────
  // Ovládání
  // ─────────────────────────────────────────────────────────────
  void _jump() {
    if (_loading) return;

    // Pád – po 2s umožni respawn tapem
    if (_fell) {
      final sinceFell = _fellAt == null
          ? 0
          : DateTime.now().difference(_fellAt!).inMilliseconds;
      if (sinceFell >= 2000) _respawn();
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
      setState(() {
        _vy             = _kJumpVelocity;
        _grounded       = false;
        _lastGroundedAt = null;
        _jumpBufferAt   = null;
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

    // Ready → Set
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => _introSprite = _setImg);

      // Set → Go
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        setState(() => _introSprite = _goImg);

        // Go → start
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
      if (!mounted || !_gameRunning || !_grounded) return;
      setState(() => _runFrame = (_runFrame + 1) % _runCycle.length);
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
      // Před tapem vždy drž runnera na správné pozici (platforma může být načtena pozdě)
      final g = _effectiveGroundY();
      _runnerY = (g >= 9999 ? _screenH * _kGroundYFrac : g) - _kRunnerR;
    }

    String sprite = _runCycle[_runFrame];
    if (_awaitFirstTap) {
      sprite = _readyImg;
    } else if (_introRunning) {
      sprite = _introSprite.isEmpty ? _readyImg : _introSprite;
    } else if (_fell || !_grounded) {
      sprite = _jumpImg;
    }

    final runnerScreenX = _runnerScreenX;

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
              // Parallax
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

              // Debug hitboxy
              CustomPaint(
                painter: _EndlessDebugPainter(
                  platforms: _platforms,
                  worldX: _worldX,
                  cameraY: _cameraY,
                  runnerX: runnerScreenX,
                  runnerY: _runnerY,
                  screenH: _screenH,
                  pits: _computePits(),
                ),
                child: const SizedBox.expand(),
              ),

              // Platformy
              ..._buildPlatforms(runnerScreenX),

              // Ground linka
              Positioned(
                left: 0, right: 0,
                top: _groundY + _cameraY,
                child: Container(height: 2, color: Colors.red.withOpacity(0.4)),
              ),

              // Runner – různý offset dle spritu
              Builder(builder: (ctx) {
                final isRunAnim = !_awaitFirstTap && !_introRunning && !_fell && _grounded;
                const spriteOffset = 2.0;
                return Positioned(
                  left:   runnerScreenX - _kRunnerR * 2,
                  top:    _runnerY - _kRunnerR * spriteOffset,
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

              // HUD
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

              // Settings
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 8,
                child: Image.asset(_gearIcon, width: 65, height: 65),
              ),

              // Progress bar
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: _screenW * 0.20,
                right: _screenW * 0.20,
                child: _buildProgressBar(),
              ),

              // Loading overlay
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
                              child: Image.asset(_runCycle[_runFrame], fit: BoxFit.contain),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              SettingsService.I.lang == Lang.cz
                                  ? 'Generuji level...' : 'Generating level...',
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
  // Vypočítej propasti = mezery mezi floor=0 platformami
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

      // Renderuj platformu jako jeden pás přes celou šířku (jako CT_3 v hard)
      // BoxFit.fitHeight + ImageRepeat.repeatX = stejný vizuální efekt
      children.add(Positioned(
        left:   screenX,
        top:    screenY,
        width:  pl.width,
        height: _kPlatformH,
        child: Image.asset(_platformMid,
          fit: BoxFit.fitHeight,
          alignment: Alignment.centerLeft,
          repeat: ImageRepeat.repeatX,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.blueGrey.withOpacity(0.8),
          ),
        ),
      ));

      // Rozcestí – žlutý okraj
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
  // Progress bar
  // ─────────────────────────────────────────────────────────────
  Widget _buildProgressBar() {
    const bgColor     = Color(0xBBD4B896);
    const fillColor   = Color(0xFF8B6914);
    const borderColor = Color(0xFF6B4F0A);
    const textColor   = Color(0xFF3B2A05);

    final barW = _screenW * 0.60;
    const barH = 14.0;
    const radius = Radius.circular(7);

    final elapsedMs = _gameRunning
        ? DateTime.now().difference(_startTime).inMilliseconds
        : (_savedElapsedMs > 0 ? _savedElapsedMs : 0);
    const intervalMs = 20000;
    final progress = (elapsedMs % intervalMs / intervalMs).clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: barW, height: barH,
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
        Text('$_checkpoints CP',
          style: const TextStyle(
            fontFamily: 'Augarix', fontSize: 10, color: textColor,
          ),
        ),
      ],
    );
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
// Debug painter – hitboxy platforem jako v game_base
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
      // Propast na úrovni walkable (zelená linka = groundY - _kPlatformH)
      final pitY = groundY - _kPlatformH - 10;
      canvas.drawLine(Offset(sx, pitY), Offset(ex, pitY), pitPaint);
    }

    final triPaint = Paint()
      ..color = const Color(0xCCAA00FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Runner trojúhelník (stejný jako game_base)
    final rLeftH     = runnerX - _kRunnerR;
    final rRightH    = runnerX + 10.0; // runnerHitboxTopRight
    final rCenterBot = runnerX;
    final rTopY      = runnerY - _kRunnerR;
    final rBotY      = runnerY + _kRunnerR;
    final path = Path()
      ..moveTo(rLeftH, rTopY)
      ..lineTo(rRightH, rTopY)
      ..lineTo(rCenterBot, rBotY)
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
      final platBotY = platTopY + _kPlatformH;

      if (screenX > size.width + 300 || screenX + pl.width < -300) continue;

      // Červený obdélník = hitbox platformy
      canvas.drawRect(
        Rect.fromLTWH(screenX, platTopY, pl.width, _kPlatformH),
        hitPaint,
      );

      // Zelená linka = celý walkable povrch (top)
      canvas.drawLine(
        Offset(screenX, platTopY),
        Offset(screenX + pl.width, platTopY),
        walkPaint,
      );

      // Oranžová linka = slope zprava (začíná na pravém rohu)
      final slopeEndX = screenX + pl.width + _kFloorH;
      canvas.drawLine(
        Offset(screenX + pl.width, platTopY),
        Offset(slopeEndX, platTopY + _kFloorH),
        slopePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EndlessDebugPainter old) => true;
}