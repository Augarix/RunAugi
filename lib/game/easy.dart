import 'package:flutter/material.dart';
import 'game_base.dart';

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
    reactionTimeSec: 1.2, // nejvíc času – nejjednodušší
  );

  @override
  State<EasyRun> createState() => _EasyRunState();
}

class _EasyRunState extends GameBaseState<EasyRun> {}