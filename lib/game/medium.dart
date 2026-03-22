import 'package:flutter/material.dart';
import 'game_base.dart';
import '../widgets/parallax_bg.dart';

class MediumRun extends GameBase {
  const MediumRun({super.key})
      : super(
    modeName: 'MEDIUM',
    minIntro: const Duration(seconds: 3),
    length: const Duration(minutes: 5),
    milesOnFinish: 5,
    checkpointFreq: const Duration(seconds: 30),
    speedPercent: 110,
    spritePrefix: 'MT',
    reactionTimeSec: 0.5,
    backgroundBuilder: _buildBackground,
  );

  static Widget _buildBackground(BuildContext context) {
    // GamePlayingScope.of() vrátí true jakmile runner se rozeběhne
    final playing = GamePlayingScope.of(context);
    return ParallaxBackground(
      backgroundAsset: 'assets/images/MT_bg1.png',
      playing: playing,
      layers: const [
        ParallaxLayerConfig.scroll(
          asset: 'assets/images/MT_bg2.png',
          duration: Duration(seconds: 25),
        ),
        ParallaxLayerConfig.scroll(
          asset: 'assets/images/MT_bg3.png',
          duration: Duration(seconds: 10),
          topFraction: 0.35,
        ),
      ],
    );
  }

  @override
  State<MediumRun> createState() => _MediumRunState();
}

class _MediumRunState extends GameBaseState<MediumRun> {}