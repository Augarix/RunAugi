import 'package:flutter/material.dart';

/// Parallax z 3 vrstev (JJ2 styl).
/// Dočasně FORCEnutý PNG fallback kvůli chybě multi_frame_codec na emu (Android 14).
class ParallaxBackground extends StatefulWidget {
  const ParallaxBackground({super.key});

  @override
  State<ParallaxBackground> createState() => _ParallaxBackgroundState();
}

class _ParallaxBackgroundState extends State<ParallaxBackground>
    with TickerProviderStateMixin {
  // ⬇⬇ Přepnout na false, až bude GIF dekodér spolehlivý na cílovém HW.
  static const bool _preferPngFallback = true;

  late final AnimationController _ctrlFast; // 100 %
  late final AnimationController _ctrlMid;  // 66 %
  late final AnimationController _ctrlSlow; // 33 %

  @override
  void initState() {
    super.initState();

    _ctrlFast = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
    _ctrlMid  = AnimationController(vsync: this, duration: const Duration(seconds: 30))..repeat();
    _ctrlSlow = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();

    // Předehřátí assetů
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = context;
      for (final a in const [
        // PNG fallbacky
        'assets/images/pozad1.png',
        'assets/images/pozad2.png',
        'assets/images/pozad3.png',
        // GIFy (pro budoucí zapnutí)
        'assets/images/pozad1.gif',
        'assets/images/pozad2.gif',
        'assets/images/pozad3.gif',
      ]) {
        // ignore: unawaited_futures
        precacheImage(AssetImage(a), ctx);
      }
    });
  }

  @override
  void dispose() {
    _ctrlFast.dispose();
    _ctrlMid.dispose();
    _ctrlSlow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _RepeatScrollLayer(
          // nejvzdálenější – 33 %
          assetPrimary: _preferPngFallback ? 'assets/images/pozad3.png' : 'assets/images/pozad3.gif',
          controller: _ctrlSlow,
        ),
        _RepeatScrollLayer(
          // střed – 66 %
          assetPrimary: _preferPngFallback ? 'assets/images/pozad2.png' : 'assets/images/pozad2.gif',
          controller: _ctrlMid,
        ),
        _RepeatScrollLayer(
          // popředí – 100 %
          assetPrimary: _preferPngFallback ? 'assets/images/pozad1.png' : 'assets/images/pozad1.gif',
          controller: _ctrlFast,
        ),
      ],
    );
  }
}

/// Jeden layer: textura se dlaždicuje horizontálně a viewport se plynule posouvá.
class _RepeatScrollLayer extends StatelessWidget {
  final String assetPrimary;           // PNG (aktuálně) nebo GIF (později)
  final AnimationController controller;

  const _RepeatScrollLayer({
    required this.assetPrimary,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;

        Image buildImage(String asset) => Image.asset(
          asset,
          fit: BoxFit.cover,
          alignment: Alignment.centerLeft,
          repeat: ImageRepeat.repeatX,
          gaplessPlayback: true,
          filterQuality: FilterQuality.none,
        );

        return RepaintBoundary(
          child: AnimatedBuilder(
            animation: controller,
            builder: (_, __) {
              final dx = -((controller.value * w) % w);
              return ClipRect(
                child: Transform.translate(
                  offset: Offset(dx, 0),
                  child: SizedBox(
                    width: w * 2,
                    height: h,
                    child: buildImage(assetPrimary),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
