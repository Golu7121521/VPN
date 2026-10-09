import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import '../state/ads.dart';
import '../state/providers.dart';

const _moods = ['Podcasts', 'Romance', 'Relax', 'Feel good', 'Party', 'Energise', 'Sad', 'Work out', 'Sleep', 'Focus'];

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _mood;

  Future<void> _refresh() async {
    ref.read(refreshProvider.notifier).bump();
    ref.invalidate(songsQueryProvider);
    ref.invalidate(songsFilterProvider);
    ref.invalidate(playlistsFilterProvider);
    ref.invalidate(moodFeedProvider);
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        onRefresh: _refresh,
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
          title: const Row(children: [
            AppLogo(size: 34),
            SizedBox(width: 10),
            Text(
              'ROXYFY',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 3, color: AppColors.primary),
            ),
          ]),
          actions: [
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search_rounded, size: 28),
              onPressed: () => context.go('/search'),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              color: AppColors.surface,
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) {
                if (v == 'ads') showRemoveAdsSheet(context);
                if (v == 'prefs') context.go('/onboarding');
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'ads',
                  child: ValueListenableBuilder<DateTime?>(
                    valueListenable: AdsController.instance.adFreeUntil,
                    builder: (_, __, ___) => Row(children: [
                      const Icon(Icons.block_rounded, size: 20),
                      const SizedBox(width: 12),
                      Text(AdsController.instance.adFree
                          ? 'Remove ads (${AdsController.instance.remaining.inMinutes} min left)'
                          : 'Remove ads'),
                    ]),
                  ),
                ),
                const PopupMenuItem(
                  value: 'prefs',
                  child: Row(children: [
                    Icon(Icons.tune_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Country, languages & artists'),
                  ]),
                ),
              ],
            ),
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
      ),
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

Widget _playlistRow(BuildContext context, List<Playlist> list, double width, String kind) => HList(
      height: width + 58,
      count: list.length,
      itemBuilder: (_, i) => PosterCard(
        imageUrl: list[i].cover,
        title: list[i].name,
        subtitle: list[i].description,
        width: width,
        onTap: () => openCollection(context, list[i], kind: kind),
      ),
    );

Widget _rows(BuildContext context, WidgetRef ref, List<FeedRow> rows) {
  final w = _cardWidth(context);
  return Column(children: [
    for (final r in rows) ...[
      SectionHeader(r.title),
      if (r.songs.isNotEmpty) _songRow(ref, r.songs, w),
      if (r.playlists.isNotEmpty) _playlistRow(context, r.playlists, w, 'podcast'),
    ],
  ]);
}

const _loadingBox = SizedBox(height: 160, child: LoadingState());

class _DefaultFeed extends ConsumerWidget {
  const _DefaultFeed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quick = ref.watch(quickPicksProvider);
    final hist = ref.watch(historyProvider);
    final specs = ref.watch(feedSpecsProvider);
    final w = _cardWidth(context);
    final top = ref.watch(topKeyProvider).split('|').where((e) => e.isNotEmpty).toList();

    void retry() {
      ref.invalidate(songsQueryProvider);
      ref.invalidate(trendingProvider);
      ref.invalidate(quickPicksProvider);
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
          const SectionHeader('Last played'),
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
        for (final s in specs) _LazyRow(spec: s),
        const SizedBox(height: 130),
      ]),
    );
  }
}

/// One feed row; its data is only fetched when it scrolls into view.
class _LazyRow extends ConsumerWidget {
  const _LazyRow({required this.spec});
  final FeedSpec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = _cardWidth(context);
    const loading = SizedBox(height: 120, child: LoadingState());
    if (spec.playlists) {
      return ref.watch(playlistsFilterProvider((q: spec.query, f: 'music_playlists'))).when(
            data: (l) => l.isEmpty
                ? const SizedBox.shrink()
                : Column(children: [SectionHeader(spec.title), _playlistRow(context, l.take(12).toList(), w, 'playlist')]),
            loading: () => Column(children: [SectionHeader(spec.title), loading]),
            error: (_, __) => const SizedBox.shrink(),
          );
    }
    return ref.watch(songsQueryProvider(spec.query)).when(
          data: (l) => l.isEmpty
              ? const SizedBox.shrink()
              : Column(children: [SectionHeader(spec.title), _songRow(ref, l, w)]),
          loading: () => Column(children: [SectionHeader(spec.title), loading]),
          error: (_, __) => const SizedBox.shrink(),
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
