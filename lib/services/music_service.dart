import 'dart:math';
import 'package:just_audio/just_audio.dart';
import '../services/settings_service.dart';

class MusicService {
  static final MusicService I = MusicService._();
  MusicService._();

  final AudioPlayer _menuPlayer = AudioPlayer();
  final AudioPlayer _gamePlayer = AudioPlayer();

  bool _menuInitialized = false;
  bool _enabled = true;
  String? _menuAsset;

  int? _currentSeed;
  MusicStyle? _styleForSeed;
  int? _lockedTrackIndex1to6;

  /// Zapni/vypni hudbu. Když `startMenuIfOn=false`, při zapnutí nespouštěj menu hudbu.
  Future<void> setEnabled(bool on, {bool startMenuIfOn = true}) async {
    _enabled = on;
    if (on) {
      if (startMenuIfOn) {
        await ensureMenuMusic();
      } else {
        // jen zajisti, že menu nehraje
        await _menuPlayer.pause();
      }
    } else {
      await _menuPlayer.pause();
      await _gamePlayer.pause();
    }
  }

  Future<void> ensureMenuMusic() async {
    if (!_enabled) return;

    final style = SettingsService.I.musicStyle;
    final desired = (style == MusicStyle.traditional)
        ? 'assets/music/menu_t.mp3'
        : 'assets/music/menu_m.mp3';

    if (!_menuInitialized) {
      await _menuPlayer.setLoopMode(LoopMode.one);
      _menuInitialized = true;
    }
    if (_menuAsset != desired) {
      await _menuPlayer.setAsset(desired);
      _menuAsset = desired;
    }
    if (!_menuPlayer.playing) {
      // ignore: unawaited_futures
      _menuPlayer.play();
    }
  }

  Future<void> stopMenuMusic() async {
    if (_menuInitialized) {
      await _menuPlayer.stop();
    } else {
      await _menuPlayer.pause();
    }
  }

  Future<void> lockTrackForSeed({required int seed, bool forceRepick = false}) async {
    final style = SettingsService.I.musicStyle;
    final seedChanged = _currentSeed != seed;
    final styleChanged = _styleForSeed != style;

    if (_lockedTrackIndex1to6 == null || forceRepick || seedChanged || styleChanged) {
      final rnd = Random();
      _lockedTrackIndex1to6 = 1 + rnd.nextInt(6);
      _currentSeed = seed;
      _styleForSeed = style;
    }
  }

  Future<void> playGameTrackForLockedSeed() async {
    if (!_enabled) return;
    if (_lockedTrackIndex1to6 == null) return;

    // vždy vypni menu, ať nehraje souběžně
    await stopMenuMusic();

    final style = _styleForSeed ?? SettingsService.I.musicStyle;
    final idx = _lockedTrackIndex1to6!.clamp(1, 6);
    final asset = (style == MusicStyle.traditional)
        ? 'assets/music/track_t$idx.mp3'
        : 'assets/music/track_m$idx.mp3';

    await _gamePlayer.setLoopMode(LoopMode.one);
    await _gamePlayer.setAsset(asset);
    // ignore: unawaited_futures
    _gamePlayer.play();
  }

  Future<void> onNewSeed({required int newSeed}) async {
    await lockTrackForSeed(seed: newSeed, forceRepick: true);
  }

  Future<void> stopGame() async {
    await _gamePlayer.stop();
  }

  Future<void> startRunWithSeed(int seed) async {
    await stopMenuMusic();
    await lockTrackForSeed(seed: seed, forceRepick: true);
    await playGameTrackForLockedSeed();
  }

  /// Okamžitě aplikuj změnu stylu v rámci HRY (nezmění uzamčený index),
  /// zastaví menu přehrávač a přepne herní asset. Pokud je hudba vypnutá, nic nepouští.
  Future<void> applyStyleNow({bool playInGame = true}) async {
    _styleForSeed = SettingsService.I.musicStyle; // drž styl k seedu v sync
    if (!_enabled || !SettingsService.I.musicOn) {
      // jen udrž vnitřní stav; nic nepouštěj
      return;
    }
    if (!playInGame) return;

    // přehraj aktuální uzamčený track v novém stylu a ujisti se, že menu je off
    await playGameTrackForLockedSeed();
  }
}
