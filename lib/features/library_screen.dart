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
    final songsV = ref.watch(songsProvider);
    final albums = ref.watch(albumsProvider).valueOrNull ?? [];
    final artists = ref.watch(artistsProvider).valueOrNull ?? [];
    final mockLists = ref.watch(playlistsProvider).valueOrNull ?? [];
    final userLists = ref.watch(userPlaylistsProvider);
    final likes = ref.watch(likesProvider);
    final ctl = ref.read(playerProvider.notifier);

    return SafeArea(
      bottom: false,
      child: DefaultTabController(
        length: 4,
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
            tabs: [Tab(text: 'Playlists'), Tab(text: 'Songs'), Tab(text: 'Albums'), Tab(text: 'Artists')],
          ),
          Expanded(
            child: songsV.when(
              loading: () => const LoadingState(),
              error: (_, __) => ErrorState(onRetry: () => ref.invalidate(songsProvider)),
              data: (songs) {
                final liked = songs.where((s) => likes.contains(s.id)).toList();
                return TabBarView(children: [
                  ListView(children: [
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
                    for (final p in [...userLists, ...mockLists])
                      ListTile(
                        leading: Artwork(p.cover, size: 52, radius: 10),
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${p.songIds.length} songs', style: const TextStyle(color: AppColors.textSecondary)),
                        onTap: () => context.push('/playlist/${p.id}'),
                      ),
                  ]),
                  liked.isEmpty
                      ? const EmptyState(
                          icon: Icons.favorite_border_rounded,
                          title: 'No liked songs yet',
                          message: 'Tap the heart on any song to save it here.',
                        )
                      : ListView.builder(
                          itemCount: liked.length,
                          itemBuilder: (_, i) => SongTile(song: liked[i], onTap: () => ctl.playQueue(liked, i)),
                        ),
                  GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: .72,
                    ),
                    itemCount: albums.length > 6 ? 6 : albums.length,
                    itemBuilder: (_, i) => PosterCard(
                      imageUrl: albums[i].artwork,
                      title: albums[i].title,
                      subtitle: albums[i].artistName,
                      width: 200,
                      onTap: () => context.push('/album/${albums[i].id}'),
                    ),
                  ),
                  ListView.builder(
                    itemCount: artists.length > 6 ? 6 : artists.length,
                    itemBuilder: (_, i) => ListTile(
                      leading: Artwork(artists[i].image, size: 52, circle: true),
                      title: Text(artists[i].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(artists[i].listeners, style: const TextStyle(color: AppColors.textSecondary)),
                      onTap: () => context.push('/artist/${artists[i].id}'),
                    ),
                  ),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }
}
