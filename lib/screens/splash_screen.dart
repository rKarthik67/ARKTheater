import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../core/theme.dart';

/// First screen shown on cold start - an animated reveal of the ARK Theatre
/// logo (fade-in, scale-up, then a diagonal light sweep) with a short chime,
/// then hands off to [next] (the app's real home/root shell).
///
/// This is a Dart-level splash, distinct from Android's native
/// launch_background.xml (which just needs to not flash white behind it
/// while the Flutter engine itself is still starting up - see
/// android/app/src/main/res/drawable/launch_background.xml).
///
/// Reuses media_kit's Player for the chime instead of adding a new audio
/// plugin - media_kit's native libmpv backend is already bundled for every
/// platform this app ships to (DesktopPlayerScreen depends on the same
/// native libs), so this adds zero new native dependencies/Gradle downloads.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.next});

  /// The screen to hand off to once the splash finishes (or is skipped).
  final Widget next;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  late final Animation<double> _sweep;

  Player? _chimePlayer;
  bool _navigated = false;

  static const _holdAfterAnimation = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

    // Logo scales in with a slight overshoot ("pop"), fading in over the
    // first third, then a light sweep plays across it once it's settled.
    _scale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack)),
    );
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.35, curve: Curves.easeIn)),
    );
    _sweep = Tween<double>(begin: -1.4, end: 1.8).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.4, 0.95, curve: Curves.easeInOut)),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(_holdAfterAnimation, _finish);
      }
    });

    unawaited(_playChime());
    _controller.forward();
  }

  Future<void> _playChime() async {
    try {
      final data = await rootBundle.load('assets/audio/splash_chime.wav');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ark_splash_chime.wav');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      final player = Player();
      _chimePlayer = player;
      await player.open(Media(file.path));
      await player.play();
    } catch (_) {
      // The animation never depends on sound succeeding - a missing/blocked
      // audio backend just means a silent (still fully animated) splash.
    }
  }

  void _finish() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => widget.next));
  }

  @override
  void dispose() {
    _controller.dispose();
    _chimePlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Tap anywhere to skip straight to Home - nobody should ever feel
      // stuck waiting on an animation (or a sound backend that hung).
      onTap: _finish,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _fade.value,
                child: Transform.scale(
                  scale: _scale.value,
                  child: ShaderMask(
                    blendMode: BlendMode.srcATop,
                    shaderCallback: (bounds) {
                      final pos = _sweep.value;
                      return LinearGradient(
                        begin: Alignment(-1 + pos, -1),
                        end: Alignment(pos, 1),
                        colors: const [Colors.transparent, Colors.white70, Colors.transparent],
                        stops: const [0.35, 0.5, 0.65],
                      ).createShader(bounds);
                    },
                    child: child,
                  ),
                ),
              );
            },
            child: Image.asset('assets/images/logo_mark.png', width: 260, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
