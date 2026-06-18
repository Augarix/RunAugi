import 'package:flutter/material.dart';
import 'game_base.dart';
import '../widgets/parallax_bg.dart';

class HardRun extends GameBase {
  const HardRun({super.key})
      : super(
    modeName: 'HARD',
    minIntro: const Duration(seconds: 2),
    length: const Duration(minutes: 5),
    milesOnFinish: 25,
    checkpointFreq: const Duration(seconds: 40),
    speedPercent: 135,
    spritePrefix: 'CT',
    spriteFolder: 'assets/images/hard/',
    reactionTimeSec: 0.40,
    backgroundBuilder: _buildBackground,
  );

  static Widget _buildBackground(BuildContext context) {
    final playing = GamePlayingScope.of(context);
    return ParallaxBackground(
      backgroundAsset: 'assets/images/hard/CT_1.png',
      playing: playing,
      layers: const [
        ParallaxLayerConfig.scroll(
          asset: 'assets/images/hard/CT_2.png',
          duration: Duration(seconds: 25),
          verticalOffset: 90.0, // kladné = dolů, záporné = nahoru
        ),
        ParallaxLayerConfig.scroll(
          asset: 'assets/images/hard/CT_3.png',
          duration: Duration(seconds: 5), // vyrovnáno na rychlost hry 135%
          topFraction: 0.87,
          fit: BoxFit.fitHeight,
          alignment: Alignment.bottomLeft,
          repeat: ImageRepeat.repeatX,
        ),
      ],
    );
  }

  @override
  State<HardRun> createState() => _HardRunState();
}

class _HardRunState extends GameBaseState<HardRun> {}