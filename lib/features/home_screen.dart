import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import '../state/providers.dart';

const _moods = ['Podcasts', 'Romance', 'Relax', 'Feel good', 'Party', 'Energise', 'Sad', 'Work out', 'Sleep', 'Focus'];

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _mood;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: CustomScrollView(slivers: [
        // App name on the left, search on the right; hides while scrolling down.
        SliverAppBar(
          floating: true,
          snap: true,
          automaticallyImplyLeading: false,
          centerTitle: false,
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 16,
          title: const Text(
            'MUSIFY',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 3, color: AppColors.primary),
          ),
          actions: [
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search_rounded, size: 28),
              onPressed: () => context.go('/search'),
            ),
            const SizedBox(width: 4),
          ],
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: _moods.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ChoiceChip(
                label: Text(_moods[i]),
                selected: _mood == _moods[i],
                showCheckmark: false,
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surfaceVariant,
                side: BorderSide.none,
                shape: const StadiumBorder(),
                onSelected: (v) => setState(() => _mood = v ? _moods[i] : null),
              ),
            ),
          ),
        ),
        if (_mood == null) const _DefaultFeed() else _MoodFeed(mood: _mood!),
      ]),
    );
  }
}

double _cardWidth(BuildContext c) => (MediaQuery.sizeOf(c).width * 0.4).clamp(130.0, 200.0).toDouble();

Widget _songRow(WidgetRef ref, List<Song> list, double width) {
  final ctl = ref.read(playerProvider.notifier);
  return HList(
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
}

Widget _playlistRow(BuildContext context, List<Playlist> list, double width) => HList(
      height: width + 58,
      count: list.length,
      itemBuilder: (_, i) => PosterCard(
        imageUrl: list[i].cover,
        title: list[i].name,
        subtitle: list[i].description,
        width: width,
        onTap: () => openCollection(context, list[i]),
      ),
    );

Widget _rows(BuildContext context, WidgetRef ref, List<FeedRow> rows) {
  final w = _cardWidth(context);
  return Column(children: [
    for (final r in rows) ...[
      SectionHeader(r.title),
      if (r.songs.isNotEmpty) _songRow(ref, r.songs, w),
      if (r.playlists.isNotEmpty) _playlistRow(context, r.playlists, w),
    ],
  ]);
}

const _loadingBox = SizedBox(height: 160, child: LoadingState());

class _DefaultFeed extends ConsumerWidget {
  const _DefaultFeed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quick = ref.watch(quickPicksProvider);
    final rows = ref.watch(feedRowsProvider);
    final hist = ref.watch(playerProvider.select((s) => s.history));
    final w = _cardWidth(context);
    final top = ref.watch(topKeyProvider).split('|').where((e) => e.isNotEmpty).toList();

    void retry() {
      ref.invalidate(songsQueryProvider);
      ref.invalidate(trendingProvider);
      ref.invalidate(quickPicksProvider);
      ref.invalidate(feedRowsProvider);
    }

    return SliverList(
      delegate: SliverChildListDelegate([
        const SectionHeader('Pick Quickly'),
        quick.when(
          data: (l) => l.isEmpty ? ErrorState(onRetry: retry) : _QuickPicks(songs: l),
          loading: () => _loadingBox,
          error: (_, __) => ErrorState(onRetry: retry),
        ),
        if (hist.isNotEmpty) ...[
          const SectionHeader('Listen again'),
          _songRow(ref, hist, w * .8),
        ],
        if (top.isNotEmpty) ...[
          const SectionHeader('Your artists'),
          HList(
            height: w * .7 + 50,
            count: top.length,
            itemBuilder: (_, i) => PosterCard(
              imageUrl: '',
              image: ArtistImage(top[i], size: w * .7),
              title: top[i],
              subtitle: 'Artist',
              width: w * .7,
              circle: true,
              onTap: () => context.push('/artist/${Uri.encodeComponent(top[i])}'),
            ),
          ),
        ],
        rows.when(
          data: (r) => _rows(context, ref, r),
          loading: () => _loadingBox,
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 130),
      ]),
    );
  }
}

class _MoodFeed extends ConsumerWidget {
  const _MoodFeed({required this.mood});
  final String mood;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(moodFeedProvider(mood));
    return SliverList(
      delegate: SliverChildListDelegate([
        feed.when(
          data: (rows) => rows.isEmpty
              ? const SizedBox(
                  height: 300,
                  child: EmptyState(icon: Icons.music_off_rounded, title: 'Nothing here yet', message: 'Try another mood.'),
                )
              : _rows(context, ref, rows),
          loading: () => const SizedBox(height: 300, child: LoadingState()),
          error: (_, __) => SizedBox(height: 300, child: ErrorState(onRetry: () => ref.invalidate(moodFeedProvider(mood)))),
        ),
        const SizedBox(height: 130),
      ]),
    );
  }
}

/// YouTube Music style: columns of 4 songs, swipe sideways for more.
class _QuickPicks extends ConsumerStatefulWidget {
  const _QuickPicks({required this.songs});
  final List<Song> songs;
  @override
  ConsumerState<_QuickPicks> createState() => _QuickPicksState();
}

class _QuickPicksState extends ConsumerState<_QuickPicks> {
  final _pc = PageController(viewportFraction: .92);

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctl = ref.read(playerProvider.notifier);
    final songs = widget.songs;
    final pages = (songs.length / 4).ceil();
    return SizedBox(
      height: 4 * 72.0 + 8,
      child: PageView.builder(
        controller: _pc,
        padEnds: false,
        itemCount: pages,
        itemBuilder: (_, p) => Column(children: [
          for (var i = p * 4; i < p * 4 + 4 && i < songs.length; i++)
            SongTile(song: songs[i], onTap: () => ctl.playQueue(songs, i)),
        ]),
      ),
    );
  }
}
