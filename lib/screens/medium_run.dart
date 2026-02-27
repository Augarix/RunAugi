import 'package:flutter/material.dart';
import '../game/game_base.dart';

class MediumRun extends GameBase {
  const MediumRun({super.key})
      : super(
    modeName: 'MEDIUM',
    minIntro: const Duration(seconds: 2),
    length: const Duration(minutes: 2),
    milesOnFinish: 1,
    checkpointFreq: const Duration(seconds: 20),
    speedPercent: 100,
  );

  @override
  State<MediumRun> createState() => GameBaseState<MediumRun>();
}
