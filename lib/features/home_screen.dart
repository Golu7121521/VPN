import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import '../state/providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _chip = 0;
  static const _chips = ['All', 'Music', 'Podcasts', 'Live'];

  void _retry() {
    ref.invalidate(songsQueryProvider);
    ref.invalidate(songsProvider);
    ref.invalidate(newReleasesProvider);
    ref.invalidate(recommendedProvider);
    ref.invalidate(artistsProvider);
  }

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good Morning' : (h < 17 ? 'Good Afternoon' : 'Good Evening');
  }

  @override
  Widget build(BuildContext context) {
    final songs = ref.watch(songsProvider);
    final playlists = ref.watch(playlistsProvider);

    final Widget body;
    if (songs.hasError) {
      body = ErrorState(onRetry: _retry);
    } else if (!songs.hasValue || !playlists.hasValue) {
      body = const LoadingState();
    } else if (_chip > 1) {
      body = const EmptyState(
        icon: Icons.podcasts,
        title: 'Coming soon',
        message: 'Podcasts and live shows will appear here.',
      );
    } else {
      body = _Content(
        songs: songs.requireValue,
        fresh: ref.watch(newReleasesProvider),
        rec: ref.watch(recommendedProvider),
        artists: ref.watch(artistsProvider),
        playlists: playlists.requireValue,
      );
    }

    return SafeArea(
      bottom: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_greeting, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const Text("Let's play something you love", style: TextStyle(color: AppColors.textSecondary)),
              ]),
            ),
            IconButton(
              tooltip: 'Notifications',
              icon: const Badge(smallSize: 8, child: Icon(Icons.notifications_none_rounded)),
              onPressed: () => showNotifications(context),
            ),
            Semantics(
              button: true,
              label: 'Profile',
              child: GestureDetector(
                onTap: () => context.push('/profile'),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primary,
                    child: Icon(Icons.person_rounded, color: Colors.white),
                  ),
                ),
              ),
            ),
          ]),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: _chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => ChoiceChip(
              label: Text(_chips[i]),
              selected: _chip == i,
              showCheckmark: false,
              selectedColor: AppColors.primary,
              backgroundColor: AppColors.surfaceVariant,
              side: BorderSide.none,
              shape: const StadiumBorder(),
              onSelected: (_) => setState(() => _chip = i),
            ),
          ),
        ),
        Expanded(child: body),
      ]),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({
    required this.songs,
    required this.fresh,
    required this.rec,
    required this.artists,
    required this.playlists,
  });
  final List<Song> songs;
  final AsyncValue<List<Song>> fresh, rec;
  final AsyncValue<List<Artist>> artists;
  final List<Playlist> playlists;

  Widget _wait<T>(AsyncValue<T> v, Widget Function(T) b) => v.when(
        data: b,
        loading: () => const SizedBox(height: 120, child: LoadingState()),
        error: (_, __) => const SizedBox.shrink(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = (MediaQuery.sizeOf(context).width * 0.4).clamp(130.0, 200.0).toDouble();
    final ctl = ref.read(playerProvider.notifier);
    final trending = songs.take(12).toList();
    final hist = ref.watch(playerProvider.select((s) => s.history));

    Widget songRow(List<Song> list, double width) => HList(
          height: width + 58,
          count: list.length,
          itemBuilder: (_, i) => PosterCard(
            imageUrl: list[i].artwork,
            title: list[i].title,
            subtitle: list[i].artistName,
            width: width,
            onTap: () => ctl.playQueue(list, i),
          ),
        );

    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: _Hero(onPlay: () => ctl.playQueue(trending, 0)),
      ),
      const SectionHeader('Trending Now'),
      songRow(trending, w),
      const SectionHeader('Made For You'),
      HList(
        height: w + 58,
        count: playlists.length,
        itemBuilder: (_, i) => PosterCard(
          imageUrl: playlists[i].cover,
          title: playlists[i].name,
          subtitle: playlists[i].description,
          width: w,
          onTap: () => context.push('/playlist/${playlists[i].id}'),
        ),
      ),
      if (hist.isNotEmpty) ...[
        const SectionHeader('Recently Played'),
        songRow(hist, w * .75),
      ],
      const SectionHeader('Popular Artists'),
      _wait(
        artists,
        (list) => HList(
          height: w * .7 + 50,
          count: list.length,
          itemBuilder: (_, i) => PosterCard(
            imageUrl: list[i].image,
            title: list[i].name,
            subtitle: 'Artist',
            width: w * .7,
            circle: true,
            onTap: () => context.push('/artist/${Uri.encodeComponent(list[i].id)}'),
          ),
        ),
      ),
      const SectionHeader('New Releases'),
      _wait(fresh, (list) => songRow(list, w)),
      const SectionHeader('Recommended For You'),
      _wait(
        rec,
        (list) => Column(children: [
          for (var i = 0; i < list.length && i < 10; i++)
            SongTile(song: list[i], onTap: () => ctl.playQueue(list, i)),
        ]),
      ),
    ]);
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onPlay});
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 170,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(gradient: AppColors.gradient, borderRadius: BorderRadius.circular(24)),
      child: Stack(children: [
        Positioned(
          right: -24,
          top: -8,
          child: Icon(Icons.graphic_eq_rounded, size: 190, color: Colors.white.withAlpha(35)),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Feel\nThe Music', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.1)),
            FilledButton.icon(
              onPressed: onPlay,
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF4C1D95)),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play now'),
            ),
          ]),
        ),
      ]),
    );
  }
}
