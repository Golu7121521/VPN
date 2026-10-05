import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../state/providers.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final likes = ref.watch(likesProvider);
    final userLists = ref.watch(userPlaylistsProvider);
    final ctl = ref.read(playerProvider.notifier);
    final liked = likes.songs;
    final lib = ref.watch(libraryProvider);
    final artists = lib.artists;
    List kind(String k) => lib.collections.where((c) => c.kind == k).toList();
    final savedPlaylists = kind('playlist'), albums = kind('album'), podcasts = kind('podcast');

    return SafeArea(
      bottom: false,
      child: DefaultTabController(
        length: 5,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(children: [
              const Expanded(child: Text('Your Library', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800))),
              IconButton(
                tooltip: 'Create playlist',
                icon: const Icon(Icons.add_rounded, size: 30),
                onPressed: () => showCreatePlaylist(context),
              ),
            ]),
          ),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppColors.primary,
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textSecondary,
            dividerColor: Colors.transparent,
            tabs: [Tab(text: 'Playlists'), Tab(text: 'Songs'), Tab(text: 'Albums'), Tab(text: 'Artists'), Tab(text: 'Podcasts')],
          ),
          Expanded(
            child: TabBarView(children: [
              ListView(padding: const EdgeInsets.only(bottom: 130), children: [
                ListTile(
                  leading: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(gradient: AppColors.gradient, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.favorite_rounded),
                  ),
                  title: const Text('Liked Songs', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${liked.length} songs', style: const TextStyle(color: AppColors.textSecondary)),
                  onTap: () => context.push('/playlist/liked'),
                ),
                for (final p in userLists)
                  ListTile(
                    leading: Artwork(p.cover, size: 52, radius: 10),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${p.songs.length} songs', style: const TextStyle(color: AppColors.textSecondary)),
                    onTap: () => context.push('/playlist/${p.id}'),
                  ),
                for (final c in savedPlaylists)
                  ListTile(
                    leading: Artwork(c.cover, size: 52, radius: 10),
                    title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(c.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary)),
                    onTap: () => openCollection(context, c, kind: 'playlist'),
                  ),
                if (userLists.isEmpty && savedPlaylists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Tap + to create your own playlist.',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                  ),
              ]),
              liked.isEmpty
                  ? const EmptyState(
                      icon: Icons.favorite_border_rounded,
                      title: 'No liked songs yet',
                      message: 'Tap the heart on any song to save it here.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 130),
                      itemCount: liked.length,
                      itemBuilder: (_, i) => SongTile(song: liked[i], onTap: () => ctl.playQueue(liked, i)),
                    ),
              _savedList(context, albums, 'album', Icons.album_rounded, 'No albums saved', 'Open an album and tap the bookmark to save it here.'),
              artists.isEmpty
                  ? const EmptyState(
                      icon: Icons.person_outline_rounded,
                      title: 'No artists saved',
                      message: 'Open an artist and tap "Add to library".',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 130),
                      itemCount: artists.length,
                      itemBuilder: (_, i) => ListTile(
                        leading: ArtistImage(artists[i], size: 52),
                        title: Text(artists[i], style: const TextStyle(fontWeight: FontWeight.w600)),
                        onTap: () => context.push('/artist/${Uri.encodeComponent(artists[i])}'),
                      ),
                    ),
              _savedList(context, podcasts, 'podcast', Icons.podcasts, 'No podcasts saved', 'Open a podcast and tap the bookmark to save it here.'),
            ]),
          ),
        ]),
      ),
    );
  }
}

Widget _savedList(BuildContext context, List items, String kind, IconData icon, String title, String msg) {
  if (items.isEmpty) return EmptyState(icon: icon, title: title, message: msg);
  return ListView.builder(
    padding: const EdgeInsets.only(bottom: 130),
    itemCount: items.length,
    itemBuilder: (_, i) {
      final c = items[i];
      return ListTile(
        leading: Artwork(c.cover, size: 52, radius: 10),
        title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(c.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary)),
        onTap: () => openCollection(context, c, kind: kind),
      );
    },
  );
}
