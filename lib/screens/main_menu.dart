// lib/screens/main_menu.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../texty.dart';
import '../services/settings_service.dart';
import '../services/music_service.dart';

import 'settings_screen.dart';
import 'leaderboard_screen.dart';
import 'achievements_screen.dart';
import 'run_select.dart';

class MainMenu extends StatefulWidget {
  const MainMenu({super.key});
  @override
  State<MainMenu> createState() => _MainMenuState();
}

class _MainMenuState extends State<MainMenu> {
  @override
  void initState() {
    super.initState();

    // Hudba menu (jen pokud je povolena); respektuje zvolený styl (menu_t/menu_m)
    MusicService.I.ensureMenuMusic();

    // Edge-to-edge i po návratu na hlavní menu
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    // Předehřát pozadí
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/images/main_background.gif'), context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: Colors.black, // pro jistotu pod GIFem
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Jediné pozadí přes CELÝ displej (i pod výřezy)
          Positioned.fill(
            child: Stack(
              children: [
                Positioned.fill(
                  child: SizedBox.expand(
                    child: Image.asset(
                      'assets/images/main_background.gif',
                      fit: BoxFit.fill, // ← VYPLNÍ CELÝ DISPLEJ (může lehce deformovat)
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Container(color: Colors.black.withOpacity(0.35)),
                ),
              ],
            ),
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

          // Ikony v rozích
          Positioned(
            top: padding.top + 12,
            left: 12,
            child: _cornerIcon(
              tooltip: T.btnLeaderboard(),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
              ),
            ),
          ),
          Positioned(
            top: padding.top + 12,
            right: 12,
            child: _cornerIcon(
              tooltip: T.btnSettings(),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: padding.bottom + 12,
            child: _cornerIcon(
              tooltip: T.btnAchievements(),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AchievementsScreen()),
              ),
            ),
          ),

          // Verze
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
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          width: 44,
          height: 44,
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
                'assets/images/placeholder.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
