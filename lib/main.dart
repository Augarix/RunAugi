import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/painting.dart'; // ⬅️ pro image cache (PaintingBinding)

import 'texty.dart';
import 'screens/main_menu.dart';
import 'services/settings_service.dart';
import 'services/music_service.dart';

const bool SAFE_BOOT = false;

void main() {
  runZonedGuarded(() async {
    // ✅ ensureInitialized i runApp ve stejné zóně
    WidgetsFlutterBinding.ensureInitialized();

    // 💾 zvětšit image cache – pomáhá s animovanými GIFy na emulátoru
    PaintingBinding.instance.imageCache.maximumSizeBytes = 256 << 20; // 256 MB
    PaintingBinding.instance.imageCache.maximumSize = 500;

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    // Nastavení
    await SettingsService.I.load();

    // Hudba – povolit/zakázat audio dle nastavení a případně spustit menu music
    await MusicService.I.setEnabled(SettingsService.I.musicOn);
    await Future.delayed(const Duration(milliseconds: 200)); // krátké „warm-up“
    if (SettingsService.I.musicOn) {
      await MusicService.I.ensureMenuMusic();
    }

    runApp(const RootApp());
  }, (error, stack) {
    // ignore: avoid_print
    print('UNCAUGHT: $error\n$stack');
  });
}

class RootApp extends StatelessWidget {
  const RootApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (SAFE_BOOT) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: Text('SAFE BOOT – app běží'))),
      );
    }
    return const AugiRunApp();
  }
}

class AugiRunApp extends StatelessWidget {
  const AugiRunApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsService.I,
      builder: (_, __) {
        // aby T.* používal aktuální jazyk
        T.lang = SettingsService.I.lang;
        return const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: MainMenu(),
        );
      },
    );
  }
}
