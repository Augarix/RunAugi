import 'package:flutter/material.dart';
import 'game_base.dart';
import '../widgets/parallax_bg.dart';

class EndlessRun extends GameBase {
  const EndlessRun({super.key})
      : super(
    modeName: 'ENDLESS',
    minIntro: const Duration(seconds: 2),
    length: const Duration(days: 3650),
    milesOnFinish: 0,
    checkpointFreq: const Duration(seconds: 20),
    speedPercent: 110,
    spritePrefix: 'EN',
    reactionTimeSec: 0.8,
    spriteFolder: 'assets/images/endless/',
    backgroundBuilder: _buildBackground,
  );

  static Widget _buildBackground(BuildContext context) {
    final playing = GamePlayingScope.of(context);
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
  }

  @override
  State<EndlessRun> createState() => _EndlessRunState();
}

class _EndlessRunState extends GameBaseState<EndlessRun> {}