import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models.dart';
import '../state/providers.dart';
import 'theme.dart';

String fmt(Duration d) {
  final s = d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Asks Google image servers for a bigger version so artwork stays sharp.
String resizeArt(String url, int px) {
  if (url.contains('googleusercontent.com') || url.contains('ggpht.com')) {
    final re = RegExp(r'=(w\d+-h\d+|s\d+)');
    if (re.hasMatch(url)) return url.replaceFirst(re, '=w$px-h$px');
  }
  return url;
}

class Artwork extends StatelessWidget {
  const Artwork(this.url, {super.key, this.size, this.radius = 12, this.circle = false});
  final String url;
  final double? size;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    const fallback = ColoredBox(
      color: AppColors.surfaceVariant,
      child: Center(child: Icon(Icons.music_note_rounded, color: AppColors.textSecondary)),
    );
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final px = ((size ?? 700) * dpr).round().clamp(120, 1200);
    return ClipRRect(
      borderRadius: BorderRadius.circular(circle ? 999 : radius),
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: resizeArt(url, px),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                placeholder: (_, __) => const ColoredBox(color: AppColors.surfaceVariant),
                errorWidget: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}

/// Shows the artist's own photo (looked up once and cached), never a song cover.
class ArtistImage extends ConsumerWidget {
  const ArtistImage(this.name, {super.key, this.fallback = '', this.size, this.circle = true, this.radius = 12});
  final String name, fallback;
  final double? size;
  final bool circle;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(artistImageProvider(name)).when(
          data: (u) => Artwork((u != null && u.isNotEmpty) ? u : fallback, size: size, circle: circle, radius: radius),
          loading: () => Artwork('', size: size, circle: circle, radius: radius),
          error: (_, __) => Artwork(fallback, size: size, circle: circle, radius: radius),
        );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Row(children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!, style: const TextStyle(color: AppColors.primary))),
        ]),
      );
}

class HList extends StatelessWidget {
  const HList({super.key, required this.height, required this.count, required this.itemBuilder});
  final double height;
  final int count;
  final Widget Function(BuildContext, int) itemBuilder;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: count,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: itemBuilder,
        ),
      );
}

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.width,
    required this.onTap,
    this.circle = false,
    this.image,
  });
  final Widget? image;
  final String imageUrl, title, subtitle;
  final double width;
  final VoidCallback onTap;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final align = circle ? TextAlign.center : TextAlign.start;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: circle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            image ?? Artwork(imageUrl, size: width, radius: 16, circle: circle),
            const SizedBox(height: 8),
            Text(title,
                maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: align,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(subtitle,
                maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: align,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class SongTile extends ConsumerWidget {
  const SongTile({super.key, required this.song, required this.onTap});
  final Song song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCurrent = ref.watch(playerProvider.select((s) => s.current?.id)) == song.id;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Artwork(song.artwork, size: 52, radius: 10),
      title: Text(song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w600, color: isCurrent ? AppColors.primary : Colors.white)),
      subtitle: Text(song.artistName,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary)),
      trailing: IconButton(
        tooltip: 'More options',
        icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
        onPressed: () => showSongSheet(context, song),
      ),
    );
  }
}

class RoundPlayButton extends StatelessWidget {
  const RoundPlayButton({super.key, required this.playing, required this.onTap, this.size = 72, this.loading = false});
  final bool playing, loading;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: playing ? 'Pause' : 'Play',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
              boxShadow: [BoxShadow(color: AppColors.primary.withAlpha(110), blurRadius: 24)],
            ),
            child: loading && !playing
                ? const Padding(
                    padding: EdgeInsets.all(22),
                    child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                  )
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      key: ValueKey(playing),
                      size: size * .55,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title, message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

class LoadingState extends StatelessWidget {
  const LoadingState({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator(color: AppColors.primary));
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Something went wrong',
        message: 'Check your internet connection and try again.',
        action: FilledButton(onPressed: onRetry, child: const Text('Retry')),
      );
}

class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.builder, required this.onRetry});
  final AsyncValue<T> value;
  final Widget Function(T) builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => value.when(
        data: builder,
        loading: () => const LoadingState(),
        error: (_, __) => ErrorState(onRetry: onRetry),
      );
}

// ---------- mini player ----------
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key, this.hero = true});
  final bool hero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(playerProvider.select((s) => s.current));
    if (song == null) return const SizedBox.shrink();
    final playing = ref.watch(playerProvider.select((s) => s.playing));
    final ctl = ref.read(playerProvider.notifier);
    return GestureDetector(
      onTap: () => context.push('/player'),
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -200) context.push('/player');
      },
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -300) ctl.next();
        if (v > 300) ctl.previous();
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: ColoredBox(
              color: AppColors.surfaceVariant.withAlpha(128),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
            child: Row(children: [
              if (hero)
                Hero(tag: 'now-art', child: Artwork(song.artwork, size: 44, radius: 10))
              else
                Artwork(song.artwork, size: 44, radius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(song.artistName, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ]),
              ),
              IconButton(
                tooltip: playing ? 'Pause' : 'Play',
                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 30),
                onPressed: ctl.toggle,
              ),
              IconButton(tooltip: 'Next', icon: const Icon(Icons.skip_next_rounded, size: 28), onPressed: ctl.next),
            ]),
          ),
          const _MiniProgress(),
        ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniProgress extends ConsumerWidget {
  const _MiniProgress();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final dur = ref.watch(playerProvider.select((s) => s.duration));
    final v = dur.inMilliseconds == 0 ? 0.0 : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
    return LinearProgressIndicator(
      value: v,
      minHeight: 2,
      color: AppColors.primary,
      backgroundColor: AppColors.divider,
    );
  }
}

class MusicSlider extends ConsumerStatefulWidget {
  const MusicSlider({super.key});
  @override
  ConsumerState<MusicSlider> createState() => _MusicSliderState();
}

class _MusicSliderState extends ConsumerState<MusicSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final pos = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final dur = ref.watch(playerProvider.select((s) => s.duration));
    final max = dur.inMilliseconds <= 0 ? 1.0 : dur.inMilliseconds.toDouble();
    final value = (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, max).toDouble();
    return Column(children: [
      Slider(
        value: value,
        max: max,
        onChanged: (v) => setState(() => _drag = v),
        onChangeEnd: (v) {
          ref.read(playerProvider.notifier).seek(Duration(milliseconds: v.round()));
          setState(() => _drag = null);
        },
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(fmt(Duration(milliseconds: value.round())),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          Text(fmt(dur), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ]),
      ),
    ]);
  }
}

// ---------- sheets ----------
void showSongSheet(BuildContext context, Song song) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Consumer(builder: (ctx, ref, _) {
      final liked = ref.watch(likesProvider).contains(song.id);
      final ctl = ref.read(playerProvider.notifier);
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Artwork(song.artwork, size: 48, radius: 10),
            title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(song.artistName, style: const TextStyle(color: AppColors.textSecondary)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.playlist_play_rounded),
            title: const Text('Play next'),
            onTap: () { ctl.playNext(song); Navigator.pop(ctx); },
          ),
          ListTile(
            leading: const Icon(Icons.queue_music_rounded),
            title: const Text('Add to queue'),
            onTap: () { ctl.addToQueue(song); Navigator.pop(ctx); },
          ),
          ListTile(
            leading: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: liked ? Colors.redAccent : null),
            title: Text(liked ? 'Remove from Liked Songs' : 'Add to Liked Songs'),
            onTap: () { ref.read(likesProvider.notifier).toggle(song); Navigator.pop(ctx); },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add_rounded),
            title: const Text('Add to playlist'),
            onTap: () { Navigator.pop(ctx); _pickPlaylist(context, song); },
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: const Text('Download'),
            onTap: () { ref.read(downloadsProvider.notifier).download(song); Navigator.pop(ctx); },
          ),
          ListTile(
            leading: const Icon(Icons.person_rounded),
            title: const Text('Go to artist'),
            onTap: () { Navigator.pop(ctx); openArtist(context, song.artistName); },
          ),
        ]),
      );
    }),
  );
}

void _pickPlaylist(BuildContext context, Song song) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    builder: (ctx) => Consumer(builder: (ctx, ref, _) {
      final lists = ref.watch(userPlaylistsProvider);
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.add_rounded, color: AppColors.primary),
            title: const Text('New playlist'),
            onTap: () { Navigator.pop(ctx); showCreatePlaylist(context); },
          ),
          for (final p in lists)
            ListTile(
              leading: Artwork(p.cover, size: 44, radius: 8),
              title: Text(p.name),
              onTap: () {
                ref.read(userPlaylistsProvider.notifier).addSong(p.id, song);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added to ${p.name}')));
              },
            ),
        ]),
      );
    }),
  );
}

void showCreatePlaylist(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => _CreatePlaylistSheet(parent: context),
  );
}

class _CreatePlaylistSheet extends ConsumerStatefulWidget {
  const _CreatePlaylistSheet({required this.parent});
  final BuildContext parent;
  @override
  ConsumerState<_CreatePlaylistSheet> createState() => _CreatePlaylistSheetState();
}

class _CreatePlaylistSheetState extends ConsumerState<_CreatePlaylistSheet> {
  final _name = TextEditingController();
  final _desc = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Create playlist', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Playlist name')),
        const SizedBox(height: 12),
        TextField(controller: _desc, decoration: const InputDecoration(labelText: 'Description (optional)')),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: () {
                final name = _name.text.trim();
                if (name.isEmpty) return;
                final p = ref.read(userPlaylistsProvider.notifier).add(name, _desc.text.trim());
                final router = GoRouter.of(widget.parent);
                Navigator.pop(context);
                router.push('/playlist/${p.id}');
              },
              child: const Text('Create Playlist'),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Opens an artist page (a full-screen route, so it works from the player too).
void openArtist(BuildContext context, String name) => context.push('/artist/${Uri.encodeComponent(name)}');

/// Opens a YouTube playlist / album / podcast. [kind] is album | playlist | podcast.
void openCollection(BuildContext context, Playlist p, {String kind = 'playlist'}) {
  context.push(Uri(path: '/collection', queryParameters: {'u': p.id, 'n': p.name, 'c': p.cover, 'k': kind}).toString());
}

/// App logo (circular) used in the header and splash screen.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});
  final double size;
  @override
  Widget build(BuildContext context) => ClipOval(
        child: Image.asset('assets/icon.png', width: size, height: size, fit: BoxFit.cover),
      );
}
