import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../state/providers.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(downloadsProvider);
    final ctl = ref.read(playerProvider.notifier);
    final songs = [for (final i in d.items) i.song];
    final pending = d.progress.entries.toList();
    return SafeArea(
      bottom: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Downloads', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        ),
        Expanded(
          child: songs.isEmpty && pending.isEmpty
              ? const EmptyState(
                  icon: Icons.download_for_offline_rounded,
                  title: 'No downloads yet',
                  message: 'Download songs in the highest quality and play them offline.',
                )
              : ListView(padding: const EdgeInsets.only(bottom: 130), children: [
                  if (songs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => ctl.playQueue(songs, 0),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Play all'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => ctl.playQueue([...songs]..shuffle(), 0),
                            icon: const Icon(Icons.shuffle_rounded),
                            label: const Text('Shuffle'),
                          ),
                        ),
                      ]),
                    ),
                  for (final p in pending)
                    ListTile(
                      leading: const SizedBox(width: 52, height: 52, child: Center(child: Icon(Icons.downloading_rounded))),
                      title: const Text('Downloading...'),
                      subtitle: LinearProgressIndicator(value: p.value == 0 ? null : p.value, color: AppColors.primary),
                    ),
                  for (var i = 0; i < songs.length; i++)
                    ListTile(
                      onTap: () => ctl.playQueue(songs, i),
                      leading: Artwork(songs[i].artwork, size: 52, radius: 10),
                      title: Text(songs[i].title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Row(children: [
                        const Icon(Icons.download_done_rounded, size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(songs[i].artistName, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textSecondary)),
                        ),
                      ]),
                      trailing: IconButton(
                        tooltip: 'Remove download',
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textSecondary),
                        onPressed: () => ref.read(downloadsProvider.notifier).remove(songs[i].id),
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}
