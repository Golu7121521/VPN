import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import '../state/providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _c = TextEditingController();
  Timer? _debounce;
  String _q = ''; // submitted query -> results
  String _typed = ''; // text being typed -> suggestions

  @override
  void dispose() {
    _debounce?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _submit(String v) {
    final q = v.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    ref.read(recentsProvider.notifier).add(q);
    setState(() {
      _q = q;
      _typed = q;
    });
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    setState(() => _q = '');
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _typed = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = _q.isNotEmpty ? _Results(q: _q) : (_typed.isNotEmpty ? _suggestions() : _browse());
    return SafeArea(
      bottom: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Text('Search', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _c,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _submit,
            decoration: InputDecoration(
              hintText: 'Search songs, artists, albums...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _c.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        _c.clear();
                        _q = '';
                        _typed = '';
                      }),
                    ),
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: body),
      ]),
    );
  }

  Widget _suggestions() {
    final v = ref.watch(suggestionsProvider(_typed));
    return v.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => ListTile(
        leading: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
        title: Text(_typed),
        onTap: () => _submit(_typed),
      ),
      data: (list) => ListView(padding: const EdgeInsets.only(bottom: 130), children: [
        for (final s in list)
          ListTile(
            leading: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
            title: Text(s),
            trailing: IconButton(
              tooltip: 'Use suggestion',
              icon: const Icon(Icons.north_west_rounded, color: AppColors.textSecondary, size: 20),
              onPressed: () {
                _c.value = TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
                _onChanged(s);
              },
            ),
            onTap: () {
              _c.text = s;
              _submit(s);
            },
          ),
      ]),
    );
  }

  Widget _browse() {
    final recents = ref.watch(recentsProvider);
    if (recents.isEmpty) {
      return const EmptyState(
        icon: Icons.search_rounded,
        title: 'Search Roxify',
        message: 'Find songs, artists, albums, playlists and podcasts.',
      );
    }
    return ListView(padding: const EdgeInsets.only(bottom: 130), children: [
      SectionHeader('Recent Searches', action: 'Clear All', onAction: ref.read(recentsProvider.notifier).clear),
      for (final r in recents)
        ListTile(
          leading: const Icon(Icons.history_rounded, color: AppColors.textSecondary),
          title: Text(r),
          trailing: IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
            onPressed: () => ref.read(recentsProvider.notifier).remove(r),
          ),
          onTap: () {
            _c.text = r;
            _submit(r);
          },
        ),
    ]);
  }
}

/// Tabs: All, Songs, Videos, Albums, Artists, Playlists, Podcasts. Each tab loads its own real data.
class _Results extends StatelessWidget {
  const _Results({required this.q});
  final String q;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Column(children: [
        const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppColors.primary,
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.textSecondary,
          dividerColor: Colors.transparent,
          tabs: [
            Tab(text: 'All'), Tab(text: 'Songs'), Tab(text: 'Videos'), Tab(text: 'Albums'),
            Tab(text: 'Artists'), Tab(text: 'Playlists'), Tab(text: 'Podcasts'),
          ],
        ),
        Expanded(
          child: TabBarView(children: [
            _AllTab(q: q),
            _SongsTab(k: (q: q, f: 'music_songs')),
            _SongsTab(k: (q: q, f: 'music_videos')),
            _PlaylistsTab(k: (q: q, f: 'music_albums'), kind: 'albums'),
            _ArtistsTab(q: q),
            _PlaylistsTab(k: (q: q, f: 'music_playlists'), kind: 'playlists'),
            _PlaylistsTab(k: (q: '$q podcast', f: 'playlists'), kind: 'podcasts'),
          ]),
        ),
      ]),
    );
  }
}

Widget _empty(String what) =>
    EmptyState(icon: Icons.search_off_rounded, title: 'No $what found', message: 'Try a different search.');

Widget _songTiles(WidgetRef ref, List<Song> l, {int? max}) {
  final ctl = ref.read(playerProvider.notifier);
  final n = max == null || l.length < max ? l.length : max;
  return Column(children: [for (var i = 0; i < n; i++) SongTile(song: l[i], onTap: () => ctl.playQueue(l, i))]);
}

Widget _playlistTile(BuildContext context, Playlist p, {String kind = 'playlist'}) => ListTile(
      leading: Artwork(p.cover, size: 56, radius: 10),
      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(p.description, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textSecondary)),
      onTap: () => openCollection(context, p, kind: kind),
    );

Widget _artistTile(BuildContext context, Artist a) => ListTile(
      leading: ArtistImage(a.name, fallback: a.image, size: 56),
      title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: const Text('Artist', style: TextStyle(color: AppColors.textSecondary)),
      onTap: () => context.push('/artist/${Uri.encodeComponent(a.id)}'),
    );

class _SongsTab extends ConsumerWidget {
  const _SongsTab({required this.k});
  final QueryFilter k;
  @override
  Widget build(BuildContext context, WidgetRef ref) => AsyncView<List<Song>>(
        value: ref.watch(songsFilterProvider(k)),
        onRetry: () => ref.invalidate(songsFilterProvider(k)),
        builder: (l) => l.isEmpty
            ? _empty('results')
            : ListView(padding: const EdgeInsets.only(bottom: 130), children: [_songTiles(ref, l)]),
      );
}

class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab({required this.k, required this.kind});
  final QueryFilter k;
  final String kind;
  @override
  Widget build(BuildContext context, WidgetRef ref) => AsyncView<List<Playlist>>(
        value: ref.watch(playlistsFilterProvider(k)),
        onRetry: () => ref.invalidate(playlistsFilterProvider(k)),
        builder: (l) => l.isEmpty
            ? _empty(kind)
            : ListView(padding: const EdgeInsets.only(bottom: 130), children: [for (final p in l) _playlistTile(context, p, kind: kind == 'albums' ? 'album' : (kind == 'podcasts' ? 'podcast' : 'playlist'))]),
      );
}

class _ArtistsTab extends ConsumerWidget {
  const _ArtistsTab({required this.q});
  final String q;
  @override
  Widget build(BuildContext context, WidgetRef ref) => AsyncView<List<Artist>>(
        value: ref.watch(artistsSearchProvider(q)),
        onRetry: () => ref.invalidate(artistsSearchProvider(q)),
        builder: (l) => l.isEmpty
            ? _empty('artists')
            : ListView(padding: const EdgeInsets.only(bottom: 130), children: [for (final a in l) _artistTile(context, a)]),
      );
}

class _AllTab extends ConsumerWidget {
  const _AllTab({required this.q});
  final String q;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(songsFilterProvider((q: q, f: 'music_songs')));
    final artists = ref.watch(artistsSearchProvider(q));
    final albums = ref.watch(playlistsFilterProvider((q: q, f: 'music_albums')));
    final lists = ref.watch(playlistsFilterProvider((q: q, f: 'music_playlists')));
    if (songs.isLoading && !songs.hasValue) return const LoadingState();
    if (songs.hasError) return ErrorState(onRetry: () => ref.invalidate(songsFilterProvider((q: q, f: 'music_songs'))));
    final w = 130.0;
    return ListView(padding: const EdgeInsets.only(bottom: 130), children: [
      if ((songs.valueOrNull ?? []).isNotEmpty) ...[
        const SectionHeader('Songs'),
        _songTiles(ref, songs.requireValue, max: 5),
      ],
      if ((artists.valueOrNull ?? []).isNotEmpty) ...[
        const SectionHeader('Artists'),
        HList(
          height: 120 + 44,
          count: artists.requireValue.length.clamp(0, 8),
          itemBuilder: (_, i) {
            final a = artists.requireValue[i];
            return PosterCard(
              imageUrl: a.image,
              image: ArtistImage(a.name, fallback: a.image, size: 110),
              title: a.name,
              subtitle: 'Artist',
              width: 110,
              circle: true,
              onTap: () => context.push('/artist/${Uri.encodeComponent(a.id)}'),
            );
          },
        ),
      ],
      if ((albums.valueOrNull ?? []).isNotEmpty) ...[
        const SectionHeader('Albums'),
        HList(
          height: w + 58,
          count: albums.requireValue.length.clamp(0, 8),
          itemBuilder: (_, i) => PosterCard(
            imageUrl: albums.requireValue[i].cover,
            title: albums.requireValue[i].name,
            subtitle: albums.requireValue[i].description,
            width: w,
            onTap: () => openCollection(context, albums.requireValue[i], kind: 'album'),
          ),
        ),
      ],
      if ((lists.valueOrNull ?? []).isNotEmpty) ...[
        const SectionHeader('Playlists'),
        for (final p in lists.requireValue.take(4)) _playlistTile(context, p),
      ],
    ]);
  }
}
