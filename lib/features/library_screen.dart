import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/repositories.dart';
import '../state/providers.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final likes = ref.watch(likesProvider);
    final userLists = ref.watch(userPlaylistsProvider);
    final ctl = ref.read(playerProvider.notifier);
    final liked = likes.songs;
    final artists = artistsFrom(liked);

    return SafeArea(
      bottom: false,
      child: DefaultTabController(
        length: 3,
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
            tabs: [Tab(text: 'Playlists'), Tab(text: 'Songs'), Tab(text: 'Artists')],
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
                if (userLists.isEmpty)
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
              artists.isEmpty
                  ? const EmptyState(
                      icon: Icons.person_outline_rounded,
                      title: 'No artists yet',
                      message: 'Artists of songs you like will show up here.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 130),
                      itemCount: artists.length,
                      itemBuilder: (_, i) => ListTile(
                        leading: ArtistImage(artists[i].name, fallback: artists[i].image, size: 52),
                        title: Text(artists[i].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        onTap: () => context.push('/artist/${Uri.encodeComponent(artists[i].id)}'),
                      ),
                    ),
            ]),
          ),
        ]),
      ),
    );
  }
}
