import 'dart:math' as math;
import 'package:flutter/material.dart';

enum ParallaxLayerMode {
  scroll,
  oscillate,
}

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

  const ParallaxLayerConfig({
    required this.asset,
    required this.duration,
    required this.mode,
    this.amplitude = 12.0,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.repeat = ImageRepeat.noRepeat,
    this.filterQuality = FilterQuality.none,
    this.gaplessPlayback = true,
  });

  const ParallaxLayerConfig.scroll({
    required this.asset,
    required this.duration,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.centerLeft,
    this.repeat = ImageRepeat.repeatX,
    this.filterQuality = FilterQuality.none,
    this.gaplessPlayback = true,
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
  }) : mode = ParallaxLayerMode.oscillate;
}

class ParallaxBackground extends StatefulWidget {
  final String backgroundAsset;
  final BoxFit backgroundFit;
  final List<ParallaxLayerConfig> layers;
  final Color? overlayColor;
  final double overlayOpacity;

  const ParallaxBackground({
    super.key,
    required this.backgroundAsset,
    required this.layers,
    this.backgroundFit = BoxFit.cover,
    this.overlayColor,
    this.overlayOpacity = 0.0,
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

    _controllers = widget.layers
        .map(
          (layer) => AnimationController(
        vsync: this,
        duration: layer.duration,
      )..repeat(),
    )
        .toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = context;

      precacheImage(AssetImage(widget.backgroundAsset), ctx);
      for (final layer in widget.layers) {
        precacheImage(AssetImage(layer.asset), ctx);
      }
    });
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
        Image.asset(
          widget.backgroundAsset,
          fit: widget.backgroundFit,
          filterQuality: FilterQuality.none,
        ),

        for (int i = 0; i < widget.layers.length; i++)
          _AnimatedParallaxLayer(
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

class _AnimatedParallaxLayer extends StatelessWidget {
  final ParallaxLayerConfig config;
  final AnimationController controller;

  const _AnimatedParallaxLayer({
    required this.config,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    switch (config.mode) {
      case ParallaxLayerMode.scroll:
        return _RepeatScrollLayer(
          asset: config.asset,
          controller: controller,
          fit: config.fit,
          alignment: config.alignment,
          repeat: config.repeat,
          filterQuality: config.filterQuality,
          gaplessPlayback: config.gaplessPlayback,
        );

      case ParallaxLayerMode.oscillate:
        return _OscillatingLayer(
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

class _RepeatScrollLayer extends StatelessWidget {
  final String asset;
  final AnimationController controller;
  final BoxFit fit;
  final Alignment alignment;
  final ImageRepeat repeat;
  final FilterQuality filterQuality;
  final bool gaplessPlayback;

  const _RepeatScrollLayer({
    required this.asset,
    required this.controller,
    required this.fit,
    required this.alignment,
    required this.repeat,
    required this.filterQuality,
    required this.gaplessPlayback,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;

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
                    child: Image.asset(
                      asset,
                      fit: fit,
                      alignment: alignment,
                      repeat: repeat,
                      gaplessPlayback: gaplessPlayback,
                      filterQuality: filterQuality,
                    ),
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

class _OscillatingLayer extends StatelessWidget {
  final String asset;
  final AnimationController controller;
  final double amplitude;
  final BoxFit fit;
  final Alignment alignment;
  final ImageRepeat repeat;
  final FilterQuality filterQuality;
  final bool gaplessPlayback;

  const _OscillatingLayer({
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