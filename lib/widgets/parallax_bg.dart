import 'dart:math' as math;
import 'package:flutter/material.dart';

enum ParallaxLayerMode { scroll, oscillate }

class ParallaxLayerConfig {
  final String asset;
  final Duration duration;
  final ParallaxLayerMode mode;
  final double amplitude;
  final BoxFit fit;
  final Alignment alignment;
  final ImageRepeat repeat;
  final FilterQuality filterQuality;
  final bool gaplessPlayback;
  final double? topFraction;

  /// Násobitel rychlosti posunu (1.0 = normální, 2.0 = dvojnásobná)
  final double speedMultiplier;

  const ParallaxLayerConfig({
    required this.asset,
    required this.duration,
    required this.mode,
    this.amplitude = 12.0,
    this.fit = BoxFit.fill,
    this.alignment = Alignment.bottomLeft,
    this.repeat = ImageRepeat.noRepeat,
    this.filterQuality = FilterQuality.none,
    this.gaplessPlayback = true,
    this.topFraction,
    this.speedMultiplier = 1.0,
  });

  const ParallaxLayerConfig.scroll({
    required this.asset,
    required this.duration,
    this.fit = BoxFit.fill,
    this.alignment = Alignment.bottomLeft,
    this.repeat = ImageRepeat.noRepeat,
    this.filterQuality = FilterQuality.none,
    this.gaplessPlayback = true,
    this.topFraction,
    this.speedMultiplier = 1.0,
  })  : mode = ParallaxLayerMode.scroll,
        amplitude = 0.0;

  const ParallaxLayerConfig.oscillate({
    required this.asset,
    required this.duration,
    this.amplitude = 12.0,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.repeat = ImageRepeat.noRepeat,
    this.filterQuality = FilterQuality.none,
    this.gaplessPlayback = true,
    this.topFraction,
    this.speedMultiplier = 1.0,
  }) : mode = ParallaxLayerMode.oscillate;
}

class ParallaxBackground extends StatefulWidget {
  final String backgroundAsset;
  final BoxFit backgroundFit;
  final Alignment backgroundAlignment;
  final List<ParallaxLayerConfig> layers;
  final Color? overlayColor;
  final double overlayOpacity;
  final bool playing;

  const ParallaxBackground({
    super.key,
    required this.backgroundAsset,
    required this.layers,
    this.backgroundFit = BoxFit.cover,
    this.backgroundAlignment = Alignment.center,
    this.overlayColor,
    this.overlayOpacity = 0.0,
    this.playing = true,
  });

  @override
  State<ParallaxBackground> createState() => _ParallaxBackgroundState();
}

class _ParallaxBackgroundState extends State<ParallaxBackground>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = widget.layers.map((layer) {
      return AnimationController(vsync: this, duration: layer.duration);
    }).toList();

    if (widget.playing) _startAll();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      precacheImage(AssetImage(widget.backgroundAsset), context);
      for (final layer in widget.layers) {
        precacheImage(AssetImage(layer.asset), context);
      }
    });
  }

  @override
  void didUpdateWidget(covariant ParallaxBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing != oldWidget.playing) {
      widget.playing ? _startAll() : _stopAll();
    }
  }

  void _startAll() {
    for (final c in _controllers) {
      if (!c.isAnimating) c.repeat();
    }
  }

  void _stopAll() {
    for (final c in _controllers) {
      c.stop();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Fallback černá → bílá podkladová barva pokud PNG má průhlednost
        const ColoredBox(color: Color(0xFF87CEEB)), // fallback sky blue
        Image.asset(
          widget.backgroundAsset,
          fit: widget.backgroundFit,
          alignment: widget.backgroundAlignment,
          filterQuality: FilterQuality.none,
          gaplessPlayback: true,
        ),
        for (int i = 0; i < widget.layers.length; i++)
          _AnimatedLayer(
            config: widget.layers[i],
            controller: _controllers[i],
          ),
        if (widget.overlayColor != null && widget.overlayOpacity > 0)
          Container(
            color: widget.overlayColor!.withOpacity(widget.overlayOpacity),
          ),
      ],
    );
  }
}

class _AnimatedLayer extends StatelessWidget {
  final ParallaxLayerConfig config;
  final AnimationController controller;

  const _AnimatedLayer({required this.config, required this.controller});

  @override
  Widget build(BuildContext context) {
    switch (config.mode) {
      case ParallaxLayerMode.scroll:
        return _ScrollLayer(
          asset: config.asset,
          controller: controller,
          fit: config.fit,
          alignment: config.alignment,
          filterQuality: config.filterQuality,
          gaplessPlayback: config.gaplessPlayback,
          topFraction: config.topFraction,
          speedMultiplier: config.speedMultiplier,
        );
      case ParallaxLayerMode.oscillate:
        return _OscillateLayer(
          asset: config.asset,
          controller: controller,
          amplitude: config.amplitude,
          fit: config.fit,
          alignment: config.alignment,
          repeat: config.repeat,
          filterQuality: config.filterQuality,
          gaplessPlayback: config.gaplessPlayback,
        );
    }
  }
}

// Dva identické obrázky vedle sebe, posouvají se doleva.
// Když první vyjede, druhý navazuje – bezešvá smyčka.
class _ScrollLayer extends StatelessWidget {
  final String asset;
  final AnimationController controller;
  final BoxFit fit;
  final Alignment alignment;
  final FilterQuality filterQuality;
  final bool gaplessPlayback;
  final double? topFraction;
  final double speedMultiplier;

  const _ScrollLayer({
    required this.asset,
    required this.controller,
    required this.fit,
    required this.alignment,
    required this.filterQuality,
    required this.gaplessPlayback,
    this.topFraction,
    this.speedMultiplier = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      final top = topFraction != null ? h * topFraction! : 0.0;
      final imgH = h - top;

      return RepaintBoundary(
        child: AnimatedBuilder(
          animation: controller,
          builder: (_, __) {
            // Plynulý offset 0 → -w, speedMultiplier mění rychlost
            final dx = -((controller.value * w * speedMultiplier) % w);

            return ClipRect(
              child: Stack(
                children: [
                  Positioned(
                    left: dx,
                    top: top,
                    width: w,
                    height: imgH,
                    child: _img(),
                  ),
                  Positioned(
                    left: dx + w,
                    top: top,
                    width: w,
                    height: imgH,
                    child: _img(),
                  ),
                ],
              ),
            );
          },
        ),
      );
    });
  }

  Widget _img() => Image.asset(
    asset,
    fit: BoxFit.fill,
    alignment: alignment,
    gaplessPlayback: gaplessPlayback,
    filterQuality: filterQuality,
  );
}

class _OscillateLayer extends StatelessWidget {
  final String asset;
  final AnimationController controller;
  final double amplitude;
  final BoxFit fit;
  final Alignment alignment;
  final ImageRepeat repeat;
  final FilterQuality filterQuality;
  final bool gaplessPlayback;

  const _OscillateLayer({
    required this.asset,
    required this.controller,
    required this.amplitude,
    required this.fit,
    required this.alignment,
    required this.repeat,
    required this.filterQuality,
    required this.gaplessPlayback,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, __) {
          final dx = math.sin(controller.value * 2 * math.pi) * amplitude;
          return Transform.translate(
            offset: Offset(dx, 0),
            child: SizedBox.expand(
              child: Image.asset(
                asset,
                fit: fit,
                alignment: alignment,
                repeat: repeat,
                gaplessPlayback: gaplessPlayback,
                filterQuality: filterQuality,
              ),
            ),
          );
        },
      ),
    );
  }
}