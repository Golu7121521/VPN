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

/// Playlist, Album and Liked Songs share one screen.
class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key, required this.kind, required this.id});
  final String kind, id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsV = ref.watch(songsProvider);
    final plV = ref.watch(playlistsProvider);
    final alV = ref.watch(albumsProvider);
    final userPl = ref.watch(userPlaylistsProvider);
    final likes = ref.watch(likesProvider);
    final ctl = ref.read(playerProvider.notifier);

    if (songsV.hasError || plV.hasError || alV.hasError) {
      return Scaffold(appBar: AppBar(), body: ErrorState(onRetry: () => ref.invalidate(songsProvider)));
    }
    if (!songsV.hasValue || !plV.hasValue || !alV.hasValue) {
      return Scaffold(appBar: AppBar(), body: const LoadingState());
    }
    final songs = songsV.requireValue;

    String title = '', sub = '';
    String? cover;
    var list = <Song>[];
    var isUser = false;

    if (kind == 'album') {
      final m = alV.requireValue.where((a) => a.id == id);
      if (m.isNotEmpty) {
        title = m.first.title;
        sub = '${m.first.artistName} • ${m.first.year}';
        cover = m.first.artwork;
        list = songs.where((s) => s.albumId == id).toList();
      }
    } else if (id == 'liked') {
      title = 'Liked Songs';
      list = songs.where((s) => likes.contains(s.id)).toList();
      sub = '${list.length} songs';
    } else {
      final m = [...userPl, ...plV.requireValue].where((p) => p.id == id);
      if (m.isNotEmpty) {
        final p = m.first;
        isUser = userPl.any((u) => u.id == id);
        title = p.name;
        cover = p.cover;
        list = [for (final sid in p.songIds) ...songs.where((s) => s.id == sid)];
        sub = '${p.description} • ${list.length} songs';
      }
    }
    if (title.isEmpty) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.error_outline, title: 'Not found', message: 'This item no longer exists.'));
    }

    final side = math.min(MediaQuery.sizeOf(context).width * .6, 300.0);
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
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
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
        if (list.isEmpty)
          const SizedBox(
            height: 220,
            child: EmptyState(
              icon: Icons.music_off_rounded,
              title: 'No songs yet',
              message: 'Use "Add to playlist" from any song menu.',
            ),
          )
        else
          for (var i = 0; i < list.length; i++) SongTile(song: list[i], onTap: () => ctl.playQueue(list, i)),
      ]),
    );
  }
}

class ArtistScreen extends ConsumerStatefulWidget {
  const ArtistScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<ArtistScreen> {
  bool _following = false;

  @override
  Widget build(BuildContext context) {
    final artistsV = ref.watch(artistsProvider);
    final songsV = ref.watch(songsProvider);
    final albumsV = ref.watch(albumsProvider);
    if (artistsV.hasError || songsV.hasError || albumsV.hasError) {
      return Scaffold(appBar: AppBar(), body: ErrorState(onRetry: () => ref.invalidate(artistsProvider)));
    }
    if (!artistsV.hasValue || !songsV.hasValue || !albumsV.hasValue) {
      return Scaffold(appBar: AppBar(), body: const LoadingState());
    }
    final matches = artistsV.requireValue.where((a) => a.id == widget.id);
    if (matches.isEmpty) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.person_off_rounded, title: 'Artist not found', message: ''));
    }
    final artist = matches.first;
    final songs = songsV.requireValue.where((s) => s.artistId == artist.id).toList();
    final albums = albumsV.requireValue.where((a) => a.artistId == artist.id).toList();
    final related = artistsV.requireValue.where((a) => a.id != artist.id).take(6).toList();
    final ctl = ref.read(playerProvider.notifier);
    final w = (MediaQuery.sizeOf(context).width * .38).clamp(120.0, 180.0).toDouble();

    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, children: [
        Stack(children: [
          SizedBox(height: 320, width: double.infinity, child: Artwork(artist.image, radius: 0)),
          Container(
            height: 320,
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
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(artist.name, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
                  Text(artist.listeners, style: const TextStyle(color: AppColors.textSecondary)),
                ]),
              ),
              OutlinedButton(
                onPressed: () => setState(() => _following = !_following),
                child: Text(_following ? 'Following' : 'Follow'),
              ),
            ]),
          ),
        ]),
        _PlayShuffleRow(
          onPlay: () => ctl.playQueue(songs, 0),
          onShuffle: () => ctl.playQueue([...songs]..shuffle(), 0),
        ),
        const SectionHeader('Popular'),
        for (var i = 0; i < songs.length; i++) SongTile(song: songs[i], onTap: () => ctl.playQueue(songs, i)),
        if (albums.isNotEmpty) ...[
          const SectionHeader('Albums'),
          HList(
            height: w + 58,
            count: albums.length,
            itemBuilder: (_, i) => PosterCard(
              imageUrl: albums[i].artwork,
              title: albums[i].title,
              subtitle: '${albums[i].year}',
              width: w,
              onTap: () => context.push('/album/${albums[i].id}'),
            ),
          ),
        ],
        const SectionHeader('Related Artists'),
        HList(
          height: w * .7 + 50,
          count: related.length,
          itemBuilder: (_, i) => PosterCard(
            imageUrl: related[i].image,
            title: related[i].name,
            subtitle: 'Artist',
            width: w * .7,
            circle: true,
            onTap: () => context.push('/artist/${related[i].id}'),
          ),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}
