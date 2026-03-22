import 'package:flutter/material.dart';
import 'game_base.dart';
import '../widgets/parallax_bg.dart';

class EasyRun extends GameBase {
  const EasyRun({super.key})
      : super(
    modeName: 'EASY',
    minIntro: const Duration(seconds: 2),
    length: const Duration(minutes: 5),
    milesOnFinish: 1,
    checkpointFreq: const Duration(seconds: 20),
    speedPercent: 100,
    spritePrefix: 'HL',
    spriteFolder: 'assets/images/easy/',
    reactionTimeSec: 0.8,
    tileScaleOverride: 5, // větší překážky – přibližně výška runnera
    backgroundBuilder: _buildBackground,
  );

  static Widget _buildBackground(BuildContext context) {
    final playing = GamePlayingScope.of(context);
    return ParallaxBackground(
      backgroundAsset: 'assets/images/easy/HL_bg1.png',
      backgroundAlignment: const Alignment(0, 0.9),
      playing: playing,
      layers: const [
        ParallaxLayerConfig.scroll(
          asset: 'assets/images/easy/HL_bg2.png',
          duration: Duration(seconds: 25),
        ),
        ParallaxLayerConfig.scroll(
          asset: 'assets/images/easy/HL_bg3.png',
          duration: Duration(seconds: 10),
          topFraction: 0.35,
        ),
      ],
    );
  }

  @override
  State<EasyRun> createState() => _EasyRunState();
}

class _EasyRunState extends GameBaseState<EasyRun> {}