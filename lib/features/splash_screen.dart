import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../state/ads.dart';
import '../state/providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 2600), () async {
      // Full-screen skippable Start.io ad right after the splash; continues when it is closed
      // (or straight away if no ad is ready / the user is in an ad-free period).
      await AdsController.instance.showStartupAd();
      if (mounted) context.go(ref.read(tasteProvider).onboarded ? '/home' : '/onboarding');
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E1237), AppColors.background],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: const AppLogo(size: 120),
            ),
            const SizedBox(height: 8),
            const GlowText('Roxify', fontSize: 38, letterSpacing: 6),
            const SizedBox(height: 8),
            const Text('Music for a better you', style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
            const SizedBox(height: 48),
            AnimatedBuilder(
              animation: _c,
              builder: (_, __) => SizedBox(
                height: 60,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 22; i++)
                      Container(
                        width: 4,
                        height: 8 + 44 * math.sin(_c.value * math.pi * 2 + i * 0.55).abs(),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i.isEven ? AppColors.primary : AppColors.secondary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
