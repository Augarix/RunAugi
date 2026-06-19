// lib/screens/main_menu.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../texty.dart';
import '../services/settings_service.dart';
import '../services/music_service.dart';
import '../widgets/parallax_bg.dart';

import 'settings_screen.dart';
import 'leaderboard_screen.dart';
import 'achievements_screen.dart';
import 'run_select.dart';

// Konfigurace parallax sad pro každou obtížnost
// Endless používá MT jako placeholder
// Parallax sady pro main menu
// midVerticalOffset: posun střední vrstvy v px
// frontRepeatX: true = opakuj přední vrstvu do šířky (pro CT_3 dlažbu)
// bgAlignmentY: vertikální zarovnání bg vrstvy (-1.0 nahoře, 1.0 dole)
const _parallaxSets = [
  // EASY – HL
  (
  bg: 'assets/images/easy/HL_bg1.png',
  mid: 'assets/images/easy/HL_bg2.png',
  front: 'assets/images/easy/HL_bg3.png',
  frontTopFraction: 0.35,
  midVerticalOffset: 0.0,
  frontRepeatX: false,
  bgAlignmentY: 0.9, // Alignment(0, 0.9) – bg posunut dolů jako v easy.dart
  ),
  // MEDIUM – MT
  (
  bg: 'assets/images/MT_bg1.png',
  mid: 'assets/images/MT_bg2.png',
  front: 'assets/images/MT_bg3.png',
  frontTopFraction: 0.35,
  midVerticalOffset: 0.0,
  frontRepeatX: false,
  bgAlignmentY: 0.0,
  ),
  // HARD – CT (přesně jako hard.dart)
  (
  bg: 'assets/images/hard/CT_1.png',
  mid: 'assets/images/hard/CT_2.png',
  front: 'assets/images/hard/CT_3.png',
  frontTopFraction: 0.87,
  midVerticalOffset: 80.0,
  frontRepeatX: true,
  bgAlignmentY: 0.0,
  ),
];

class MainMenu extends StatefulWidget {
  const MainMenu({super.key});
  @override
  State<MainMenu> createState() => _MainMenuState();
}

class _MainMenuState extends State<MainMenu> {
  // Náhodně vybraná sada parallaxu při každém zobrazení
  late final _set = _parallaxSets[Random().nextInt(_parallaxSets.length)];

  @override
  void initState() {
    super.initState();
    MusicService.I.ensureMenuMusic();
    // Reaguj na změny nastavení (jazyk apod.) → překresli menu s aktuálními T.* texty.
    SettingsService.I.addListener(_onSettingsChanged);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SettingsService.I.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Parallax pozadí – vždy animované (hlavní menu vždy "běží")
          Positioned.fill(
            child: ParallaxBackground(
              backgroundAsset: _set.bg,
              backgroundAlignment: Alignment(0, _set.bgAlignmentY),
              playing: true,
              layers: [
                ParallaxLayerConfig.scroll(
                  asset: _set.mid,
                  duration: const Duration(seconds: 25),
                  verticalOffset: _set.midVerticalOffset,
                ),
                if (_set.front.isNotEmpty)
                  ParallaxLayerConfig.scroll(
                    asset: _set.front,
                    duration: const Duration(seconds: 10),
                    topFraction: _set.frontTopFraction,
                    fit: _set.frontRepeatX ? BoxFit.fitHeight : BoxFit.fill,
                    alignment: _set.frontRepeatX ? Alignment.bottomLeft : Alignment.bottomLeft,
                    repeat: _set.frontRepeatX ? ImageRepeat.repeatX : ImageRepeat.noRepeat,
                  ),
              ],
            ),
          ),

          // Tmavý overlay
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.35)),
          ),

          // Centrální RUN tlačítko
          Center(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RunSelectScreen()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Text(
                    T.btnRun(),
                    style: const TextStyle(
                      fontFamily: 'Augarix',
                      fontSize: 40,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Leaderboard – vlevo nahoře
          Positioned(
            top: padding.top + 12,
            left: 12,
            child: _cornerIcon(
              asset: 'assets/images/icon_leaderboard.png',
              tooltip: T.btnLeaderboard(),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
              ),
            ),
          ),

          // Settings – vpravo nahoře
          Positioned(
            top: padding.top + 12,
            right: 12,
            child: _cornerIcon(
              asset: 'assets/images/icon_settings.png',
              tooltip: T.btnSettings(),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
                // Po návratu z nastavení překresli menu – jazyk se mohl změnit,
                // takže T.btnRun() a další T.* texty potřebují rebuild.
                if (mounted) setState(() {});
              },
            ),
          ),

          // Achievements – vlevo dole
          Positioned(
            left: 12,
            bottom: padding.bottom + 12,
            child: _cornerIcon(
              asset: 'assets/images/icon_achievements.png',
              tooltip: T.btnAchievements(),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AchievementsScreen()),
              ),
            ),
          ),

          // Verze – vpravo dole
          Positioned(
            right: 12,
            bottom: padding.bottom + 12,
            child: Text(
              T.version(SettingsService.I.version),
              style: const TextStyle(
                fontFamily: 'Augarix',
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cornerIcon({
    required String asset,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.black.withOpacity(0.25),
            border: Border.all(color: Colors.white.withOpacity(0.4)),
          ),
          child: Tooltip(
            message: tooltip ?? '',
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Image.asset(
                asset,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.image_not_supported,
                  color: Colors.white54,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}