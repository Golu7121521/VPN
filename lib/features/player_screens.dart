import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

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
  bool _locked = false, _immersive = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() => setState(() => _dy = _from + (_to - _from) * Curves.easeOutCubic.transform(_c.value)));
  }

  @override
  void dispose() {
    _c.dispose();
    if (_locked || _immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    super.dispose();
  }

  // ---- landscape / full-screen video ----
  void _enterFullscreen() {
    _locked = true;
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  }

  void _exitFullscreen() {
    _locked = false;
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    });
  }

  void _syncUi(bool videoMode, bool fs) {
    if (fs != _immersive) {
      _immersive = fs;
      WidgetsBinding.instance.addPostFrameCallback((_) =>
          SystemChrome.setEnabledSystemUIMode(fs ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge));
    }
    if (!videoMode && _locked) _exitFullscreen();
  }

  void _run(double to, {bool pop = false}) {
    _from = _dy;
    _to = to;
    _c.forward(from: 0).then((_) {
      if (pop && mounted) context.pop();
    });
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
    final videoMode = ref.watch(playerProvider.select((s) => s.videoMode));
    final hasVideo = ref.watch(playerProvider.select((s) => s.hasVideo));
    final hasAudio = ref.watch(playerProvider.select((s) => s.hasAudio));
    final videoBusy = ref.watch(playerProvider.select((s) => s.videoBusy));
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final fs = videoMode && landscape;
    _syncUi(videoMode, fs);
    if (fs) {
      // Landscape: the video fills the whole screen.
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _exitFullscreen();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: _VideoStage(fullscreen: true, onToggleFullscreen: _exitFullscreen),
        ),
      );
    }
    final tint = ref.watch(artColorProvider(song.artwork)).valueOrNull ?? const Color(0xFF2A1B4D);
    final ctl = ref.read(playerProvider.notifier);

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
                Expanded(
                  child: Center(
                    child: (hasVideo && hasAudio)
                        ? _ModeSwitch(
                            video: videoMode,
                            busy: videoBusy,
                            onChanged: (v) => ctl.setVideoMode(v),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                IconButton(
                  tooltip: 'More options',
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => showSongSheet(context, song),
                ),
              ]),
              Expanded(
                child: Center(
                  child: videoMode
                      ? _InlineVideo(onFullscreen: _enterFullscreen)
                      : LayoutBuilder(builder: (_, box) {
                    final side = math.min(box.maxWidth, box.maxHeight) - 16;
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
          : () => downloadWithAd(context, ref, song),
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
          toolbarHeight: 56,
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


// ---------- Song / Video switch ----------
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.video, required this.busy, required this.onChanged});
  final bool video, busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool selected, bool isVideo) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: busy || selected ? null : () => onChanged(isVideo),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? Colors.white.withAlpha(60) : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (isVideo && busy)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              Text(label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.textSecondary,
                  )),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Colors.black.withAlpha(70), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('Song', !video, false),
        seg('Video', video, true),
      ]),
    );
  }
}

/// Portrait: the video sits where the artwork normally is.
class _InlineVideo extends ConsumerWidget {
  const _InlineVideo({required this.onFullscreen});
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(playerProvider.select((s) => s.videoRev));
    final v = ref.read(playerProvider.notifier).videoController;
    final ar = (v == null || !v.value.isInitialized ? 16 / 9 : v.value.aspectRatio).clamp(.5625, 16 / 9).toDouble();
    return LayoutBuilder(builder: (_, box) {
      final w = math.min(box.maxWidth, box.maxHeight * ar);
      return SizedBox(
        width: w,
        height: w / ar,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _VideoStage(fullscreen: false, onToggleFullscreen: onFullscreen),
        ),
      );
    });
  }
}

/// The video with YouTube-Music-style gestures: tap = controls, double tap left/right = -/+10 s,
/// two-finger pinch = fit <-> edge-to-edge cover (pinch out in portrait opens full screen).
class _VideoStage extends ConsumerStatefulWidget {
  const _VideoStage({required this.fullscreen, required this.onToggleFullscreen});
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;
  @override
  ConsumerState<_VideoStage> createState() => _VideoStageState();
}

class _VideoStageState extends ConsumerState<_VideoStage> with SingleTickerProviderStateMixin {
  bool _controls = true;
  Timer? _hide, _seekTimer;
  double _zoom = 1, _baseZoom = 1, _lastScale = 1;
  late final AnimationController _zc = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Offset _tap = Offset.zero;
  int _seekDir = 0, _seekAcc = 0;
  Duration _pending = Duration.zero;

  @override
  void initState() {
    super.initState();
    _zc.addListener(() => setState(() => _zoom = _zFrom + (_zTo - _zFrom) * Curves.easeOut.transform(_zc.value)));
    _autoHide();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _seekTimer?.cancel();
    _zc.dispose();
    super.dispose();
  }

  void _autoHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && ref.read(playerProvider).playing) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _autoHide();
  }

  void _doubleTap(double width) {
    final ctl = ref.read(playerProvider.notifier);
    final v = ctl.videoController;
    if (v == null) return;
    final dir = _tap.dx < width / 2 ? -1 : 1;
    final dur = v.value.duration;
    final base = (_seekTimer?.isActive ?? false) && dir == _seekDir ? _pending : v.value.position;
    var target = base + Duration(seconds: 10 * dir);
    if (target < Duration.zero) target = Duration.zero;
    if (dur > Duration.zero && target > dur) target = dur;
    _pending = target;
    ctl.seek(target);
    _seekTimer?.cancel();
    setState(() {
      _seekAcc = _seekDir == dir && _seekAcc > 0 ? _seekAcc + 10 : 10;
      _seekDir = dir;
    });
    _seekTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _seekAcc = 0);
    });
  }

  double _zFrom = 1, _zTo = 1;

  void _snap(double maxZoom) {
    _zFrom = _zoom;
    _zTo = _zoom > 1 + (maxZoom - 1) * .35 ? maxZoom : 1.0;
    _zc.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(playerProvider.select((s) => s.videoRev));
    final playing = ref.watch(playerProvider.select((s) => s.playing));
    final loading = ref.watch(playerProvider.select((s) => s.loading));
    final title = ref.watch(playerProvider.select((s) => s.current?.title ?? ''));
    final ctl = ref.read(playerProvider.notifier);
    final v = ctl.videoController;
    if (v == null || !v.value.isInitialized) {
      return const ColoredBox(color: Colors.black, child: Center(child: CircularProgressIndicator()));
    }
    final fs = widget.fullscreen;
    return LayoutBuilder(builder: (_, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final a = v.value.aspectRatio <= 0 ? 16 / 9 : v.value.aspectRatio;
      final cw = w / h > a ? h * a : w;
      final ch = w / h > a ? h : w / a;
      final maxZoom = math.max(w / cw, h / ch);
      final z = _zoom.clamp(1.0, math.max(1.0, maxZoom)).toDouble();
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: (d) => _tap = d.localPosition,
        onDoubleTap: () => _doubleTap(w),
        onScaleStart: (_) {
          _zc.stop();
          _baseZoom = _zoom;
          _lastScale = 1;
        },
        onScaleUpdate: (d) {
          if (d.pointerCount < 2) return;
          _lastScale = d.scale;
          if (fs) setState(() => _zoom = (_baseZoom * d.scale).clamp(1.0, math.max(1.0, maxZoom)).toDouble());
        },
        onScaleEnd: (_) {
          if (fs) {
            _snap(maxZoom);
          } else if (_lastScale > 1.15) {
            widget.onToggleFullscreen(); // pinch out in portrait -> full screen (landscape)
          }
          _lastScale = 1;
        },
        child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: Colors.black),
          ClipRect(
            child: Center(
              child: Transform.scale(
                scale: z,
                child: SizedBox(width: cw, height: ch, child: VideoPlayer(v)),
              ),
            ),
          ),
          // double-tap seek feedback
          if (_seekAcc > 0)
            Align(
              alignment: _seekDir < 0 ? Alignment.centerLeft : Alignment.centerRight,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 28),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(40)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_seekDir < 0 ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded, size: 28),
                  Text('$_seekAcc s', style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          // controls
          IgnorePointer(
            ignoring: !_controls,
            child: AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x99000000), Color(0x33000000), Color(0x99000000)],
                  ),
                ),
                child: Stack(children: [
                  Positioned(
                    top: fs ? 8 : 0,
                    left: fs ? 8 : 12,
                    right: 0,
                    child: Row(children: [
                      if (fs) ...[
                        IconButton(
                          tooltip: 'Exit full screen',
                          icon: const Icon(Icons.arrow_back_rounded),
                          onPressed: widget.onToggleFullscreen,
                        ),
                        Expanded(
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                      ] else
                        const Spacer(),
                      if (!fs)
                        IconButton(
                          tooltip: 'Full screen',
                          icon: const Icon(Icons.fullscreen_rounded),
                          onPressed: widget.onToggleFullscreen,
                        ),
                    ]),
                  ),
                  Center(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(iconSize: fs ? 44 : 34, icon: const Icon(Icons.skip_previous_rounded), onPressed: ctl.previous),
                      SizedBox(width: fs ? 24 : 12),
                      loading
                          ? const SizedBox(width: 56, height: 56, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                          : IconButton(
                              iconSize: fs ? 64 : 48,
                              icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                              onPressed: () {
                                ctl.toggle();
                                _autoHide();
                              },
                            ),
                      SizedBox(width: fs ? 24 : 12),
                      IconButton(iconSize: fs ? 44 : 34, icon: const Icon(Icons.skip_next_rounded), onPressed: ctl.next),
                    ]),
                  ),
                  if (fs)
                    const Positioned(left: 24, right: 24, bottom: 8, child: MusicSlider()),
                ]),
              ),
            ),
          ),
        ]),
      );
    });
  }
}
