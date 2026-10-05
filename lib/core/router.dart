import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/detail_screens.dart';
import '../features/home_screen.dart';
import '../features/downloads_screen.dart';
import '../features/library_screen.dart';
import '../features/onboarding_screen.dart';
import '../features/player_screens.dart';
import '../features/search_screen.dart';
import '../features/splash_screen.dart';
import '../state/providers.dart';
import 'widgets.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
    ShellRoute(
      builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
        GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
        GoRoute(path: '/library', builder: (_, __) => const LibraryScreen()),
        GoRoute(path: '/downloads', builder: (_, __) => const DownloadsScreen()),
        GoRoute(
          path: '/collection',
          builder: (_, s) => RemoteCollectionScreen(
            url: s.uri.queryParameters['u'] ?? '',
            name: s.uri.queryParameters['n'] ?? '',
            cover: s.uri.queryParameters['c'] ?? '',
          ),
        ),
        GoRoute(path: '/playlist/:id', builder: (_, s) => CollectionScreen(id: s.pathParameters['id']!)),
        GoRoute(path: '/artist/:name', builder: (_, s) => ArtistScreen(name: s.pathParameters['name']!)),
      ],
    ),
    GoRoute(
      path: '/player',
      pageBuilder: (_, s) => CustomTransitionPage<void>(
        key: s.pageKey,
        opaque: false,
        child: const NowPlayingScreen(),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ),
    GoRoute(
      path: '/queue',
      builder: (_, s) => QueueScreen(initialTab: s.uri.queryParameters['tab'] == 'lyrics' ? 1 : 0),
    ),
  ],
);

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  static const _tabs = ['/home', '/search', '/library', '/downloads'];
  static int _last = 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = _tabs.indexWhere(location.startsWith);
    if (i >= 0) _last = i;
    ref.listen(playerProvider.select((s) => s.error), (_, e) {
      if (e != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e), duration: const Duration(seconds: 12)));
        ref.read(playerProvider.notifier).clearError();
      }
    });
    // Tapping any song opens the Now Playing screen.
    ref.listen(playerProvider.select((s) => s.openCount), (prev, next) {
      if (next > (prev ?? 0)) context.push('/player');
    });
    return Scaffold(
      extendBody: true,
      body: child,
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        const MiniPlayer(),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x000B0A10), Color(0xF20B0A10)],
            ),
          ),
          child: NavigationBar(
            height: 56,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
            selectedIndex: _last,
            onDestinationSelected: (i) => context.go(_tabs[i]),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Search'),
              NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music_rounded), label: 'Library'),
              NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download_rounded), label: 'Downloads'),
            ],
          ),
        ),
      ]),
    );
  }
}
