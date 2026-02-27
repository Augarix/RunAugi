// lib/screens/achievements_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../texty.dart';
import '../models/lang.dart';             // pro T.lang == Lang.cz (používá se nepřímo)
import '../achievements/ach_logic.dart';
import '../services/settings_service.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  @override
  void initState() {
    super.initState();

    // Edge-to-edge a světlé ikony
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    // Předehřát pozadí (menší bliknutí)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/images/main_background.gif'), context);
    });

    // Reakce na změnu jazyka / nastavení
    SettingsService.I.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {}); // překreslí AppBar title & texty
  }

  @override
  void dispose() {
    SettingsService.I.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // pro jistotu sjednotíme T.lang i při přímém vstupu na obrazovku
    T.lang = SettingsService.I.lang;

    final ids = AchLogic.I.visibleToday();

    return Scaffold(
      backgroundColor: Colors.black,            // stejné jako v MainMenu (pod GIFem)
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: Text(T.achievementsTitle(), style: const TextStyle(fontFamily: 'Augarix')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        automaticallyImplyLeading: false,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),
      body: Stack(
        children: [
          // ✅ ÚPLNĚ STEJNÝ BACKGROUND BLOK JAKO V MAIN MENU
          Positioned.fill(
            child: Stack(
              children: [
                Positioned.fill(
                  child: SizedBox.expand(
                    child: Image.asset(
                      'assets/images/main_background.gif',
                      fit: BoxFit.fill, // vyplní celý displej (může mírně deformovat)
                      // Pokud chceš bez deformace, přepni na: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Container(color: Colors.black.withOpacity(0.35)),
                ),
              ],
            ),
          ),

          // Obsah
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Ovládací tlačítka
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            await AchLogic.I.unlockTwoExtraNoAds();
                            setState(() {});
                          },
                          child: Text(T.adExtra()),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () async {
                            if (ids.isNotEmpty) {
                              await AchLogic.I.restartOneNoAds(ids.first);
                              setState(() {});
                            }
                          },
                          child: Text(T.restartOne()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Seznam achievementů
                    SizedBox(
                      height: 420,
                      child: ListView.separated(
                        itemCount: ids.length,
                        separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white12, height: 1),
                        itemBuilder: (_, i) {
                          final id = ids[i];
                          final def = AchLogic.I.defs[id]!;
                          final p = AchLogic.I.progress[id]!;
                          final name = (T.lang == Lang.cz) ? def.nameCZ : def.nameEN;
                          final desc = (T.lang == Lang.cz) ? def.descCZ : def.descEN;
                          return ListTile(
                            title: Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Augarix',
                              ),
                            ),
                            subtitle: Text(
                              desc,
                              style: const TextStyle(color: Colors.white70),
                            ),
                            trailing: Text(
                              '${p.value}/${def.target}',
                              style: TextStyle(
                                color: p.done ? Colors.greenAccent : Colors.white70,
                                fontFamily: 'Augarix',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
