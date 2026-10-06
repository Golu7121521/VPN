import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:startapp_sdk/startapp.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import '../state/art_color.dart';
import '../state/providers.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});
  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  double _dy = 0, _from = 0, _to = 0;
  bool _video = false, _loadingVideo = false;
  VideoPlayerController? _vc;

  @override
  void initState() {
    super.initState();
    _c.addListener(() => setState(() => _dy = _from + (_to - _from) * Curves.easeOutCubic.transform(_c.value)));
  }

  @override
  void dispose() {
    _c.dispose();
    _vc?.dispose();
    super.dispose();
  }

  void _run(double to, {bool pop = false}) {
    _from = _dy;
    _to = to;
    _c.forward(from: 0).then((_) {
      if (pop && mounted) context.pop();
    });
  }

  /// Video mode: a muted video follows the audio player, which stays the master clock.
  Future<void> _enableVideo(Song s) async {
    setState(() => _loadingVideo = true);
    VideoPlayerController? vc;
    try {
      final url = await ref.read(musicRepoProvider).videoUrl(s);
      if (url == null) throw Exception('no video');
      vc = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: {'User-Agent': kUserAgent},
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await vc.initialize();
      await vc.setVolume(0);
      await vc.seekTo(ref.read(positionProvider).valueOrNull ?? Duration.zero);
      if (!mounted || !_video) {
        await vc.dispose();
        return;
      }
      if (ref.read(playerProvider).playing) await vc.play();
      final old = _vc;
      setState(() {
        _vc = vc;
        _loadingVideo = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    } catch (_) {
      await vc?.dispose();
      if (mounted) {
        setState(() {
          _video = false;
          _loadingVideo = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video is not available for this song')));
      }
    }
  }

  void _setMode(bool video, Song song) {
    if (video == _video) return;
    setState(() => _video = video);
    if (video) {
      _enableVideo(song);
    } else {
      final old = _vc;
      setState(() => _vc = null);
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    }
  }

  Widget _modeToggle(Song song) {
    Widget seg(String t, bool v) => GestureDetector(
          onTap: () => _setMode(v, song),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: _video == v ? Colors.white.withAlpha(40) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(t, style: TextStyle(fontWeight: FontWeight.w700, color: _video == v ? Colors.white : AppColors.textSecondary)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Colors.black.withAlpha(60), borderRadius: BorderRadius.circular(24)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [seg('Song', false), seg('Video', true)]),
    );
  }

  void _sleepSheet() {
    final label = ref.read(playerProvider).sleepLabel;
    final ctl = ref.read(playerProvider.notifier);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Sleep timer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          for (final o in const [('Off', null), ('15 min', 15), ('30 min', 30), ('45 min', 45), ('1 hour', 60), ('End of song', -1)])
            ListTile(
              title: Text(o.$1),
              trailing: (o.$2 == null ? label == null : (o.$2 == -1 ? label == 'End of song' : label == '${o.$2} min'))
                  ? const Icon(Icons.check_rounded, color: AppColors.primary)
                  : null,
              onTap: () {
                if (o.$2 == null) {
                  ctl.setSleep(null);
                } else if (o.$2 == -1) {
                  ctl.setSleep(null, endOfSong: true);
                } else {
                  ctl.setSleep(Duration(minutes: o.$2!));
                }
                Navigator.pop(ctx);
              },
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
    final sleep = ref.watch(playerProvider.select((s) => s.sleepLabel));
    final liked = ref.watch(likesProvider).contains(song.id);
    final tint = ref.watch(artColorProvider(song.artwork)).valueOrNull ?? const Color(0xFF2A1B4D);
    final ctl = ref.read(playerProvider.notifier);

    ref.listen(playerProvider.select((s) => s.playing), (_, p) {
      final vc = _vc;
      if (vc == null) return;
      p ? vc.play() : vc.pause();
    });
    ref.listen(playerProvider.select((s) => s.current?.id), (_, id) {
      final s = ref.read(playerProvider).current;
      if (_video && s != null) _enableVideo(s);
    });
    ref.listen(positionProvider, (_, pos) {
      final vc = _vc;
      final p = pos.valueOrNull;
      if (vc != null && p != null && vc.value.isInitialized && (vc.value.position - p).abs() > const Duration(milliseconds: 1500)) {
        vc.seekTo(p);
      }
    });

    final page = Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 700),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [tint, AppColors.background],
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
                Expanded(child: Center(child: _modeToggle(song))),
                IconButton(
                  tooltip: 'More options',
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => showSongSheet(context, song),
                ),
              ]),
              Expanded(
                child: Center(
                  child: LayoutBuilder(builder: (_, box) {
                    final side = math.min(box.maxWidth, box.maxHeight) - 16;
                    final showVideo = _video && _vc != null && _vc!.value.isInitialized;
                    if (showVideo) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SizedBox(
                          width: box.maxWidth,
                          child: AspectRatio(aspectRatio: _vc!.value.aspectRatio, child: VideoPlayer(_vc!)),
                        ),
                      );
                    }
                    return Stack(alignment: Alignment.center, children: [
                      Hero(
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
                                BoxShadow(color: AppColors.primary.withAlpha(playing ? 120 : 40), blurRadius: 50, spreadRadius: 2),
                              ],
                            ),
                            child: Artwork(song.artwork, size: side, radius: 24),
                          ),
                        ),
                      ),
                      if (_loadingVideo) const CircularProgressIndicator(color: Colors.white),
                    ]);
                  }),
                ),
              ),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(song.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    GestureDetector(
                      onTap: () => openArtist(context, song.artistName),
                      child: Text(song.artistName, style: const TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                    ),
                  ]),
                ),
                IconButton(
                  tooltip: liked ? 'Remove from liked songs' : 'Like song',
                  iconSize: 30,
                  onPressed: () => ref.read(likesProvider.notifier).toggle(song),
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
              const SizedBox(height: 4),
              const MusicSlider(),
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
                    repeat == RepeatKind.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                    color: repeat == RepeatKind.off ? AppColors.textSecondary : AppColors.primary,
                  ),
                  onPressed: ctl.cycleRepeat,
                ),
              ]),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _DownloadButton(song: song),
                IconButton(
                  tooltip: sleep == null ? 'Sleep timer' : 'Sleep timer: $sleep',
                  icon: Icon(Icons.bedtime_outlined, color: sleep == null ? AppColors.textSecondary : AppColors.primary),
                  onPressed: _sleepSheet,
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
              const SizedBox(height: 28),
            ]),
          ),
        ),
      ),
    );
    // Pull down to shrink back into the mini player.
    return GestureDetector(
      onVerticalDragUpdate: (d) => setState(() => _dy = (_dy + d.delta.dy).clamp(0.0, double.infinity)),
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (_dy > 140 || v > 800) {
          _run(MediaQuery.sizeOf(context).height, pop: true);
        } else {
          _run(0);
        }
      },
      child: Transform.translate(offset: Offset(0, _dy), child: page),
    );
  }
}

class _DownloadButton extends ConsumerWidget {
  const _DownloadButton({required this.song});
  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(downloadsProvider);
    final p = d.progress[song.id];
    if (p != null) {
      return SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 3, value: p == 0 ? null : p, color: AppColors.primary),
          ),
        ),
      );
    }
    final done = d.pathFor(song.id) != null;
    return IconButton(
      tooltip: done ? 'Downloaded' : 'Download',
      icon: Icon(done ? Icons.download_done_rounded : Icons.download_rounded,
          color: done ? AppColors.primary : AppColors.textSecondary),
      onPressed: done
          ? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Already downloaded')))
          : () async {
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(const SnackBar(content: Text('Loading Ad...')));

              try {
                final startAppSdk = StartAppSdk();
                final rewardedAd = await startAppSdk.loadRewardedVideoAd();

                if (rewardedAd != null) {
                  // Await the completion of the ad show, then start the download
                  await rewardedAd.show();
                  ref.read(downloadsProvider.notifier).download(song);
                  messenger.showSnackBar(const SnackBar(content: Text('Downloading in best quality...')));
                } else {
                  // Fallback: Agar ad load nahi ho pata
                  ref.read(downloadsProvider.notifier).download(song);
                  messenger.showSnackBar(const SnackBar(content: Text('Downloading in best quality...')));
                }
              } catch (e) {
                // Fallback: Kisi bhi error ke case mein download shuru kar dein
                ref.read(downloadsProvider.notifier).download(song);
                messenger.showSnackBar(const SnackBar(content: Text('Downloading in best quality...')));
              }
            },
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
      value: ref.watch(lyricsProvider(song)),
      onRetry: () => ref.invalidate(lyricsProvider(song)),
      builder: (lines) {
        if (lines.isEmpty) {
          return const EmptyState(
            icon: Icons.lyrics_outlined,
            title: 'No lyrics found',
            message: "We couldn't find lyrics for this song.",
          );
        }
        final synced = lines.first.at >= Duration.zero;
        final pos = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
        final active = synced ? lines.lastIndexWhere((l) => l.at <= pos) : -1;
        if (synced && active != _last) {
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
                color: (!synced || i == active) ? Colors.white : AppColors.textSecondary.withAlpha(150),
              ),
              child: Text(lines[i].text),
            ),
          ),
        );
      },
    );
  }
}
