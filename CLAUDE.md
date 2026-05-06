# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**AugiRun** — a Flutter endless runner game in the style of Geometry Dash, targeting Android and iOS. The player runs through procedurally generated obstacle courses across four difficulty modes: Easy, Medium, Hard, and Endless.

## Commands

```bash
# Run on connected device / emulator
flutter run

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Static analysis (lint)
flutter analyze

# Build
flutter build apk          # Android
flutter build ios          # iOS

# Regenerate launcher icons (after changing assets/images/icon.png)
flutter pub run flutter_launcher_icons

# Regenerate native splash screen
flutter pub run flutter_native_splash:create
```

## Architecture

### Singleton services (access via `.I`)

All services are lazily initialized singletons — **never instantiate directly**.

| Class | File | Purpose |
|---|---|---|
| `SettingsService.I` | `lib/services/settings_service.dart` | Persists lang, musicOn, musicStyle, vibration, username, characterId via SharedPreferences. Extends `ChangeNotifier` — `AugiRunApp` rebuilds on change. |
| `MusicService.I` | `lib/services/music_service.dart` | Manages two `AudioPlayer` instances: menu and game. Tracks are selected by seed + `MusicStyle` (traditional/modern). |
| `PlayerProfile.I` | `lib/models/player_prefs.dart` | In-memory total miles counter for current session. |
| `AchLogic.I` | `lib/achievements/ach_logic.dart` | Daily achievement system — rolls 3 random achievements per session, tracks progress, awards miles on completion. |
| `LeaderboardModel.I` | `lib/models/leaderboard_model.dart` | In-memory seeded leaderboard (100 entries). Sorted by `km` (precise distance), not miles. |

### Game engine — `GameBase` / `GameBaseState`

`lib/game/game_base.dart` is the core. All game modes extend `GameBase` (widget config) and `GameBaseState` (the full game loop):

- **Obstacle generation**: `_ensureGeneratedAhead()` procedurally generates obstacles ahead of `worldX` using the seeded `rng`. Each mode configures `reactionTimeSec` to guarantee reaction time between obstacles.
- **Physics**: fixed-timestep timer at 60 fps. `gravity`, `jumpVelocity`, and `gravityFlipped` drive runner movement. Hitbox is a triangle (not a circle), with `runnerFrontOffset` providing "benefit of the doubt" on the right.
- **Seed persistence**: each mode stores its current seed in SharedPreferences under `level_seed_{modeName}`. The best distance is stored under `best_worldx_v3_{modeName}`.
- **`GamePlayingScope`**: `InheritedNotifier<ValueNotifier<bool>>` that propagates play/pause state to the background widget without rebuilding the game layer.
- **Sprite naming convention**: `{prefix}_start.png`, `{prefix}_mid.png`, `{prefix}_end.png`, `{prefix}_fill.png`, `{prefix}_spike.png`. Prefixes: `HL` (Easy/hills), `MT` (Medium/mountains), `CT` (Hard/city).

### Game modes

Each mode in `lib/game/` is a thin subclass that supplies config to `GameBase`:

```
EasyRun    → spritePrefix: 'HL', spriteFolder: 'assets/images/easy/', tileScaleOverride: 5, reactionTimeSec: 0.8
MediumRun  → spritePrefix: 'MT', reactionTimeSec: 0.8
HardRun    → spritePrefix: 'CT', reactionTimeSec: 0.5
EndlessRun → reactionTimeSec: 0.8, stayDead: false
```

### Localization

All UI strings go through `T.*()` static methods in `lib/texty.dart`. The active language is set on `T.lang` by `AugiRunApp` whenever `SettingsService` notifies. **Never hardcode user-visible strings** — add them to `texty.dart` with both CZ and EN variants.

### UI components

`lib/ui/ui_standard.dart` — abstract class `UiStd` with reusable settings-screen widgets: `UiStd.row()`, `UiStd.segmented()`, `UiStd.characterPicker()`, `UiStd.sectionTitle()`. Use these instead of building custom settings rows.

### Parallax background

`lib/widgets/parallax_bg.dart` — `ParallaxBackground` drives multiple `AnimationController` instances. Two layer modes: `scroll` (seamless horizontal loop) and `oscillate` (sine-wave sway). Pause/resume is driven by `GamePlayingScope`.

### Navigation flow

```
MainMenu → RunSelectScreen → [EasyRun | MediumRun | HardRun | EndlessRun]
         ↘ SettingsScreen
         ↘ LeaderboardScreen
         ↘ AchievementsScreen
```

Music transitions: `MusicService` stops menu music when a game starts and resumes it when returning to `MainMenu`.

## Key constants (in `GameBaseState`)

| Constant | Value | Notes |
|---|---|---|
| `baseSpeedPxPerSec` | 520 | Base run speed |
| `runnerRadius` | 36 | Visual only |
| `runnerFrontOffset` | 28.0 | Right edge of hitbox (smaller = more forgiving) |
| `groundYFrac` | 0.90 | Ground line as fraction of screen height |
| `speedMps` | 6.0 | Real-world speed for distance display |
| `SAFE_BOOT` | false | Set `true` in `main.dart` to skip game for startup debugging |

## Asset structure

- `assets/images/run/` — runner animation frames (Ready, Set, Go, Run1–8, Jump1, Death, Grounded)
- `assets/images/easy/` — Easy mode sprites (HL_*)
- `assets/images/hard/` — Hard mode sprites (CT_*)
- `assets/images/` root — Medium (MT_*) and shared sprites
- `assets/music/` — `menu_t.mp3` / `menu_m.mp3` (menu), `track_t1–6.mp3` / `track_m1–6.mp3` (game)
- `assets/fonts/Augarix.otf` — custom font used everywhere

New assets must be registered in `pubspec.yaml` under `flutter.assets`.

## Notes

- `AudioService` in `lib/services/audio_service.dart` is a legacy stub — all active audio goes through `MusicService`.
- `google_mobile_ads` is commented out in `pubspec.yaml`; ad-related code in `AchLogic` uses no-op stubs.
- The leaderboard is entirely in-memory and re-seeded on each app launch — there is no backend.
