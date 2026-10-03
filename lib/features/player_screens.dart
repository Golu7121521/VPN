import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import '../state/providers.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(playerProvider.select((s) => s.current));
    if (song == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.music_off_rounded, title: 'Nothing playing', message: 'Pick a song to start.'),
      );
    }
    final playing = ref.watch(playerProvider.select((s) => s.playing));
    final loading = ref.watch(playerProvider.select((s) => s.loading));
    final shuffle = ref.watch(playerProvider.select((s) => s.shuffle));
    final repeat = ref.watch(playerProvider.select((s) => s.repeat));
    final liked = ref.watch(likesProvider).contains(song.id);
    final ctl = ref.read(playerProvider.notifier);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2A1B4D), AppColors.background],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(children: [
              Row(children: [
                IconButton(
                  tooltip: 'Close player',
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                  onPressed: () => context.pop(),
                ),
                const Expanded(child: Center(child: Text('Now Playing', style: TextStyle(fontWeight: FontWeight.w600)))),
                IconButton(
                  tooltip: 'More options',
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => showSongSheet(context, song),
                ),
              ]),
              Expanded(
                child: Center(
                  child: LayoutBuilder(builder: (_, box) {
                    final side = (box.maxWidth < box.maxHeight ? box.maxWidth : box.maxHeight) - 16;
                    return Hero(
                      tag: 'now-art',
                      child: AnimatedScale(
                        scale: playing ? 1 : .9,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          width: side,
                          height: side,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withAlpha(playing ? 120 : 40),
                                blurRadius: 50,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Artwork(song.artwork, size: side, radius: 24),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(song.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    Text(song.artistName, style: const TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                  ]),
                ),
                IconButton(
                  tooltip: liked ? 'Remove from liked songs' : 'Like song',
                  iconSize: 30,
                  onPressed: () => ref.read(likesProvider.notifier).toggle(song.id),
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: Icon(
                      liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      key: ValueKey(liked),
                      color: liked ? Colors.redAccent : Colors.white,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              const MusicSlider(),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                IconButton(
                  tooltip: shuffle ? 'Shuffle on' : 'Shuffle off',
                  icon: Icon(Icons.shuffle_rounded, color: shuffle ? AppColors.primary : AppColors.textSecondary),
                  onPressed: ctl.toggleShuffle,
                ),
                IconButton(tooltip: 'Previous', iconSize: 40, icon: const Icon(Icons.skip_previous_rounded), onPressed: ctl.previous),
                RoundPlayButton(playing: playing, loading: loading, onTap: ctl.toggle),
                IconButton(tooltip: 'Next', iconSize: 40, icon: const Icon(Icons.skip_next_rounded), onPressed: ctl.next),
                IconButton(
                  tooltip: 'Repeat ${repeat.name}',
                  icon: Icon(
                    repeat == RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                    color: repeat == RepeatMode.off ? AppColors.textSecondary : AppColors.primary,
                  ),
                  onPressed: ctl.cycleRepeat,
                ),
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                IconButton(
                  tooltip: 'Connect to a device',
                  icon: const Icon(Icons.cast_rounded, color: AppColors.textSecondary),
                  onPressed: () => ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('No devices found nearby'))),
                ),
                IconButton(
                  tooltip: 'Lyrics',
                  icon: const Icon(Icons.lyrics_outlined, color: AppColors.textSecondary),
                  onPressed: () => context.push('/queue?tab=lyrics'),
                ),
                IconButton(
                  tooltip: 'Queue',
                  icon: const Icon(Icons.queue_music_rounded, color: AppColors.textSecondary),
                  onPressed: () => context.push('/queue'),
                ),
              ]),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      ),
    );
  }
}

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(playerProvider.notifier);
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Playing Queue'),
          actions: [
            TextButton(
              onPressed: () async {
                await ctl.clearQueue();
                if (context.mounted) context.go('/home');
              },
              child: const Text('Clear', style: TextStyle(color: AppColors.primary)),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: AppColors.primary,
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: [Tab(text: 'Queue'), Tab(text: 'Lyrics')],
          ),
        ),
        body: const TabBarView(children: [_QueueTab(), _LyricsTab()]),
      ),
    );
  }
}

class _QueueTab extends ConsumerWidget {
  const _QueueTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(playerProvider.select((s) => s.queue));
    final index = ref.watch(playerProvider.select((s) => s.index));
    final ctl = ref.read(playerProvider.notifier);
    if (queue.isEmpty) {
      return const EmptyState(icon: Icons.queue_music_rounded, title: 'Queue is empty', message: 'Play a song to build your queue.');
    }
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: queue.length,
      onReorder: ctl.move,
      itemBuilder: (_, i) {
        final s = queue[i];
        final now = i == index;
        return ListTile(
          key: ValueKey('q$i-${s.id}'),
          onTap: () => ctl.skipTo(i),
          leading: Artwork(s.artwork, size: 48, radius: 10),
          title: Text(s.title,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w600, color: now ? AppColors.primary : Colors.white)),
          subtitle: Text(now ? 'Now playing • ${s.artistName}' : s.artistName,
              style: const TextStyle(color: AppColors.textSecondary)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (!now)
              IconButton(
                tooltip: 'Remove from queue',
                icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                onPressed: () => ctl.removeAt(i),
              ),
            ReorderableDragStartListener(
              index: i,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_handle_rounded, color: AppColors.textSecondary),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _LyricsTab extends ConsumerStatefulWidget {
  const _LyricsTab();
  @override
  ConsumerState<_LyricsTab> createState() => _LyricsTabState();
}

class _LyricsTabState extends ConsumerState<_LyricsTab> {
  final _sc = ScrollController();
  int _last = -2;
  static const _extent = 72.0;

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  void _scrollTo(int i) {
    if (i < 0 || !_sc.hasClients) return;
    final vh = _sc.position.viewportDimension;
    final t = (24 + i * _extent + _extent / 2 - vh / 2).clamp(0.0, _sc.position.maxScrollExtent).toDouble();
    _sc.animateTo(t, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(playerProvider.select((s) => s.current));
    if (song == null) {
      return const EmptyState(icon: Icons.lyrics_outlined, title: 'No lyrics', message: 'Play a song to see its lyrics.');
    }
    return AsyncView<List<LyricLine>>(
      value: ref.watch(lyricsProvider(song.id)),
      onRetry: () => ref.invalidate(lyricsProvider(song.id)),
      builder: (lines) {
        final pos = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
        final active = lines.lastIndexWhere((l) => l.at <= pos);
        if (active != _last) {
          _last = active;
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(active));
        }
        return ListView.builder(
          controller: _sc,
          itemExtent: _extent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          itemCount: lines.length,
          itemBuilder: (_, i) => Align(
            alignment: Alignment.centerLeft,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: i == active ? 26 : 21,
                fontWeight: FontWeight.w800,
                color: i == active ? Colors.white : AppColors.textSecondary.withAlpha(150),
              ),
              child: Text(lines[i].text),
            ),
          ),
        );
      },
    );
  }
}
