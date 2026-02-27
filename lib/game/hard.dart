import 'package:flutter/material.dart';
import 'game_base.dart';

// Hard má flip a mirror sekce (řeší game_base)

class HardRun extends GameBase {
  const HardRun({super.key})
      : super(
    modeName: 'HARD',
    minIntro: const Duration(seconds: 4),
    length: const Duration(minutes: 5),
    milesOnFinish: 25,
    checkpointFreq: const Duration(seconds: 40),
    speedPercent: 120,
  );

  @override
  State<HardRun> createState() => _HardRunState();
}

class _HardRunState extends GameBaseState<HardRun> {}
