// lib/screens/achievements_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';

import '../texty.dart';
import '../models/lang.dart';
import '../achievements/ach_logic.dart';
import '../services/settings_service.dart';
import '../widgets/parallax_bg.dart';

const _parallaxSets = [
  (
  bg: 'assets/images/easy/HL_bg1.png',
  mid: 'assets/images/easy/HL_bg2.png',
  front: 'assets/images/easy/HL_bg3.png',
  frontTopFraction: 0.35,
  midVerticalOffset: 0.0,
  frontRepeatX: false,
  bgAlignmentY: 0.9,
  ),
  (
  bg: 'assets/images/MT_bg1.png',
  mid: 'assets/images/MT_bg2.png',
  front: 'assets/images/MT_bg3.png',
  frontTopFraction: 0.35,
  midVerticalOffset: 0.0,
  frontRepeatX: false,
  bgAlignmentY: 0.0,
  ),
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

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  late final _set = _parallaxSets[Random().nextInt(_parallaxSets.length)];

  @override
  void initState() {
    super.initState();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    SettingsService.I.addListener(_onSettingsChanged);
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
    T.lang = SettingsService.I.lang;
    final ids = AchLogic.I.visibleToday();

    return Scaffold(
      backgroundColor: Colors.black,
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
          // Parallax pozadí – stejné jako main menu
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
                    alignment: Alignment.bottomLeft,
                    repeat: _set.frontRepeatX ? ImageRepeat.repeatX : ImageRepeat.noRepeat,
                  ),
              ],
            ),
          ),
          // Tmavý overlay – 0.55 pro lepší čitelnost
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.55)),
          ),

          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
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