import 'package:flutter/material.dart';
import 'game_base.dart';

class HardRun extends GameBase {
  const HardRun({super.key})
      : super(
    modeName: 'HARD',
    minIntro: const Duration(seconds: 4),
    length: const Duration(minutes: 5),
    milesOnFinish: 25,
    checkpointFreq: const Duration(seconds: 40),
    speedPercent: 120,
    spritePrefix: 'CT',
    reactionTimeSec: 0.5, // nejméně času – nejtěžší
  );

  @override
  State<HardRun> createState() => _HardRunState();
}

class _HardRunState extends GameBaseState<HardRun> {}