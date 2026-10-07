import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
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

/// Shared layout for Liked Songs, your playlists and YouTube albums / playlists / podcasts.
class _CollectionView extends ConsumerWidget {
  const _CollectionView({
    required this.title,
    required this.sub,
    required this.cover,
    required this.songsV,
    required this.onRetry,
    this.onDelete,
    this.extraActions = const [],
  });
  final List<Widget> extraActions;
  final String title, sub;
  final String? cover;
  final AsyncValue<List<Song>> songsV;
  final VoidCallback onRetry;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(playerProvider.notifier);
    final side = math.min(MediaQuery.sizeOf(context).width * .6, 300.0);
    final list = songsV.valueOrNull ?? <Song>[];
    return Scaffold(
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer(hero: false)),
      appBar: AppBar(
        actions: [
          ...extraActions,
          if (onDelete != null)
            PopupMenuButton<String>(
              onSelected: (_) => onDelete!(),
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
            child: (cover == null || cover!.isEmpty)
                ? Container(
                    width: side,
                    height: side,
                    decoration: BoxDecoration(gradient: AppColors.gradient, borderRadius: BorderRadius.circular(20)),
                    child: const Icon(Icons.favorite_rounded, size: 90),
                  )
                : Artwork(cover!, size: side, radius: 20),
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
          error: (_, __) => SizedBox(height: 260, child: ErrorState(onRetry: onRetry)),
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

/// Liked Songs and playlists created on this phone.
class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userPl = ref.watch(userPlaylistsProvider);
    final likes = ref.watch(likesProvider);
    if (id == 'liked') {
      return _CollectionView(
        title: 'Liked Songs',
        sub: '${likes.length} songs',
        cover: null,
        songsV: AsyncData(likes.songs),
        onRetry: () {},
      );
    }
    final m = userPl.where((p) => p.id == id);
    if (m.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.error_outline, title: 'Not found', message: 'This playlist no longer exists.'),
      );
    }
    final p = m.first;
    return _CollectionView(
      title: p.name,
      sub: '${p.description} • ${p.songs.length} songs',
      cover: p.cover,
      songsV: AsyncData(p.songs),
      onRetry: () {},
      onDelete: () {
        ref.read(userPlaylistsProvider.notifier).remove(id);
        context.pop();
      },
    );
  }
}

/// A YouTube Music album, playlist or podcast.
class RemoteCollectionScreen extends ConsumerWidget {
  const RemoteCollectionScreen({super.key, required this.url, required this.name, required this.cover, this.kind = 'playlist'});
  final String url, name, cover, kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(playlistDetailsProvider(url));
    final p = v.valueOrNull;
    final title = (p?.name.isNotEmpty ?? false) ? p!.name : name;
    final coverUrl = (p?.cover.isNotEmpty ?? false) ? p!.cover : cover;
    final saved = ref.watch(libraryProvider).hasCollection(url);
    return _CollectionView(
      extraActions: [
        IconButton(
          tooltip: saved ? 'Remove from library' : 'Add to library',
          icon: Icon(saved ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
              color: saved ? AppColors.primary : Colors.white),
          onPressed: () {
            ref.read(libraryProvider.notifier).toggleCollection(
                Playlist(id: url, name: title, description: p?.description ?? '', cover: coverUrl, kind: kind));
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(saved ? 'Removed from your library' : 'Added to your library')));
          },
        ),
      ],
      title: title,
      sub: p == null ? '' : '${p.description}${p.description.isEmpty ? '' : ' • '}${p.songs.length} songs',
      cover: coverUrl,
      songsV: v.whenData((d) => d.songs),
      onRetry: () => ref.invalidate(playlistDetailsProvider(url)),
    );
  }
}

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsV = ref.watch(songsQueryProvider(name));
    final others = ref.watch(topKeyProvider).split('|').where((e) => e.isNotEmpty && e != name).toList();
    final ctl = ref.read(playerProvider.notifier);
    final w = (MediaQuery.sizeOf(context).width * .38).clamp(120.0, 180.0).toDouble();

    if (songsV.hasError) {
      return Scaffold(appBar: AppBar(), body: ErrorState(onRetry: () => ref.invalidate(songsQueryProvider(name))));
    }
    if (!songsV.hasValue) return Scaffold(appBar: AppBar(), body: const LoadingState());
    final songs = songsV.requireValue;
    final image = songs.isEmpty ? '' : songs.first.artwork;

    final inLibrary = ref.watch(libraryProvider).hasArtist(name);
    final isFav = ref.watch(tasteProvider).artists.contains(name);
    return Scaffold(
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer(hero: false)),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 10, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => ref.read(libraryProvider.notifier).toggleArtist(name),
              icon: Icon(inLibrary ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined, size: 18),
              label: Text(inLibrary ? 'In library' : 'Add to library'),
            ),
            FilledButton.tonalIcon(
              onPressed: () {
                ref.read(tasteProvider.notifier).toggleArtist(name);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(isFav ? 'Removed from Your artists' : 'Added to Your artists. Your home feed will update.')));
              },
              style: FilledButton.styleFrom(
                backgroundColor: isFav ? AppColors.primary : AppColors.surfaceVariant,
                foregroundColor: Colors.white,
              ),
              icon: Icon(isFav ? Icons.check_rounded : Icons.add_rounded, size: 18),
              label: Text(isFav ? 'In Your artists' : 'Add to Your artists'),
            ),
          ]),
        ),
        const SectionHeader('Popular'),
        for (var i = 0; i < songs.length; i++) SongTile(song: songs[i], onTap: () => ctl.playQueue(songs, i)),
        if (others.isNotEmpty) ...[
          const SectionHeader('Related Artists'),
          HList(
            height: w * .7 + 50,
            count: others.length,
            itemBuilder: (_, i) => PosterCard(
              imageUrl: '',
              image: ArtistImage(others[i], size: w * .7),
              title: others[i],
              subtitle: 'Artist',
              width: w * .7,
              circle: true,
              onTap: () => context.push('/artist/${Uri.encodeComponent(others[i])}'),
            ),
          ),
        ],
        const SizedBox(height: 130),
      ]),
    );
  }
}
