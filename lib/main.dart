import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'texty.dart';
import 'screens/main_menu.dart';
import 'services/settings_service.dart';
import 'services/music_service.dart';

const bool SAFE_BOOT = false;

void main() {
  runZonedGuarded(() async {
    final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
    // Zachovej splash dokud app není připravena
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

    PaintingBinding.instance.imageCache.maximumSizeBytes = 256 << 20;
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

    await SettingsService.I.load();

    await MusicService.I.setEnabled(SettingsService.I.musicOn);
    await Future.delayed(const Duration(milliseconds: 200));
    if (SettingsService.I.musicOn) {
      await MusicService.I.ensureMenuMusic();
    }

    // Zobraz splash minimálně 3 sekundy
    await Future.delayed(const Duration(seconds: 3));
    FlutterNativeSplash.remove();

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
        T.lang = SettingsService.I.lang;
        return const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: MainMenu(),
        );
      },
    );
  }
}