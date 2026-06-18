import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:gif/gif.dart'; // ⬅️ pauzovatelné GIF pozadí
import 'package:shared_preferences/shared_preferences.dart';

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
enum ObstacleType {
  box,
  spike,
  /// Hard: CT_mid – killing zleva, walkable nahoře, slope (varianta B) vpravo
  /// Výška = 0.5–2.0× runnerRadius*2, krok 0.25
  hardMid,
  /// Hard: CT_spike (sudy) – killing zleva, walkable nahoře, slope horní část vpravo
  hardSpike,
  /// Hard: CT_spike1 – killing ze všech stran (identický s easy spike logicky)
  hardSpike1,
}

// ———————————————————————————————————————————————————————————
// Obstacle datový model
// ———————————————————————————————————————————————————————————
class Obstacle {
  final double x;            // světová X pozice levého okraje
  final double width;        // celková šířka
  final double height;       // výška (z "podlahy" vzhůru)
  final bool fromFloor;      // true = stojí na zemi
  final ObstacleType type;   // BOX / SPIKE
  /// Výška nad zemí – pro typ C vrchní překážky = výška základny.
  /// 0 = stojí přímo na zemi.
  final double groundOffset;

  const Obstacle({
    required this.x,
    required this.width,
    required this.height,
    required this.fromFloor,
    required this.type,
    this.groundOffset = 0,
  });
}

class FlipMarker { final double atX; const FlipMarker(this.atX); }
class MirrorMarker { final double atX; final double untilX; const MirrorMarker(this.atX, this.untilX); }

// ———————————————————————————————————————————————————————————
// InheritedWidget – sdílí stav přehrávání s background widgetem
// ———————————————————————————————————————————————————————————
class GamePlayingScope extends InheritedNotifier<ValueNotifier<bool>> {
  const GamePlayingScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<GamePlayingScope>();
    return scope?.notifier?.value ?? false;
  }
}

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

  /// Složka assetů pro tento mód. Default = 'assets/images/'

  /// Přepis tileScale pro tento mód. null = použij default (1.25)
  final double? tileScaleOverride;

  /// Složka kde leží sprite assety. Výchozí = 'assets/images/'.
  /// Pro easy: 'assets/images/easy/'
  final String spriteFolder;

  /// Minimální reakční čas mezi koncem překážky a začátkem další (v sekundách).
  /// Garantuje že hráč má dost času zareagovat.
  /// EASY=1.2s, MEDIUM=0.8s, HARD=0.5s, ENDLESS=0.8s
  final double reactionTimeSec;

  /// Když true, po smrti hra zamrzne na místě a čeká na tap pro respawn.
  final bool stayDead;

  /// Volitelné vlastní pozadí. Null = původní GIF background.
  final WidgetBuilder? backgroundBuilder;

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
    this.spriteFolder = 'assets/images/',
    this.stayDead = false,
    this.backgroundBuilder,
    this.tileScaleOverride,
  });

  /// Klíč pro SharedPreferences – každý mode má vlastní seed.
  String get seedPrefsKey => 'level_seed_$modeName';
  /// Klíč pro nejlepší vzdálenost v tomto levelu.
  /// v3 = vzdalenost primo v metrech jako double
  String get bestXPrefsKey => 'best_worldx_v3_$modeName';
  /// Klíč pro uložený checkpoint (worldX pozice)
  String get checkpointPrefsKey => 'last_checkpoint_$modeName';
  /// Klíč pro uložený elapsed čas v ms (pro progress bar)
  String get elapsedMsPrefsKey => 'last_elapsed_ms_$modeName';
}

class GameBaseState<TW extends GameBase> extends State<TW>
    with SingleTickerProviderStateMixin {
  // ——— tuning & assets ———
  static const double baseSpeedPxPerSec = 520;
  static const double runnerRadius = 36;        // poloměr vizuálního kruhu
  // Pravá hrana runner hitboxu = worldX + runnerFrontOffset
  // Snížením hodnoty pod runnerRadius dáš hráči "benefit of doubt" vpravo
  static const double runnerFrontOffset = 28.0; // pravá hrana hitboxu

  // ── Skóre / vzdálenost ────────────────────────────────────────
  // Velikost flash textu jako % výšky displeje (landscape)
  static const double scoreFlashSizePct = 0.20; // 20% výšky = ~78px na typickém telefonu
  /// Velikost Easy spike nezávisle na tileScaleOverride
  static const double easySpikeScale = 4.9;

  // ── Hard CT_spike ───────────────────────────────────────────
  // CT_spike.png: 1024×665, poměr 1.54, výška = runnerRadius*2 = 72px → šířka = 111px
  static const double hardSpikeW = 111.0;
  // Přibližná konverze px → km (závisí na speed a měřítku)
  // 1 km = 1000m, baseSpeed=520px/s → při 100% speedPercent
  // Laditelná konstanta – upravit dle pocitu ve hře
  // Reálná rychlost runnera v m/s (libovolná ale konzistentní konvence)
  // 6.0 m/s = dobrá běžecká rychlost, odpovídá 10 min/km
  static const double speedMps = 6.0;
  // Trojúhelníkový hitbox: a=levý dolní, b=pravý horní (posunutelný), c=pravý dolní
  // runnerHitboxTopRight: X offset bodu b od středu runnera (kladné = vpravo)
  static const double runnerHitboxTopRight = 10.0; // bod b blize stredu nez c
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
    'assets/images/run/Run4.png',
    'assets/images/run/Run5.png',
    'assets/images/run/Run6.png',
    'assets/images/run/Run7.png',
    'assets/images/run/Run8.png',
  ];
  static const String _jumpImg     = 'assets/images/run/Jump1.png';
  static const String _deathImg    = 'assets/images/run/Death.png';
  static const String _groundedImg = 'assets/images/run/Grounded.png'; // ⬅️ přidat do pubspec.yaml
  static const String _gearIcon    = 'assets/images/icon_settings.png';  // tlačítko vpravo nahoře

  // Dlaždice – sprite rozměry (px, nativní velikost assetů)
  // Poznámka: public aby byly dostupné z _RunnerPainter
  static const double _tileStartW = 16.0;  // MT_start / MT_end šířka
  static const double _tileEndW   = 16.0;
  static const double _tileMidW   = 25.0;  // MT_mid / MT_Fill šířka
  static const double _tileH      = 19.0;  // výška jedné řady
  // Aliasy pro přístup z _RunnerPainter (Dart neumí přistupovat k private z jiné třídy)
  static const double tileStartWPub = _tileStartW;
  static const double tileEndWPub   = _tileEndW;

  // ── Škálování vizuálu ──────────────────────────────────────────
  // 1.0 = nativní, 2.0 = dvojnásobné, 0.5 = poloviční.
  // Hitboxy (fyzika, kolize) nejsou ovlivněny.
  static const double tileScale   = 1.25; // +25 % dle požadavku
  /// Efektivní tileScale – použije override pokud je nastaven
  double get effectiveTileScale => widget.tileScaleOverride ?? tileScale;
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

  // ── Score / vzdálenost ───────────────────────────────────────
  double _bestMeters      = 0; // nejdál kam hráč v tomto levelu došel (v metrech)
  double _runMeters       = 0; // aktuální vzdálenost v tomto runu (v metrech)
  double _sessionNewM     = 0; // nové metry získané v tomto runu (pro flash)
  Timer? _scoreFlashTimer;
  double _scoreFlashOpacity   = 0;
  bool   _scoreFlashVisible   = false;
  double _scoreDisplayScale   = 1.0; // pro pulz v rohu
  bool   _scorePulsing        = false;

  // Tracking generátoru – přetrvává mezi voláními _ensureGeneratedAhead
  int  _genLastLayers     = 1;
  bool _genLastWasBox     = true;
  bool _genLastWasSpike   = false;
  bool _genLastWasPlatform = true;

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
  DateTime? _jumpBufferAt;   // ⏱ jump buffer – čas posledního tapu (i když nebyl grounded)
  int _savedElapsedMs = 0;   // ⏱ uložený elapsed čas při restore checkpointu
  bool _pendingObstacleGen = false; // true = vygeneruj překážky hned po mountu

  // stayDead runtime
  bool _deadFrozen = false;

  // start flow
  bool _awaitFirstTap = true;
  bool _gameRunning = false;
  bool _queuedJump = false;

  // 🎞️ GIF controller (nullable – jen pokud není custom background)
  GifController? _bgGifCtrl;

  bool get _hasCustomBackground => widget.backgroundBuilder != null;

  // ⛔️→🙂 Death → Grounded přepínač
  Timer? _deathStageTimer;

  // 🔁 Continuous jump při longpress
  Timer? _longJumpTimer;

  // Notifier pro parallax pozadí – true = runner běží, false = stojí
  final ValueNotifier<bool> bgPlayingNotifier = ValueNotifier(false);

  // 🔥 precache guard + loading overlay
  bool _isRestoringLevel = false; // true = načítáme existující seed, false = generujeme nový
  bool _precached = false;
  bool _loading = true;

  bool get _shouldBgPlay =>
      _gameRunning && !paused && _intro == IntroPhase.none && !_deadFrozen && !finished;

  void _syncBgAnim() {
    if (!mounted) return;
    if (_hasCustomBackground) return;
    if (_shouldBgPlay) {
      // Normalizovaný rozsah 0..1, perioda celé smyčky:
      _bgGifCtrl?.repeat(min: 0, max: 1, period: const Duration(seconds: 6));
    } else {
      // „pauza“ = stop na aktuálním frame
      _bgGifCtrl?.stop();
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
      // Dlaždice aktuálního game modu (dle spritePrefix)
      AssetImage('${widget.spriteFolder}${widget.spritePrefix}_spike.png'),
      AssetImage('${widget.spriteFolder}${widget.spritePrefix}_start.png'),
      AssetImage('${widget.spriteFolder}${widget.spritePrefix}_mid.png'),
      AssetImage('${widget.spriteFolder}${widget.spritePrefix}_fill.png'),
      AssetImage('${widget.spriteFolder}${widget.spritePrefix}_end.png'),
      // Hard: extra sprite typy
      if (widget.modeName == 'HARD') ...[
        AssetImage('${widget.spriteFolder}${widget.spritePrefix}_spike1.png'),
      ],
      ..._runCycle.map((p) => AssetImage(p)),
    ];

    for (final p in providers) {
      await precacheImage(p, ctx);
    }

    // Vygeneruj celý level během loading overlaye
    if (mounted) {
      final totalLength = widget.length.inMilliseconds / 1000.0 * speed;
      _generateFullLevel(totalLength + 4000);
    }

    // Maskování načítání
    final loadDelay = _isRestoringLevel
        ? const Duration(seconds: 2)
        : const Duration(seconds: 7);
    await Future.delayed(loadDelay);
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
    if (!_hasCustomBackground) {
      _bgGifCtrl = GifController(vsync: this);
      _bgGifCtrl!.value = 0;
      _bgGifCtrl!.stop();
    }

    speed = baseSpeedPxPerSec * (widget.speedPercent / 100.0);
    // Načti uložený seed nebo vygeneruj nový při prvním spuštění
    _loadOrGenerateSeed();
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
    _scoreFlashTimer?.cancel();
    bgPlayingNotifier.dispose();
    loop.cancel();
    _bgGifCtrl?.dispose();
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
            // Pokud obnovujeme checkpoint, posuň startTime dozadu
            startTime = _savedElapsedMs > 0
                ? DateTime.now().subtract(Duration(milliseconds: _savedElapsedMs))
                : DateTime.now();
            lastTick = _savedElapsedMs > 0
                ? Duration(milliseconds: _savedElapsedMs)
                : Duration.zero;
            _savedElapsedMs = 0; // spotřebováno
          });
          bgPlayingNotifier.value = true;
          _syncBgAnim();
          // automatický skok po GO záměrně odstraněn
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
  // ── Reset herního stavu bez změny seedu ──────────────────────
  void _resetGameState() {
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
    _genLastLayers      = 1;
    _genLastWasBox      = true;
    _genLastWasSpike    = false;
    _genLastWasPlatform = true;
    _runMeters          = 0;
    _jumpBufferAt       = null;
    _lastGroundedAt     = null;
    _savedElapsedMs     = 0;
    _pendingObstacleGen = false;
    bgPlayingNotifier.value = false;
  }

  // ── Aplikuj seed (bez persistování) ──────────────────────────
  void _applySeed(int s) {
    seed = s;
    rng = Random(seed);
    _resetGameState();
    Future.microtask(() async {
      await MusicService.I.stopMenuMusic();
      await MusicService.I.onNewSeed(newSeed: seed);
      if (SettingsService.I.musicOn) {
        await MusicService.I.playGameTrackForLockedSeed();
      }
    });
    _syncBgAnim();
  }

  // ── Načti uložený seed nebo vygeneruj nový ───────────────────
  Future<void> _loadOrGenerateSeed() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(widget.seedPrefsKey);
    _bestMeters = prefs.getDouble(widget.bestXPrefsKey) ?? 0;
    if (saved != null) {
      // Existující seed – obnovujeme level od posledního checkpointu
      _isRestoringLevel = true;
      final savedCheckpoint = prefs.getDouble(widget.checkpointPrefsKey) ?? 0;
      final savedCheckpointCount = prefs.getInt('last_checkpoint_count_${widget.modeName}') ?? 0;
      _applySeed(saved);
      // Obnov checkpoint pozici po applySeed (který resetuje stav)
      if (savedCheckpoint > 0) {
        final savedElapsedMs = prefs.getInt(widget.elapsedMsPrefsKey) ?? 0;
        lastCheckpointWorldX = savedCheckpoint;
        checkpoints = savedCheckpointCount;
        nextCheckpointIn = widget.checkpointFreq;
        _savedElapsedMs = savedElapsedMs;
        // Vygeneruj level od 0 do checkpointu + buffer
        worldX = 0;
        _generateFullLevel(savedCheckpoint + 4000);
        // Po vygenerování posuň runnera na checkpoint (s reaction gap ochranou)
        worldX = _safeSpawnX(savedCheckpoint);
        _runMeters = worldX / (baseSpeedPxPerSec * (widget.speedPercent / 100.0)) * speedMps;
        // Nastav Y pozici stejně jako při respawnu – runner stojí na ground nebo walkable box
        _stickToGround();
        // Pojistka: pokud je runner v kolizi, posuň dál dozadu
        int safetyIter = 0;
        while (_collides() && safetyIter < 20) {
          worldX -= speed * 0.1;
          _stickToGround();
          safetyIter++;
        }
        // Překresli widget s nově vygenerovanými překážkami
        if (mounted) setState(() {});
        // 🔍 DEBUG LOG
        debugPrint('=== RESTORE DEBUG ===');
        debugPrint('savedCheckpoint: $savedCheckpoint');
        debugPrint('worldX after restore: $worldX');
        debugPrint('obstacles.length: ${obstacles.length}');
        if (obstacles.isNotEmpty) {
          debugPrint('first obstacle x: ${obstacles.first.x}');
          debugPrint('last obstacle x: ${obstacles.last.x}');
          // Překážky v visible oblasti (worldX-200 až worldX+1500)
          final visible = obstacles.where((o) => o.x >= worldX - 200 && o.x <= worldX + 1500).toList();
          debugPrint('visible obstacles near checkpoint: ${visible.length}');
          for (final o in visible.take(5)) {
            debugPrint('  ob x:${o.x} w:${o.width} type:${o.type}');
          }
        }
      }
    } else {
      // Nový seed – generujeme level
      _isRestoringLevel = false;
      final s = DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF;
      await prefs.setInt(widget.seedPrefsKey, s);
      _applySeed(s);
    }
  }

  // ── Hook pro přegenerování úrovně ────────────────────────────
  // Volej po zobrazení reklamy nebo po penalizaci.
  // Smaže uložený seed → příští _loadOrGenerateSeed vygeneruje nový.
  Future<void> regenerateLevel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(widget.seedPrefsKey);
    await prefs.remove(widget.bestXPrefsKey);
    await prefs.remove(widget.checkpointPrefsKey);
    await prefs.remove('last_checkpoint_count_${widget.modeName}');
    await prefs.remove(widget.elapsedMsPrefsKey);
    _bestMeters = 0;
    _isRestoringLevel = false; // vždy generujeme nový
    await _loadOrGenerateSeed();
    if (mounted) setState(() {});
    _syncBgAnim();
  }

  // ── Nový seed (přegenerování v ingame menu) ───────────────────
  void _newSeed() {
    final s = DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(widget.seedPrefsKey, s);
      prefs.remove(widget.checkpointPrefsKey);
      prefs.remove('last_checkpoint_count_${widget.modeName}');
      prefs.remove(widget.elapsedMsPrefsKey);
    });
    _applySeed(s);
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
  // Vygeneruje celý level od začátku do targetX bez limitu překážek per volání
  void _generateFullLevel(double targetX) {
    debugPrint('=== _generateFullLevel START, targetX: $targetX, worldX: $worldX ===');
    // Reset tracking fields aby generátor začal od začátku
    _genLastLayers      = 1;
    _genLastWasBox      = true;
    _genLastWasSpike    = false;
    _genLastWasPlatform = true;
    obstacles.clear();
    // Dočasně odstraň limit překážek
    _fullGenMode = true;
    _ensureGeneratedAhead(targetX);
    _fullGenMode = false;
    debugPrint('=== _generateFullLevel DONE, obstacles: ${obstacles.length}, last x: ${obstacles.isEmpty ? "none" : obstacles.last.x} ===');
  }

  bool _fullGenMode = false; // true = bez limitu 8 překážek

  void _ensureGeneratedAhead(double targetX) {
    // cursor = kde generátor naposledy skončil (konec poslední překážky)
    // NESMÍ být nastaven na targetX – to by přeskočilo celé generování!
    double cursor = obstacles.isEmpty ? 0 : obstacles.last.x + obstacles.last.width;

    // V _fullGenMode generuj až do targetX, jinak jen 4000px dopředu od worldX
    final double endX = _fullGenMode ? targetX : max(worldX + 4000, targetX);
    if (_fullGenMode) {
      debugPrint('_ensureGeneratedAhead: targetX=$targetX endX=$endX cursor=$cursor worldX=$worldX');
    }

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

    // ── Tracking – aliasy z fields (přetrvávají mezi voláními) ──
    int  lastLayers     = _genLastLayers;
    bool lastWasBox     = _genLastWasBox;
    bool lastWasSpike   = _genLastWasSpike;

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
    bool lastWasPlatform = _genLastWasPlatform;

    // Přesná šířka BOX dle počtu mid sloupců
    double _boxWidth(int midCols) {
      return (_tileStartW + midCols * _tileMidW + _tileEndW) * tileScale;
    }

    int _genCount = 0;
    while (cursor < endX && (_fullGenMode || _genCount < 8)) {

      // ── Krok 1: Typ překážky ───────────────────────────────────
      // EASY: jen SPIKE a TYP A (žádné B, žádné C)
      // MEDIUM+: SPIKE (20%), TYP A (40%), TYP B (40%)
      final isEasy = widget.modeName == 'EASY';

      final canSpike = lastLayers < highThreshold && lastWasBox;
      // Easy: spike 25%, ostatní: 20%
      // EASY: 40% spike šance (více spiků = více legionářů želvy)
      final makeSpike = canSpike && rng.nextDouble() < (widget.modeName == 'EASY' ? 0.40 : 0.20);

      double obW;
      double obH;
      ObstacleType obType;
      bool obIsPlatform;
      int obLayersForTracking;

      if (makeSpike) {
        final spikeRoll  = rng.nextDouble();
        // EASY: max 2 spike (3 nejdou přeskočit), vlastní easySpikeScale
        // MEDIUM+: 1-3 spike, normální spikeScale
        final spikeCount = isEasy
            ? 1 // EASY: vždy jen 1 spike
            : (spikeRoll < 0.10 ? 1 : (spikeRoll < 0.50 ? 2 : 3));
        obW = spikeCount * (isEasy ? _tileH * easySpikeScale : _tileH * spikeScale);
        obH = isEasy ? _tileH * easySpikeScale : _tileH * spikeScale;
        obType            = ObstacleType.spike;
        obIsPlatform      = false;
        obLayersForTracking = highThreshold;
      } else {
        obType = ObstacleType.box;
        final int maxAllowed = lastLayers >= highThreshold ? 2 : maxLayers;
        final int layers = minLayers + rng.nextInt(maxAllowed - minLayers + 1);
        obH = layers * sTileHGen;
        obLayersForTracking = layers;

        if (isEasy) {
          // EASY: jen HL_mid dlaždice, 3–15 bloků, 1 vrstva
          // Hitbox = vizuální rozměry (effectiveTileScale) aby přesně kopíroval obrázek
          final midCols = 3 + rng.nextInt(13); // 3–15 dlaždic
          obW          = midCols * _tileMidW * effectiveTileScale; // vizuální šířka
          obH          = _tileH * effectiveTileScale; // vizuální výška (1 vrstva)
          obLayersForTracking = 1;
          obIsPlatform = true; // walkable celý povrch
        } else if (rng.nextDouble() < 0.40) {
          // TYP A: [start][end] – smrtící shora
          obW          = (_tileStartW + _tileEndW) * tileScale;
          obIsPlatform = false;
        } else {
          // TYP B: [start][mid×3–10][end] – walkable odrazový můstek
          final midCols = 3 + rng.nextInt(8); // 3–10
          obW          = _boxWidth(midCols);
          obIsPlatform = true;
        }
      }

      // ── Krok 2: Mezera ─────────────────────────────────────────
      final wantB = !lastWasSpike && lastWasPlatform && rng.nextDouble() < 0.70;
      double clearGap;

      if (wantB) {
        final gapB     = reactionGap * (0.6 + rng.nextDouble() * 0.6);
        final prevTopH = lastLayers * sTileHGen;
        final sStartW  = _tileStartW * tileScale;

        final reachToMid   = obIsPlatform ? _jumpReach(prevTopH, obH) : 0.0;
        final reachOverAll = _jumpReach(prevTopH, 0.0);
        final b1ok = obIsPlatform && (gapB + sStartW) <= reachToMid;
        final b2ok = reachOverAll > gapB + obW;

        if (b1ok || b2ok) {
          clearGap = gapB;
        } else if (obIsPlatform) {
          clearGap = (reachToMid - sStartW).clamp(reactionGap * 0.6, reactionGap * 1.2);
        } else {
          clearGap = reactionGap * (1.3 + rng.nextDouble() * 0.9);
        }
      } else {
        final mult = lastWasSpike
            ? (1.3 + rng.nextDouble() * 0.7)
            : (1.3 + rng.nextDouble() * 0.9);
        clearGap = reactionGap * mult;
      }

      final placeX = cursor + clearGap;
      if (placeX <= introLimitX) {
        cursor = placeX + 1;
        continue;
      }

      // ── Krok 2.5: Typ C – přepočítej obW PŘED přidáním základny ──
      // P(C|B) = 0.37 → P(C) = 0.60 × 0.37 ≈ 22% = každá 4.5. překážka
      // Easy: žádný typ C
      final isTypeC = !isEasy &&
          obIsPlatform &&
          obType == ObstacleType.box &&
          rng.nextDouble() < 0.37;

      int cVariant = 0;
      int cMaxTops = 1;
      if (isTypeC) {
        // Základna C: vždy 1 vrstva výšky (plochá, bez pyramid fill řad).
        // Tím jsou nástavby a spike vizuálně jasně nad základnou.
        obH = sTileHGen; // 1 vrstva
        obLayersForTracking = 1;
        // Délka základny dle varianty
        cVariant = rng.nextInt(3);
        switch (cVariant) {
          case 0:  obW = _boxWidth(10 + rng.nextInt(11)); cMaxTops = 2; break; // C1: 10–20
          case 1:  obW = _boxWidth(21 + rng.nextInt(30)); cMaxTops = 3; break; // C2: 21–50
          default: obW = _boxWidth(51 + rng.nextInt(50)); cMaxTops = 5; break; // C3: 51–100
        }
      }

      // ── Krok 3: Přidej základnu ────────────────────────────────
      obstacles.add(Obstacle(
        x: placeX, width: obW, height: obH,
        fromFloor: true, type: obType,
      ));
      cursor          = placeX + obW;
      lastLayers      = obLayersForTracking;
      lastWasBox      = obType == ObstacleType.box;
      lastWasSpike    = obType == ObstacleType.spike;
      lastWasPlatform = obIsPlatform;

      // ── Krok 4: Nástavby pro typ C ─────────────────────────────
      if (isTypeC) {
        final baseHeight   = obH;
        final maxTopLayers = 5 - obLayersForTracking;
        final baseEnd      = placeX + obW; // obW je nyní správná délka C
        final sEndWLocal   = _tileEndW   * tileScale;
        final sStartWLocal = _tileStartW * tileScale;
        final sMidWLocal   = _tileMidW   * tileScale;
        final topReactionGap = reactionGap * 0.7;

        if (maxTopLayers >= 1) {
          final topCount = 1 + rng.nextInt(cMaxTops);
          double topCursor = placeX;

          for (int tc = 0; tc < topCount; tc++) {
            final topGap = topReactionGap * (1.0 + rng.nextDouble() * 0.8);
            final topX   = topCursor + topGap;

            // Nejdřív typ, pak topH (spike má fixní výšku sSpikeH)
            final topRoll     = rng.nextDouble();
            final spikeThresh = cVariant == 0 ? 0.30 : (cVariant == 1 ? 0.20 : 0.15);
            final typeAThresh = spikeThresh + (cVariant == 0 ? 0.35 : (cVariant == 1 ? 0.30 : 0.20));
            final isTopSpike  = topRoll < spikeThresh;
            final sSpikeWLocal = _tileH * spikeScale;

            // Spike výška = sSpikeH (fixní), BOX výška = náhodné vrstvy
            final topH = isTopSpike
                ? sSpikeWLocal
                : (1 + rng.nextInt(maxTopLayers.clamp(1, 3))) * sTileHGen;

            // maxTopW závisí na správném topH
            final maxTopW = baseEnd - topX - topH - runnerRadius;
            if (maxTopW <= sStartWLocal + sEndWLocal) break;

            double topW;
            ObstacleType topType;

            if (isTopSpike) {
              // Spike skupina: 10%=1, 40%=2, 50%=3
              final maxSpikes  = ((maxTopW / sSpikeWLocal).floor()).clamp(1, 3);
              final spikeRollC = rng.nextDouble();
              final spikeCount = (spikeRollC < 0.10 ? 1 : (spikeRollC < 0.50 ? 2 : 3))
                  .clamp(1, maxSpikes);
              topW    = spikeCount * sSpikeWLocal;
              topType = ObstacleType.spike;
            } else if (topRoll < typeAThresh) {
              topW    = sStartWLocal + sEndWLocal;
              topType = ObstacleType.box;
            } else {
              final maxMidForVariant = cVariant == 0 ? 3 : (cVariant == 1 ? 6 : 10);
              final maxMidCols = ((maxTopW - sStartWLocal - sEndWLocal) / sMidWLocal)
                  .floor().clamp(1, maxMidForVariant);
              final topMidCols = 1 + rng.nextInt(maxMidCols);
              topW    = sStartWLocal + topMidCols * sMidWLocal + sEndWLocal;
              topType = ObstacleType.box;
            }

            if (topX + topW > baseEnd) break;

            obstacles.add(Obstacle(
              x: topX, width: topW, height: topH,
              fromFloor: false, type: topType,
              groundOffset: baseHeight,
            ));

            topCursor = topX + topW;
          }
        }
      }

      // Persistuj tracking do fields pro příští volání _ensureGeneratedAhead
      _genLastLayers      = lastLayers;
      _genLastWasBox      = lastWasBox;
      _genLastWasSpike    = lastWasSpike;
      _genLastWasPlatform = lastWasPlatform;
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

        // ── Hard extra: CT_mid a CT_spike/CT_spike1 ──────────────
        // Přidávají se jako samostatné překážky za aktuální překážkou
        // s vlastní mezerou (reactionGap). Nepřepisují výše postavenou překážku.
        // P(CT_mid after box) = 25%, P(CT_spike after box) = 15%
        if (lastWasBox && rng.nextDouble() < 0.25) {
          final midGap  = reactionGap * (1.2 + rng.nextDouble() * 0.8);
          final midX    = cursor + midGap;
          // CT_mid: mřížka bloků. Výška 2–5 vrstev (jako medium), šířka 3–10 bloků.
          // Grafika = CT_mid.png stohovaná do mřížky X×Y.
          // blockH = výška vrstvy (tileH), blockW podle poměru obrázku 1018×830
          const midBlockH = _tileH * tileScale;              // 23.75px
          const midBlockW = midBlockH * (1018.0 / 830.0);    // ~29.1px
          final midLayers = minLayers + rng.nextInt(maxLayers - minLayers + 1); // 2–5
          final midBlocks = 3 + rng.nextInt(8); // 3–10 bloků na šířku
          final midW      = midBlocks * midBlockW;
          final midH      = midLayers * midBlockH; // variabilní výška
          obstacles.add(Obstacle(
            x: midX, width: midW, height: midH,
            fromFloor: true, type: ObstacleType.hardMid,
          ));
          cursor = midX + midW;
          lastWasBox = false;
          lastWasSpike = false;
          lastWasPlatform = true;
          lastLayers = midLayers;
        } else if (lastWasBox && rng.nextDouble() < 0.15) {
          final spikeGap = reactionGap * (1.2 + rng.nextDouble() * 0.6);
          final spikeX   = cursor + spikeGap;
          // CT_spike nebo CT_spike1 (50/50)
          final isSpike1 = rng.nextBool();
          obstacles.add(Obstacle(
            x: spikeX, width: hardSpikeW, height: runnerRadius * 2.0,
            fromFloor: true,
            type: isSpike1 ? ObstacleType.hardSpike1 : ObstacleType.hardSpike,
          ));
          cursor = spikeX + hardSpikeW;
          lastWasBox  = false;
          lastWasSpike = true;
          lastWasPlatform = false;
          lastLayers = highThreshold;
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

    worldX    += speed * dtSec;
    // _runMeters = aktuální pozice v levelu přepočtená na metry
    // worldX / speed * speedMps = proporcionální přepočet
    _runMeters = worldX / speed * speedMps;

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
      // Persist checkpoint – ulož elapsed čas V TOMTO MOMENTĚ (= čas checkpointu)
      final elapsedAtCheckpoint = DateTime.now().difference(startTime).inMilliseconds;
      SharedPreferences.getInstance().then((prefs) {
        prefs.setDouble(widget.checkpointPrefsKey, lastCheckpointWorldX);
        prefs.setInt('last_checkpoint_count_${widget.modeName}', checkpoints);
        prefs.setInt(widget.elapsedMsPrefsKey, elapsedAtCheckpoint); // elapsed v místě checkpointu
      });
      _onBanner();
    }

    // fyzika
    final gNow = gravity * (gravityFlipped ? -1.0 : 1.0);
    vy += gNow * dtSec;
    runnerY += vy * dtSec;
    _applyGroundCeilClamp();

    // Jump buffer: pokud byl tap uložen a runner je nyní grounded → skoč
    if (_jumpBufferAt != null && grounded) {
      final bufferMs = widget.modeName == 'EASY' ? 180 : 120;
      final sinceBuffer = DateTime.now().difference(_jumpBufferAt!).inMilliseconds;
      if (sinceBuffer <= bufferMs) {
        vy = gravityFlipped ? jumpVelocity.abs() : jumpVelocity;
        grounded = false;
        _lastGroundedAt = null;
      }
      _jumpBufferAt = null; // buffer vždy spotřebuj
    }

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

    final isEasyMode = widget.modeName == 'EASY';

    for (final ob in obstacles) {
      if (ob.type != ObstacleType.box &&
          ob.type != ObstacleType.hardMid &&
          ob.type != ObstacleType.hardSpike) continue;

      final localFloor = baseGround - ob.groundOffset;
      final obTop      = localFloor - ob.height;

      if (isEasyMode) {
        // EASY: celý povrch walkable, žádný slope
        if (runnerWorldX < ob.x || runnerWorldX > ob.x + ob.width + runnerRadius) continue;
        if (obTop < ground) ground = obTop;
      } else if (ob.type == ObstacleType.hardMid || ob.type == ObstacleType.hardSpike) {
        // HARD CT_mid / CT_spike: walkable nahoře, slope varianta B (horní část) vpravo
        // Slope začíná od (x + width) po výšku překážky (horní polovina)
        final slopeStartX = ob.x + ob.width;
        final slopeH      = ob.height * 0.5; // slope jen v horní části (varianta B)
        final slopeLen    = slopeH + runnerRadius;
        final rightEdge   = slopeStartX + slopeLen;
        // Walkable oblast: od ob.x (killing zleva → hráč musí přijít zprava/seshora)
        // Povrch nahoře: od ob.x po slopeStartX
        if (runnerWorldX < ob.x || runnerWorldX > rightEdge) continue;
        if (runnerWorldX <= slopeStartX) {
          if (obTop < ground) ground = obTop;
        } else {
          // Slope: lineární interpolace od obTop → localFloor v horní části
          final t = (runnerWorldX - slopeStartX) / slopeLen;
          final slope = obTop + t * (localFloor - obTop);
          if (slope < ground) ground = slope;
        }
      } else {
        final sEndW      = _tileEndW * tileScale;
        const slopeShift = 25.0;
        final endStart   = ob.x + ob.width - sEndW + slopeShift;
        final slopeLen   = ob.height + runnerRadius;
        final rightEdge  = endStart + slopeLen;
        final sStartW    = _tileStartW * tileScale;
        final midStart   = ob.x + sStartW;

        if (runnerWorldX < midStart || runnerWorldX > rightEdge) continue;

        if (runnerWorldX <= endStart) {
          if (obTop < ground) ground = obTop;
        } else {
          final t = (runnerWorldX - endStart) / (rightEdge - endStart);
          final slope = obTop + t * (localFloor - obTop);
          if (slope < ground) ground = slope;
        }
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
    final rRight  = runnerWorldFront + runnerFrontOffset;

    for (final ob in obstacles) {
      // fromFloor=false je OK – spike na základně (typ C) musí také zabíjet
      if (ob.type != ObstacleType.spike &&
          ob.type != ObstacleType.hardSpike1) continue;
      if (ob.x > runnerWorldFront + 80) break;
      if (ob.x + ob.width < runnerWorldFront - 200) continue;

      final localFloor = baseGround - ob.groundOffset;
      final top    = localFloor - ob.height;
      final bottom = localFloor;

      // Easy spike: jednoduchý obdélníkový hitbox (ob.width × ob.height)
      // Medium spike: trojúhelníkový hitbox
      final bool hit;
      if (widget.tileScaleOverride != null) {
        // Přímý obdélník – hitbox přesně odpovídá vizuálu
        final overlapX = rRight >= ob.x && rLeft <= ob.x + ob.width;
        final overlapY = rBottom >= top && rTop <= bottom;
        hit = overlapX && overlapY;
      } else {
        final contactY = rBottom.clamp(top, bottom);
        final t = (bottom - contactY) / (bottom - top).clamp(1.0, double.infinity);
        final effectiveHalfW = (ob.width / 2) * (0.20 + 0.80 * (1.0 - t));
        final obCenterX = ob.x + ob.width / 2;
        final tSpike = ((contactY - rTop) / (rBottom - rTop).clamp(1.0, double.infinity)).clamp(0.0, 1.0);
        final rLeftSpike  = rLeft  + tSpike * (runnerWorldFront - rLeft);
        final rRightSpike = rRight + tSpike * (runnerWorldFront - rRight);
        final overlapX = rRightSpike >= obCenterX - effectiveHalfW &&
            rLeftSpike  <= obCenterX + effectiveHalfW;
        final effectiveTop = top + ob.height * 0.25;
        final overlapY = rBottom >= effectiveTop && rTop <= bottom;
        hit = overlapX && overlapY;
      }
      if (hit) return true;
    }
    return false;
  }

  double _effectiveCeilY(double screenH) => screenH * ceilYFrac;

  void _applyGroundCeilClamp() {
    final h = _screenH;
    final localGround = _effectiveGroundY(h, _runnerWorldX) - runnerRadius;
    final localCeil   = _effectiveCeilY(h) + runnerRadius;

    if (!gravityFlipped) {
      // Slope snap: pokud je runner do 1 výšky tilesH nad localGround → snap dolů
      // Tím runner "jede" po slope místo aby letěl nad ní
      const slopeSnapTolerance = 30.0; // px nad ground kde snap nastane
      if (runnerY >= localGround) {
        runnerY = localGround;
        vy = 0;
        if (!grounded) _lastGroundedAt = DateTime.now();
        grounded = true;
      } else if (runnerY >= localGround - slopeSnapTolerance && vy >= 0) {
        // Těsně nad ground a klesáme (nebo stojíme) → snap, runner běží
        // vy < 0 znamená aktivní skok → NESNAP
        runnerY = localGround;
        vy = 0;
        if (!grounded) _lastGroundedAt = DateTime.now();
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

    final rTop    = runnerY - runnerRadius;
    final rBottom = runnerY + runnerRadius;
    // Trojúhelník: a=levý horní, b=pravý horní, c=spodní střed
    // a: (runnerWorldFront - runnerRadius, rTop)
    // b: (runnerWorldFront + runnerHitboxTopRight, rTop)
    // c: (runnerWorldFront, rBottom)  ← jeden bod dole uprostřed
    final rLeftTop    = runnerWorldFront - runnerRadius;   // a – levý horní
    final rRightTop   = runnerWorldFront + runnerHitboxTopRight; // b – pravý horní
    final rBottomX    = runnerWorldFront;                  // c – spodní střed X
    // Pro kolizi: levá a pravá hrana se lineárně sbíhají od (a,b) k c
    // rLeftWorld a rRightWorld jsou nejširší (nahoře), zužují se dolů
    final rLeftWorld  = rLeftTop;   // levá hrana = a (horní) = nejlevější bod
    final rRightWorld = rRightTop;  // pravá hrana = b (horní) = nejpravější bod

    for (final ob in obstacles) {
      // Všechny překážky kolizní – i ty na základně (typ C, fromFloor=false)
      if (ob.x > runnerWorldFront + 80) break;
      if (ob.x + ob.width < runnerWorldFront - 200) continue;

      final localFloor = baseGround - ob.groundOffset;
      final top = localFloor - ob.height;
      final bottom = localFloor;
      final oLeft = ob.x;
      final oRight = ob.x + ob.width;

      // Trojúhelník a,b nahoře, c dole uprostřed.
      // Pro každou Y výšku kontaktu: levá hrana a→c, pravá hrana b→c
      final midY = (top + bottom) / 2.0;
      final tHit = ((midY - rTop) / (rBottom - rTop)).clamp(0.0, 1.0);
      // t=0 (nahoře) → plná šířka (a,b), t=1 (dole) → bod c (runnerWorldFront)
      final rLeftAtMid  = rLeftTop  + tHit * (rBottomX - rLeftTop);
      final rRightAtMid = rRightTop + tHit * (rBottomX - rRightTop);
      final overlapX = (rRightAtMid >= oLeft) && (rLeftAtMid <= oRight);
      final overlapY = (rBottom >= top) && (rTop <= bottom);
      if (!(overlapX && overlapY)) continue;

      if (ob.type == ObstacleType.spike) {
        // SPIKE: jakýkoli kontakt je smrt
        return true;
      } else if (ob.type == ObstacleType.hardSpike1) {
        // hardSpike1: jakýkoli kontakt je smrt (stejně jako easy spike)
        return true;
      } else if (ob.type == ObstacleType.hardMid || ob.type == ObstacleType.hardSpike) {
        // hardMid / hardSpike: killing zleva, nahoře walkable, vpravo slope
        if (rBottom <= top + 6) continue; // přelet shora → OK
        // Stojíme nahoře?
        final currentGroundTop = _effectiveGroundY(h, _runnerWorldX);
        if (grounded && currentGroundTop < baseGround) continue;
        // Boční náraz zleva → smrt
        if ((rLeftWorld < ob.x) && (rRightWorld > ob.x + 1)) return true;
      } else if (widget.modeName == 'EASY') {
        // EASY BOX: smrtící pouze čelní náraz (zleva)
        final currentGroundTop = _effectiveGroundY(h, _runnerWorldX);
        if (grounded && currentGroundTop < baseGround) continue;
        if (rBottom <= top + 6) continue;
        if ((rLeftWorld < oLeft) && (rRightWorld > oLeft + 1)) return true;
      } else {
        // BOX:
        final sStartW  = _tileStartW * tileScale;
        final midStart = oLeft + sStartW;

        // 1) stojíme na mid/end oblasti (grounded + ground elevovaný)? → OK
        final currentGroundTop = _effectiveGroundY(h, _runnerWorldX);
        if (_runnerWorldX >= midStart && grounded && currentGroundTop < baseGround) {
          continue;
        }
        // 2) přelet shora → toleruj
        if (rBottom <= top + 6) continue;
        // 3) boční náraz zleva → smrtící
        if ((rLeftWorld < oLeft) && (rRightWorld > oLeft + 1)) return true;
        // 4) přistání na start oblast → smrtící
        if (_runnerWorldX >= oLeft && _runnerWorldX < midStart && rBottom >= top) {
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

    // ── Výpočet nového skóre ──────────────────────────────────
    _sessionNewM = 0;
    final currentM = _runMeters.floorToDouble();
    if (currentM > _bestMeters) {
      _sessionNewM = currentM - _bestMeters;
      _bestMeters  = currentM;
      // Ulož rekord
      SharedPreferences.getInstance().then((prefs) {
        prefs.setDouble(widget.bestXPrefsKey, _bestMeters);
      });
      // Leaderboard snapshot
      LeaderboardModel.I.updatePlayer(
        SettingsService.I.username,
        PlayerProfile.I.milesTotal,
        km: _bestMeters,
      );
      // Míle za každých 1000m
      final newMiles = (_sessionNewM / 1000).floor();
      if (newMiles > 0) PlayerProfile.I.addMiles(newMiles);
      // Flash
      _triggerScoreFlash();
    }
    // _sessionNewM == 0 → flash se nezobrazí

    // ❄️ kompletní stop – čekáme na tap (po chvíli Death → Grounded)
    _longJumpTimer?.cancel();
    _longJumpTimer = null;
    // Snap runnera vždy na base ground (ne na překážku) + vizuální offset
    final baseGroundY = _screenH * groundYFrac;
    runnerY = baseGroundY - runnerRadius + runnerRadius * 0.8;
    setState(() {
      paused = true;
      _deadFrozen = true;
      _gameRunning = false;
    });
    // Vibrace při smrti – pouze pokud má uživatel zapnuté vibrace
    debugPrint('[DEATH] game_base: _deadFrozen=true, vibrationOn=${SettingsService.I.vibrationOn}');
    if (SettingsService.I.vibrationOn) {
      debugPrint('[DEATH] game_base: spouštím Vibration.vibrate()');
      Vibration.vibrate(duration: 400, amplitude: 255);
      debugPrint('[DEATH] game_base: Vibration.vibrate() zavoláno');
    } else {
      debugPrint('[DEATH] game_base: vibrace vypnuty, přeskakuji');
    }
    bgPlayingNotifier.value = false;
    _syncBgAnim();
    _armGroundedAfterDeath();
  }

  // ── Score flash + pulz v rohu ────────────────────────────────
  void _triggerScoreFlash() {
    _scoreFlashTimer?.cancel();
    setState(() {
      _scoreFlashVisible = true;
      _scoreFlashOpacity = 1.0;
    });
    // Po 2s začne fade 0.5s
    _scoreFlashTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      // Fade out za 0.5s (16ms kroky)
      int steps = 0;
      Timer.periodic(const Duration(milliseconds: 16), (t) {
        if (!mounted) { t.cancel(); return; }
        steps++;
        final opacity = 1.0 - (steps / 31); // 31 kroků ≈ 0.5s
        if (opacity <= 0) {
          t.cancel();
          setState(() { _scoreFlashVisible = false; _scoreFlashOpacity = 0; });
        } else {
          setState(() => _scoreFlashOpacity = opacity);
        }
      });
    });
    // Pulz čísla v rohu – zvětší na 200% za 0.25s, pak zpět za 0.25s
    _triggerScorePulse();
  }

  void _triggerScorePulse() {
    if (_scorePulsing) return;
    _scorePulsing = true;
    int steps = 0;
    Timer.periodic(const Duration(milliseconds: 16), (t) {
      if (!mounted) { t.cancel(); return; }
      steps++;
      final progress = steps / 31; // 0.5s celkem
      final scale = progress < 0.5
          ? 1.0 + progress * 2    // 1.0 → 2.0 za první půlku
          : 2.0 - (progress - 0.5) * 2; // 2.0 → 1.0 za druhou půlku
      if (steps >= 31) {
        t.cancel();
        setState(() { _scoreDisplayScale = 1.0; _scorePulsing = false; });
      } else {
        setState(() => _scoreDisplayScale = scale.clamp(1.0, 2.0));
      }
    });
  }

  /// Vrátí worldX posunuté dozadu tak aby byl reaction gap garantován.
  /// Ignoruje walkable BOX překážky – runner na nich může stát.
  /// Kontroluje pouze SPIKE a smrtící BOX (typ A, fromFloor=true, !walkable).
  double _safeSpawnX(double spawnX) {
    final minGap = widget.reactionTimeSec * speed * 2.0;
    for (int i = 0; i < 50; i++) {
      final runnerFront = spawnX + 40;
      bool safe = true;
      for (final ob in obstacles) {
        // Přeskoč překážky za runnerem
        if (ob.x + ob.width < runnerFront) continue;
        // Překážka dost daleko – OK
        if (ob.x > runnerFront + minGap) break;

        // Walkable BOX (platforma) – runner na ní může stát, není nebezpečná
        // Poznáme ji: type == box && šířka > start+end (má mid část)
        final isWalkableBox = ob.type == ObstacleType.box &&
            ob.groundOffset == 0 &&
            ob.width > (_tileStartW + _tileEndW) * tileScale;
        if (isWalkableBox) continue;

        // Smrtící překážka příliš blízko → posuň spawn dozadu
        spawnX = ob.x - minGap - 40;
        safe = false;
        break;
      }
      if (safe) break;
    }
    return spawnX;
  }

  void _respawnToCheckpoint() {
    _deathStageTimer?.cancel();
    worldX = _safeSpawnX(lastCheckpointWorldX);
    // _runMeters se neresetuje – měří celkovou vzdálenost od startu levelu
    startTime = DateTime.now().subtract(widget.checkpointFreq * checkpoints);
    nextCheckpointIn = widget.checkpointFreq;
    // Nastav Y pozici až po nastavení worldX aby _effectiveGroundY
    // správně zohlednil překážky na aktuální X pozici
    _stickToGround();
    // Pojistka: pokud je runner stále v kolizi, posuň ho dál dozadu
    int safetyIter = 0;
    while (_collides() && safetyIter < 20) {
      worldX -= speed * 0.1; // posuň o 100ms dozadu
      _stickToGround();
      safetyIter++;
    }
    bgPlayingNotifier.value = true; // rovnou bez GO intra
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
      LeaderboardModel.I.updatePlayer(SettingsService.I.username, PlayerProfile.I.milesTotal,
          km: _bestMeters);
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

    LeaderboardModel.I.updatePlayer(SettingsService.I.username, PlayerProfile.I.milesTotal,
        km: _bestMeters);
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
      final sinceDeathMs = _lastDeathAt == null
          ? 999
          : DateTime.now().difference(_lastDeathAt!).inMilliseconds;
      if (sinceDeathMs >= 280) _respawnToCheckpoint();
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

    // Jump buffer: zapamatuj tap i když runner není grounded
    _jumpBufferAt = DateTime.now();

    // Coyote time: dovol skok krátce po opuštění překážky
    final coyoteMs = widget.modeName == 'EASY' ? 120 : 80;
    final sinceGrounded = _lastGroundedAt == null
        ? 9999
        : DateTime.now().difference(_lastGroundedAt!).inMilliseconds;
    final canCoyote = !grounded && sinceGrounded <= coyoteMs;

    if (grounded || canCoyote) {
      setState(() {
        vy = gravityFlipped ? jumpVelocity.abs() : jumpVelocity;
        grounded = false;
        _lastGroundedAt = null;
        _jumpBufferAt = null; // buffer spotřebován
      });
    }
  }

  void _openIngame() {
    if (_loading) return; // během načítání neotvírat
    setState(() => paused = true);
    bgPlayingNotifier.value = false;
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
        if (_gameRunning) bgPlayingNotifier.value = true;
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
    final f = widget.spriteFolder;
    return (
    start: '${f}${p}_start.png',
    mid:   '${f}${p}_mid.png',
    fill:  '${f}${p}_fill.png',
    end:   '${f}${p}_end.png',
    );
  }

  // SPIKE: sprite dle prefixu (HL_spike.png, MT_spike.png atd.)
  // Fallback na spike.png pokud prefix-specifický neexistuje
  ({String start, String mid, String fill, String end}) get _spikeSprites {
    final p = widget.spritePrefix;
    final f = widget.spriteFolder;
    final path = '${f}${p}_spike.png';
    return (start: path, mid: path, fill: path, end: path);
  }

  // Hard CT_spike (sudy) sprite
  String get _hardSpikeSprite => '${widget.spriteFolder}${widget.spritePrefix}_spike.png';
  // Hard CT_spike1 sprite (stejná grafika jako easy spike)
  String get _hardSpike1Sprite => 'assets/images/easy/HL_spike.png';

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
  // Background helpers
  // ———————————————————————————————————————————————————————————
  // ── DEV menu (vpravo dole) ───────────────────────────────────
  Widget _buildDevMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Přegenerovat seed (reset bestX + nový seed)
        FloatingActionButton.small(
          heroTag: 'dev_regen',
          tooltip: 'Smaž seedy a jdi na výběr obtížnosti (DEV)',
          backgroundColor: const Color(0xFFB03030),
          onPressed: () async {
            // Smaž seedy všech módů
            final prefs = await SharedPreferences.getInstance();
            for (final mode in ['EASY', 'MEDIUM', 'HARD', 'ENDLESS']) {
              await prefs.remove('level_seed_$mode');
              await prefs.remove('best_worldx_v3_$mode');
              await prefs.remove('last_checkpoint_$mode');
              await prefs.remove('last_checkpoint_count_$mode');
              await prefs.remove('last_elapsed_ms_$mode');
            }
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
        // Reset pouze bestWorldX (seed zůstane, vzdálenost se resetuje)
        FloatingActionButton.small(
          heroTag: 'dev_reset_dist',
          tooltip: 'Reset vzdálenosti (DEV)',
          backgroundColor: const Color(0xFF307030),
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove(widget.bestXPrefsKey);
            setState(() { _bestMeters = 0; _runMeters = 0; });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('📍 Vzdálenost resetována – seed zachován'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
          child: const Icon(Icons.social_distance, size: 18),
        ),
        const SizedBox(height: 8),
        // Instant win
        FloatingActionButton(
          heroTag: 'dev_win',
          tooltip: 'Dokončit level (DEV)',
          onPressed: _devInstantWin,
          child: const Icon(Icons.crop_square),
        ),
      ],
    );
  }

  // Formátování vzdálenosti v dobových jednotkách
  // Vstup = metry (double)
  // Pod 1000: kroků / steps
  // Nad 1000: mil / miles (1 des. místo)
  // 1 míle = 1000 kroků (zjednodušená antická míle)
  static const double _stepsPerMile = 1000.0;

  String _formatSteps(double meters) {
    final isCz = SettingsService.I.lang == Lang.cz;
    if (meters < _stepsPerMile) {
      final steps = meters.round();
      return isCz ? '$steps kroků' : '$steps steps';
    }
    final miles = meters / _stepsPerMile;
    return isCz
        ? '${miles.toStringAsFixed(1)} mil'
        : '${miles.toStringAsFixed(1)} miles';
  }

  // HUD zobrazuje nejlepší dosažené metry v tomto levelu
  double get _totalMeters => _bestMeters;

  Widget _buildBackgroundLayer() {
    if (_hasCustomBackground) {
      // Builder zajistí čerstvý context jako child GamePlayingScope
      // aby GamePlayingScope.of() správně zaregistroval dependency a rebuildo
      return Builder(builder: (ctx) => widget.backgroundBuilder!(ctx));
    }
    final ctrl = _bgGifCtrl;
    if (ctrl == null) return const SizedBox.expand();
    return SizedBox.expand(
      child: Gif(
        controller: ctrl,
        autostart: Autostart.no,
        image: const AssetImage(_bgGif),
        fit: BoxFit.fill,
      ),
    );
  }

  Widget _buildBackgroundOverlay() {
    if (_hasCustomBackground) return const SizedBox.shrink();
    return Positioned.fill(
      child: Container(color: Colors.black.withOpacity(0.35)),
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
    if (false) {
      // Endless má vlastní progress bar v endless_run.dart
      progress = 0;
      label = '';
    } else {
      // Progress = elapsed / total
      // _savedElapsedMs > 0 = restore z checkpointu, drž tuto hodnotu dokud hra nezačne
      final int elapsedMs;
      if (_savedElapsedMs > 0) {
        elapsedMs = _savedElapsedMs;
      } else if (_gameRunning) {
        elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      } else {
        elapsedMs = lastTick.inMilliseconds.clamp(0, widget.length.inMilliseconds);
      }
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
    if (_awaitFirstTap) {
      // Před prvním tapem zobraz Ready
      playerSprite = _readyImg;
    } else if (_intro != IntroPhase.none) {
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

    return GamePlayingScope(
      notifier: bgPlayingNotifier,
      child: Scaffold(
        backgroundColor: Colors.black,
        floatingActionButton: _buildDevMenu(),
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
              Positioned.fill(child: _buildBackgroundLayer()),
              _buildBackgroundOverlay(),

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
                  obstacles: obstacles,
                  runnerScreenX: runnerScreenX,
                ),
                child: const SizedBox.expand(),
              ),

              // Překážky (dlaždicované obrázky)
              ...obstacleWidgets,

              // Postavička – pozice dle runnerY (fyzikální stav)
              Positioned(
                left: runnerScreenX - (runnerRadius * 2 * runnerScale),
                top:  runnerY       - (runnerRadius * 2 * runnerScale),
                width:  runnerRadius * 4 * runnerScale,
                height: runnerRadius * 4 * runnerScale,
                child: IgnorePointer(
                  ignoring: true,
                  child: Image.asset(playerSprite, fit: BoxFit.contain, alignment: Alignment.bottomCenter),
                ),
              ),

              // pravý horní roh – tlačítko do ingame settings
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 8,
                child: GestureDetector(
                  onTap: _openIngame,
                  child: Image.asset(_gearIcon, width: 65, height: 65, fit: BoxFit.contain),
                ),
              ),

              // ── Progress bar nahoře uprostřed ──────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: size.width * 0.20,
                right: size.width * 0.20,
                child: _buildProgressBar(size),
              ),

              // ── Skóre + Menu tlačítko – levý horní roh ──────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: _scoreDisplayScale,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _formatSteps(_totalMeters),
                        style: TextStyle(
                          fontFamily: 'Augarix',
                          fontSize: size.height * 0.045,
                          color: const Color(0xFF555555),
                          shadows: const [Shadow(
                            color: Color(0x88000000),
                            offset: Offset(1, 1),
                            blurRadius: 3,
                          )],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () {
                        // Ulož checkpoint a vrať se do menu
                        // Checkpoint a elapsed byly uloženy při průchodu checkpointem
                        // Menu tlačítko jen uloží worldX pro jistotu, elapsed NEPŘEPISUJE
                        SharedPreferences.getInstance().then((prefs) {
                          prefs.setDouble(widget.checkpointPrefsKey, lastCheckpointWorldX);
                          prefs.setInt('last_checkpoint_count_${widget.modeName}', checkpoints);
                        });
                        MusicService.I.stopGame().then((_) => MusicService.I.ensureMenuMusic());
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.30),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withOpacity(0.30)),
                        ),
                        child: Text(
                          T.backToMenu(),
                          style: const TextStyle(
                            fontFamily: 'Augarix',
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Score flash – střed obrazovky ──────────────────
              if (_scoreFlashVisible)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Opacity(
                        opacity: _scoreFlashOpacity,
                        child: Text(
                          '+${_formatSteps(_sessionNewM)}',
                          style: TextStyle(
                            fontFamily: 'Augarix',
                            fontSize: size.height * scoreFlashSizePct,
                            color: const Color(0xFF444444), // tmavě šedá
                            shadows: const [
                              Shadow(color: Color(0xAA000000), offset: Offset(2, 2), blurRadius: 6),
                            ],
                          ),
                        ),
                      ),
                    ),
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
                              _isRestoringLevel
                                  ? (SettingsService.I.lang == Lang.cz
                                  ? 'Nahrávám level...'
                                  : 'Restoring level...')
                                  : (SettingsService.I.lang == Lang.cz
                                  ? 'Generuji level...'
                                  : 'Generating level...'),
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
      ),
    );
  }

  // ———————————————————————————————————————————————————————————
  // Dlaždicování překážek do viditelného okna
  // ———————————————————————————————————————————————————————————
  List<Widget> _buildVisibleObstacleTiles(Size size, double runnerScreenX) {
    final groundY = size.height * groundYFrac;
    final List<Widget> children = [];
    // 🔍 DEBUG – loguj jen jednou za 60 framů
    if (obstacles.isNotEmpty && (_runFrame == 0)) {
      final visible = obstacles.where((o) {
        final dx = o.x - worldX;
        final sx = runnerScreenX + dx;
        return sx > -256 && sx < size.width + 256;
      }).length;
      debugPrint('BUILD TILES: worldX=$worldX obstacles=${obstacles.length} visible=$visible screenW=${size.width}');
    }

    // Škálované rozměry dlaždic (box)
    final sStartW = _tileStartW * effectiveTileScale;
    final sEndW   = _tileEndW   * effectiveTileScale;
    final sMidW   = _tileMidW   * effectiveTileScale;
    final sFillW  = _tileMidW   * effectiveTileScale;
    final sTileH  = _tileH      * effectiveTileScale;
    // Vizuální scale faktor: ob.height je spočítán s tileScale (fyzika),
    // renderer ho musí přepočítat na effectiveTileScale (vizuál)
    final visualScaleFactor = effectiveTileScale / tileScale;

    // Spike používá vlastní scale + visualScaleFactor pro vizuální zvětšení
    final sSpikeW = _tileH * spikeScale * visualScaleFactor;
    final sSpikeH = _tileH * spikeScale * visualScaleFactor;

    // Dva průchody: nejdřív BOX základny (vzadu), pak SPIKE a nástavby (vpředu)
    // Tím spike nikdy není zakryt základnou C
    final renderOrder = [
      ...obstacles.where((o) => o.type == ObstacleType.box && o.groundOffset == 0),
      ...obstacles.where((o) => o.type == ObstacleType.box && o.groundOffset > 0),
      ...obstacles.where((o) => o.type == ObstacleType.hardMid),
      ...obstacles.where((o) => o.type == ObstacleType.hardSpike),
      ...obstacles.where((o) => o.type == ObstacleType.hardSpike1),
      ...obstacles.where((o) => o.type == ObstacleType.spike),
    ];
    for (final ob in renderOrder) {
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
        final obGroundYSpike = groundY - ob.groundOffset;
        // Pro Easy: ob.width a ob.height jsou vizuální → použij přímo
        // Pro Medium+: ob.width je fyzická → přepočítej přes spikeW
        final double spikeRenderW;
        final double spikeRenderH;
        final int spikeCount;
        if (widget.tileScaleOverride != null) {
          // Easy: spike = blok želvy (midW × effectiveTileScale)
          spikeRenderW = _tileH * easySpikeScale;
          spikeRenderH = _tileH * easySpikeScale;
          spikeCount   = max(1, (ob.width / spikeRenderW).round());
        } else {
          // Medium+: fyzická šířka → vizuální
          final physSpikeW = _tileH * spikeScale;
          spikeCount   = max(1, (ob.width / physSpikeW).round());
          spikeRenderW = sSpikeW;
          spikeRenderH = sSpikeH;
        }
        final actualW = spikeCount * spikeRenderW;
        // Spike na základně C: zanořit o 8px aby vizuálně seděl na povrchu
        final spikeVisualSink = ob.groundOffset > 0 ? 8.0 : 0.0;
        final spikeTop = obGroundYSpike - spikeRenderH + spikeVisualSink;
        if (screenX0 > size.width + 256 || screenX0 + actualW < -256) continue;
        for (int s = 0; s < spikeCount; s++) {
          children.add(Positioned(
            left: screenX0 + s * spikeRenderW,
            top: spikeTop,
            width: spikeRenderW,
            height: spikeRenderH,
            child: _safeImage(sp.mid, fit: BoxFit.fill),
          ));
        }
        continue;
      }

      // ── Hard CT_mid rendering (mřížka stohovaných CT_mid.png bloků) ──
      if (ob.type == ObstacleType.hardMid) {
        final obGroundYH = groundY - ob.groundOffset;
        // CT_mid.png: 1018×830, poměr 1.227 → blockW zachová poměr obrázku
        const stepH = _tileH * tileScale;            // 23.75px (krok vrstvy)
        const stepW = stepH * (1018.0 / 830.0);      // ~29.1px (krok sloupce)
        // Bloky se vykreslí 2.5× větší než krok → překryv vyplní prázdná místa v obrázku
        const overscan = 2.5;
        const drawW = stepW * overscan;
        const drawH = stepH * overscan;
        final cols = max(1, (ob.width  / stepW).round());
        final rows = max(1, (ob.height / stepH).round());
        if (screenX0 > size.width + 256 || screenX0 + ob.width < -256) continue;
        // Vyplň mřížku odspodu nahoru; blok centrovaný na buňku (krok), přesah ven
        const offX = (drawW - stepW) / 2;
        const offY = (drawH - stepH) / 2;
        for (int r = 0; r < rows; r++) {
          // r=0 = nejspodnější vrstva u země, r=rows-1 = vrchní
          final cellTop = obGroundYH - (r + 1) * stepH;
          for (int c = 0; c < cols; c++) {
            children.add(Positioned(
              left:   screenX0 + c * stepW - offX,
              top:    cellTop - offY,
              width:  drawW,
              height: drawH,
              child:  _safeImage('${widget.spriteFolder}${widget.spritePrefix}_mid.png'),
            ));
          }
        }
        continue;
      }

      // ── Hard CT_spike / CT_spike1 rendering ───────────────────
      if (ob.type == ObstacleType.hardSpike ||
          ob.type == ObstacleType.hardSpike1) {
        final String sprite = ob.type == ObstacleType.hardSpike
            ? _hardSpikeSprite
            : _hardSpike1Sprite;
        final obGroundYH = groundY - ob.groundOffset;
        final imgTop     = obGroundYH - ob.height;
        if (screenX0 > size.width + 256 || screenX0 + ob.width < -256) continue;
        children.add(Positioned(
          left: screenX0, top: imgTop,
          width: ob.width, height: ob.height,
          child: _safeImage(sprite, fit: BoxFit.fill),
        ));
        continue;
      }

      // ── Box rendering ─────────────────────────────────────────
      final obGroundY = groundY - ob.groundOffset;

      if (widget.modeName == 'EASY') {
        // Easy: jen mid dlaždice za sebou s 10% překryvem
        final midW    = sMidW;
        final step    = midW * 0.90;
        final midCols = max(1, (ob.width / step).round());
        final imgTop  = obGroundY - sTileH;
        if (screenX0 > size.width + 256 || screenX0 + ob.width < -256) continue;
        for (int m = 0; m < midCols; m++) {
          children.add(Positioned(
            left: screenX0 + m * step,
            top: imgTop,
            width: midW,
            height: sTileH,
            child: _safeImage(sp.mid, fit: BoxFit.fill),
          ));
        }
      } else if (widget.tileScaleOverride != null) {
        // EASY: flat rendering – jen mid dlaždice v jedné řadě
        // ob.width a ob.height jsou už vizuální (effectiveTileScale)
        final midCols = max(1, (ob.width / sMidW).round());
        final rightmost = screenX0 + midCols * sMidW;
        if (screenX0 > size.width + 256 || rightmost < -256) continue;

        final midTop = obGroundY - sTileH;
        for (int m = 0; m < midCols; m++) {
          children.add(Positioned(
            left: screenX0 + m * sMidW,
            top: midTop,
            width: sMidW,
            height: sTileH,
            child: _safeImage(sp.mid, fit: BoxFit.fill),
          ));
        }
        continue; // Easy hotovo – přeskoč Medium pyramid rendering
      } else if (widget.modeName == 'HARD') {
        // HARD: box se staví ze stejné CT_mid mřížky jako hardMid.
        // CT_start/CT_end v hard neexistují → vše z CT_mid.png.
        const stepH = _tileH * tileScale;
        const stepW = stepH * (1018.0 / 830.0);
        const overscan = 2.5;
        const drawW = stepW * overscan;
        const drawH = stepH * overscan;
        final cols = max(1, (ob.width  / stepW).round());
        final rows = max(1, (ob.height / stepH).round());
        if (screenX0 > size.width + 256 || screenX0 + ob.width < -256) continue;
        const offX = (drawW - stepW) / 2;
        const offY = (drawH - stepH) / 2;
        for (int r = 0; r < rows; r++) {
          final cellTop = obGroundY - (r + 1) * stepH;
          for (int c = 0; c < cols; c++) {
            children.add(Positioned(
              left:   screenX0 + c * stepW - offX,
              top:    cellTop - offY,
              width:  drawW,
              height: drawH,
              child:  _safeImage('${widget.spriteFolder}${widget.spritePrefix}_mid.png'),
            ));
          }
        }
        continue;
      } else {
        // MEDIUM+: pyramid rendering
        final physMidW = _tileMidW * tileScale;
        final physStartW = _tileStartW * tileScale;
        final physEndW = _tileEndW * tileScale;
        final midCols = max(1, ((ob.width - physStartW - physEndW) / physMidW).round());
        final visObH = ob.height * visualScaleFactor;
        final fillRowCount = max(0, ((visObH - sTileH) / sTileH).ceil());

        final leftmost  = screenX0 - fillRowCount * sFillW;
        final rightmost = screenX0 + sStartW + midCols * sMidW + sEndW;
        if (leftmost > size.width + 256 || rightmost < -256) continue;

        final midTop = obGroundY - (fillRowCount + 1) * sTileH;
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
          final rowY      = obGroundY - (fillRowCount - row + 1) * sTileH;
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
      } // konec else (Medium+ pyramid rendering)
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
  final List<Obstacle> obstacles;
  final double runnerScreenX;
  // runnerY je již field výše

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
    required this.obstacles,
    required this.runnerScreenX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintDebugHitboxes(canvas, size);
  }

  void _paintDebugHitboxes(Canvas canvas, Size size) {
    final groundY    = size.height * GameBaseState.groundYFrac;
    final worldOffset = mirroring ? (size.width - runnerScreenX) : runnerScreenX;

    // Paint styles
    final hitboxPaint = Paint()
      ..color = const Color(0xCCFF2020)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final walkablePaint = Paint()
      ..color = const Color(0xCC00FF88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final slopePaint = Paint()
      ..color = const Color(0xCCFFAA00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final groundPaint = Paint()
      ..color = const Color(0x88FF2020)
      ..strokeWidth = 1.5;

    // Zem (červená linka)
    canvas.drawLine(Offset(0, groundY), Offset(size.width, groundY), groundPaint);

    // Runner hitbox – trojúhelník: a=levý horní, b=pravý horní, c=spodní střed
    final rLeftH  = runnerScreenX - GameBaseState.runnerRadius;        // a
    final rRightH = runnerScreenX + GameBaseState.runnerHitboxTopRight; // b (posunutelný)
    final rCenterBot = runnerScreenX;                                   // c – spodní střed
    final rTopY   = runnerY - GameBaseState.runnerRadius;
    final rBotY   = runnerY + GameBaseState.runnerRadius;
    final triPaint = Paint()
      ..color = const Color(0xCCAA00FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final path = Path()
      ..moveTo(rLeftH, rTopY)      // a – levý horní
      ..lineTo(rRightH, rTopY)     // b – pravý horní (posunutelný runnerHitboxTopRight)
      ..lineTo(rCenterBot, rBotY)  // c – spodní střed
      ..close();
    canvas.drawPath(path, triPaint);

    const tileScale   = GameBaseState.tileScale;
    const tileStartW  = GameBaseState.tileStartWPub;
    const tileEndW    = GameBaseState.tileEndWPub;
    const runnerRadius = GameBaseState.runnerRadius;

    for (final ob in obstacles) {
      final dx = ob.x - worldX;
      final screenX = mirroring
          ? (size.width - (worldOffset + dx))
          : (worldOffset + dx);

      // Přeskoč pokud mimo obrazovku
      if (screenX > size.width + 300 || screenX + ob.width < -300) continue;

      final localFloor = groundY - ob.groundOffset;
      final obTop = localFloor - ob.height;

      if (ob.type == ObstacleType.spike || ob.type == ObstacleType.hardSpike1) {
        // Spike / hardSpike1: červený obdélník = killing ze všech stran
        canvas.drawRect(
          Rect.fromLTWH(screenX, obTop, ob.width, ob.height),
          hitboxPaint,
        );
      } else if (ob.type == ObstacleType.hardMid || ob.type == ObstacleType.hardSpike) {
        // hardMid / hardSpike: červený obdélník tělo, zelená walkable nahoře, oranžová slope
        canvas.drawRect(Rect.fromLTWH(screenX, obTop, ob.width, ob.height), hitboxPaint);
        // Walkable nahoře
        canvas.drawLine(Offset(screenX, obTop), Offset(screenX + ob.width, obTop), walkablePaint);
        // Slope varianta B: horní polovina pravé strany
        final slopeStartX = screenX + ob.width;
        final slopeH      = ob.height * 0.5;
        final slopeLen    = slopeH + runnerRadius;
        canvas.drawLine(
          Offset(slopeStartX, obTop),
          Offset(slopeStartX + slopeLen, obTop + ob.height),
          slopePaint,
        );
        // Svislá dolní část (wall)
        canvas.drawLine(
          Offset(slopeStartX, obTop + slopeH),
          Offset(slopeStartX, obTop + ob.height),
          hitboxPaint,
        );
      } else if (ob.type == ObstacleType.box) {
        // BOX: červený obdélník = celý hitbox
        canvas.drawRect(
          Rect.fromLTWH(screenX, obTop, ob.width, ob.height),
          hitboxPaint,
        );

        final sStartW  = tileStartW * tileScale;
        final sEndW    = tileEndW   * tileScale;
        final midStart = screenX + sStartW;
        const slopeShift = 25.0;
        final endStartX  = screenX + ob.width - sEndW + slopeShift;
        final slopeLen   = ob.height + runnerRadius;
        final rightEdgeX = endStartX + slopeLen;
        // Zelená linka = walkable povrch (od midStart po endStart)
        if (midStart < endStartX) {
          canvas.drawLine(
            Offset(midStart, obTop),
            Offset(endStartX, obTop),
            walkablePaint,
          );
        }

        // Oranžová linka = slope (od endStart po rightEdge ~45°)
        canvas.drawLine(
          Offset(endStartX, obTop),
          Offset(rightEdgeX, localFloor),
          slopePaint,
        );

        // Červená svislá čára = start (smrtící levý okraj)
        canvas.drawLine(
          Offset(screenX, obTop),
          Offset(screenX, localFloor),
          hitboxPaint,
        );
      }
    }
  }

  String get _hudMode => mode;

  void _t(Canvas c, String s, Offset p, TextStyle st) {
    final tp = TextPainter(text: TextSpan(text: s, style: st), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, p);
  }

  @override
  bool shouldRepaint(covariant _RunnerPainter o) => true; // debug – vždy překresli
}

// test commit