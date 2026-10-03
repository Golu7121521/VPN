import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/detail_screens.dart';
import '../features/home_screen.dart';
import '../features/library_screen.dart';
import '../features/player_screens.dart';
import '../features/premium_screen.dart';
import '../features/profile_screens.dart';
import '../features/search_screen.dart';
import '../features/splash_screen.dart';
import '../state/providers.dart';
import 'widgets.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    ShellRoute(
      builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
        GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
        GoRoute(path: '/library', builder: (_, __) => const LibraryScreen()),
        GoRoute(path: '/premium', builder: (_, __) => const PremiumScreen()),
        GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(path: '/history', builder: (_, __) => const HistoryScreen()),
        GoRoute(path: '/downloads', builder: (_, __) => const DownloadsScreen()),
        GoRoute(
          path: '/playlist/:id',
          builder: (_, s) => CollectionScreen(kind: 'playlist', id: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/album/:id',
          builder: (_, s) => CollectionScreen(kind: 'album', id: s.pathParameters['id']!),
        ),
        GoRoute(path: '/artist/:id', builder: (_, s) => ArtistScreen(id: s.pathParameters['id']!)),
      ],
    ),
    GoRoute(
      path: '/player',
      pageBuilder: (_, s) => CustomTransitionPage<void>(
        key: s.pageKey,
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

  static const _tabs = ['/home', '/search', '/library', '/premium'];
  static int _last = 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = _tabs.indexWhere(location.startsWith);
    if (i >= 0) _last = i;
    ref.listen(playerProvider.select((s) => s.error), (_, e) {
      if (e != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e)));
        ref.read(playerProvider.notifier).clearError();
      }
    });
    return Scaffold(
      body: child,
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        const MiniPlayer(),
        NavigationBar(
          selectedIndex: _last,
          onDestinationSelected: (i) => context.go(_tabs[i]),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Search'),
            NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music_rounded), label: 'Library'),
            NavigationDestination(icon: Icon(Icons.workspace_premium_outlined), selectedIcon: Icon(Icons.workspace_premium_rounded), label: 'Premium'),
          ],
        ),
      ]),
    );
  }
}
