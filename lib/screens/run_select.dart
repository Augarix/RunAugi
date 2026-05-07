import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../texty.dart';
import '../game/easy.dart';
import '../game/medium.dart';
import '../game/hard.dart';
import '../game/endless_run.dart';

class RunSelectScreen extends StatelessWidget {
  const RunSelectScreen({super.key});

  static const double _easyX = 0.50;
  static const double _easyY = 0.33;

  static const double _mediumX = 0.70;
  static const double _mediumY = 0.80;

  static const double _hardX = 0.17;
  static const double _hardY = 0.88;

  static const double _endlessX = 0.70;
  static const double _endlessY = 0.10;

  static const double _easyFont    = 24;
  static const double _mediumFont  = 24;
  static const double _hardFont    = 24;
  static const double _endlessFont = 24;

  static const List<Shadow> _whiteShadow = [
    Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black87),
    Shadow(offset: Offset(-1, -1), blurRadius: 2, color: Colors.black54),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle.light,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Zpět',
        ),
        title: Text(
          T.selectMode(),
          style: const TextStyle(
            fontFamily: 'Augarix',
            fontSize: 22,
            color: Colors.white,
          ),
        ),
        centerTitle: false,
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;

          return Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/Difficulty-bg 3.png',
                  fit: BoxFit.fill,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.high,
                ),
              ),

              _hotspot(
                w: w, h: h, x: _easyX, y: _easyY,
                label: T.modeEasy(),
                fontSize: _easyFont,
                color: Colors.black,
                onTap: () => _goTo(context, const EasyRun()),
              ),

              _hotspot(
                w: w, h: h, x: _mediumX, y: _mediumY,
                label: T.modeMedium(),
                fontSize: _mediumFont,
                color: Colors.black,
                onTap: () => _goTo(context, const MediumRun()),
              ),

              _hotspot(
                w: w, h: h, x: _hardX, y: _hardY,
                label: T.modeHard(),
                fontSize: _hardFont,
                color: Colors.black,
                onTap: () => _goTo(context, const HardRun()),
              ),

              _hotspot(
                w: w, h: h, x: _endlessX, y: _endlessY,
                label: T.modeEndless(),
                fontSize: _endlessFont,
                color: Colors.white,
                shadows: _whiteShadow,
                onTap: () => _goTo(context, const EndlessRun()),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _goTo(BuildContext context, Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  static Widget _hotspot({
    required double w,
    required double h,
    required double x,
    required double y,
    required String label,
    required double fontSize,
    required VoidCallback onTap,
    Color color = Colors.white,
    List<Shadow>? shadows,
  }) {
    const double minW = 120;
    const double minH = 44;

    return Positioned(
      left: w * x,
      top:  h * y,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: minW, minHeight: minH),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onTap,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Augarix',
                fontSize: fontSize,
                color: color,
                height: 1.0,
                shadows: shadows,
              ),
            ),
          ),
        ),
      ),
    );
  }
}