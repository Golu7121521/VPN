import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/mock_data.dart';
import '../data/models.dart';
import '../state/providers.dart';

class _PlayShuffleRow extends StatelessWidget {
  const _PlayShuffleRow({required this.onPlay, required this.onShuffle});
  final VoidCallback onPlay, onShuffle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: onPlay,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: onShuffle,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
                backgroundColor: AppColors.surfaceVariant,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.shuffle_rounded),
              label: const Text('Shuffle'),
            ),
          ),
        ]),
      );
}

/// Featured playlists (filled by a live search), user playlists and Liked Songs.
class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userPl = ref.watch(userPlaylistsProvider);
    final likes = ref.watch(likesProvider);
    final ctl = ref.read(playerProvider.notifier);

    String title = '', sub = '';
    String? cover;
    var isUser = false;
    AsyncValue<List<Song>> songsV = const AsyncData([]);

    if (id == 'liked') {
      title = 'Liked Songs';
      sub = '${likes.length} songs';
      songsV = AsyncData(likes.songs);
    } else {
      final m = [...userPl, ...featuredPlaylists].where((p) => p.id == id);
      if (m.isNotEmpty) {
        final p = m.first;
        isUser = userPl.any((u) => u.id == id);
        title = p.name;
        cover = p.cover;
        sub = p.description;
        songsV = p.query != null ? ref.watch(songsQueryProvider(p.query!)) : AsyncData(p.songs);
      }
    }
    if (title.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.error_outline, title: 'Not found', message: 'This item no longer exists.'),
      );
    }

    final side = math.min(MediaQuery.sizeOf(context).width * .6, 300.0);
    final list = songsV.valueOrNull ?? <Song>[];
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (isUser)
            PopupMenuButton<String>(
              onSelected: (_) {
                ref.read(userPlaylistsProvider.notifier).remove(id);
                context.pop();
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete playlist'))],
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 130), children: [
        Center(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: AppColors.primary.withAlpha(60), blurRadius: 40)],
            ),
            child: cover == null
                ? Container(
                    width: side,
                    height: side,
                    decoration: BoxDecoration(gradient: AppColors.gradient, borderRadius: BorderRadius.circular(20)),
                    child: const Icon(Icons.favorite_rounded, size: 90),
                  )
                : Artwork(cover, size: side, radius: 20),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Column(children: [
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
          ]),
        ),
        _PlayShuffleRow(
          onPlay: () => ctl.playQueue(list, 0),
          onShuffle: () => ctl.playQueue([...list]..shuffle(), 0),
        ),
        songsV.when(
          loading: () => const SizedBox(height: 200, child: LoadingState()),
          error: (_, __) => SizedBox(
            height: 260,
            child: ErrorState(onRetry: () => ref.invalidate(songsQueryProvider)),
          ),
          data: (l) => l.isEmpty
              ? const SizedBox(
                  height: 220,
                  child: EmptyState(
                    icon: Icons.music_off_rounded,
                    title: 'No songs yet',
                    message: 'Use "Add to playlist" from any song menu.',
                  ),
                )
              : Column(children: [
                  for (var i = 0; i < l.length; i++) SongTile(song: l[i], onTap: () => ctl.playQueue(l, i)),
                ]),
        ),
      ]),
    );
  }
}

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsV = ref.watch(songsQueryProvider(name));
    final others = ref.watch(artistsProvider).valueOrNull ?? [];
    final ctl = ref.read(playerProvider.notifier);
    final w = (MediaQuery.sizeOf(context).width * .38).clamp(120.0, 180.0).toDouble();

    if (songsV.hasError) {
      return Scaffold(appBar: AppBar(), body: ErrorState(onRetry: () => ref.invalidate(songsQueryProvider(name))));
    }
    if (!songsV.hasValue) return Scaffold(appBar: AppBar(), body: const LoadingState());
    final songs = songsV.requireValue;
    final image = songs.isEmpty ? '' : songs.first.artwork;
    final related = others.where((a) => a.name != name).take(8).toList();

    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, children: [
        Stack(children: [
          SizedBox(
            height: 300,
            width: double.infinity,
            child: ArtistImage(name, fallback: image, circle: false, radius: 0),
          ),
          Container(
            height: 300,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, AppColors.background],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          SafeArea(child: Padding(padding: const EdgeInsets.all(4), child: BackButton(onPressed: () => context.pop()))),
          Positioned(
            left: 16,
            right: 16,
            bottom: 8,
            child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
          ),
        ]),
        _PlayShuffleRow(
          onPlay: () => ctl.playQueue(songs, 0),
          onShuffle: () => ctl.playQueue([...songs]..shuffle(), 0),
        ),
        const SectionHeader('Popular'),
        for (var i = 0; i < songs.length; i++) SongTile(song: songs[i], onTap: () => ctl.playQueue(songs, i)),
        if (related.isNotEmpty) ...[
          const SectionHeader('Related Artists'),
          HList(
            height: w * .7 + 50,
            count: related.length,
            itemBuilder: (_, i) => PosterCard(
              imageUrl: related[i].image,
              image: ArtistImage(related[i].name, fallback: related[i].image, size: w * .7),
              title: related[i].name,
              subtitle: 'Artist',
              width: w * .7,
              circle: true,
              onTap: () => context.push('/artist/${Uri.encodeComponent(related[i].id)}'),
            ),
          ),
        ],
        const SizedBox(height: 130),
      ]),
    );
  }
}
