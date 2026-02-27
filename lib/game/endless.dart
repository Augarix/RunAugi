import 'package:flutter/material.dart';
import 'game_base.dart';

class EndlessRun extends GameBase {
  const EndlessRun({super.key})
      : super(
    modeName: 'ENDLESS',
    minIntro: const Duration(seconds: 2),
    length: const Duration(days: 3650), // prakticky nekonečné
    milesOnFinish: 0,
    checkpointFreq: const Duration(seconds: 20),
    speedPercent: 110,
  );

  @override
  State<EndlessRun> createState() => _EndlessRunState();
}

class _EndlessRunState extends GameBaseState<EndlessRun> {}
