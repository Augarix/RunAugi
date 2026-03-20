import 'package:flutter/material.dart';
import 'game_base.dart';

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
    reactionTimeSec: 0.5, // poloviční mezery oproti EASY
  );

  @override
  State<MediumRun> createState() => _MediumRunState();
}

class _MediumRunState extends GameBaseState<MediumRun> {}