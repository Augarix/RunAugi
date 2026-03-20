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
    reactionTimeSec: 0.8,
    backgroundBuilder: _buildEasyBackground,
  );

  static Widget _buildEasyBackground(BuildContext context) {
    return const ParallaxBackground(
      backgroundAsset: 'assets/images/easy_BG.png',
      backgroundFit: BoxFit.cover,
      layers: [
        ParallaxLayerConfig.oscillate(
          asset: 'assets/images/easy_BG_layer1.png',
          duration: Duration(seconds: 6),
          amplitude: 12,
          fit: BoxFit.cover,
        ),
      ],
    );
  }

  @override
  State<EasyRun> createState() => _EasyRunState();
}

class _EasyRunState extends GameBaseState<EasyRun> {}