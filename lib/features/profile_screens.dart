import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/models.dart';
import '../state/providers.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _soon(BuildContext c, String m) =>
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData i, String t, VoidCallback f) => ListTile(
          leading: Icon(i),
          title: Text(t),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          onTap: f,
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        const SizedBox(height: 8),
        const Center(
          child: CircleAvatar(
            radius: 48,
            backgroundColor: AppColors.primary,
            child: Icon(Icons.person_rounded, size: 52, color: Colors.white),
          ),
        ),
        const SizedBox(height: 12),
        const Center(child: Text('Rahul Sharma', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
        const Center(child: Text('rahul@example.com', style: TextStyle(color: AppColors.textSecondary))),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton(onPressed: () => _soon(context, 'Edit profile is coming soon'), child: const Text('Edit Profile')),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your Plan', style: TextStyle(color: AppColors.textSecondary)),
                Text('Free Plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ]),
            ),
            FilledButton(onPressed: () => context.go('/premium'), child: const Text('Upgrade')),
          ]),
        ),
        tile(Icons.download_rounded, 'Downloads', () => context.push('/downloads')),
        tile(Icons.history_rounded, 'Listening History', () => context.push('/history')),
        tile(Icons.settings_rounded, 'Settings', () => context.push('/settings')),
        tile(Icons.help_outline_rounded, 'Help & Support', () => _soon(context, 'Support: help@musify.app')),
        tile(Icons.logout_rounded, 'Log Out', () => context.go('/splash')),
      ]),
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final set = ref.read(settingsProvider.notifier).set;

    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(t, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
        );
    Widget sw(String key, String title) => SwitchListTile(
          value: s[key]! as bool,
          title: Text(title),
          activeColor: AppColors.primary,
          onChanged: (v) => set(key, v),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        header('Playback'),
        ListTile(
          title: const Text('Audio Quality'),
          subtitle: Text('${s['quality']}', style: const TextStyle(color: AppColors.textSecondary)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            backgroundColor: AppColors.surface,
            builder: (ctx) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final q in const ['Low', 'Normal', 'High', 'Very High'])
                  ListTile(
                    title: Text(q),
                    subtitle: Text(
                      const {'Low': '~1 MB/min', 'Normal': '~2 MB/min', 'High': '~3.5 MB/min', 'Very High': '~5 MB/min'}[q]!,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    trailing: s['quality'] == q ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                    onTap: () {
                      set('quality', q);
                      Navigator.pop(ctx);
                    },
                  ),
              ]),
            ),
          ),
        ),
        sw('crossfade', 'Crossfade'),
        sw('gapless', 'Gapless Playback'),
        sw('normalize', 'Normalize Volume'),
        header('Downloads'),
        sw('wifiOnly', 'Download over Wi-Fi only'),
        header('Notifications'),
        sw('newReleases', 'New Releases'),
        sw('recs', 'Recommendations'),
        sw('playlists', 'Playlist Updates'),
        header('Other'),
        ListTile(
          title: const Text('Clear Cache'),
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache cleared'))),
        ),
        ListTile(
          title: const Text('About'),
          onTap: () => showAboutDialog(context: context, applicationName: 'Musify', applicationVersion: '1.0.0'),
        ),
      ]),
    );
  }
}

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  bool _cleared = false;

  @override
  Widget build(BuildContext context) {
    final songs = ref.watch(songsProvider).valueOrNull ?? [];
    final hist = ref.watch(playerProvider.select((s) => s.history));
    final ctl = ref.read(playerProvider.notifier);
    final groups = <(String, List<Song>)>[
      if (!_cleared && songs.isNotEmpty) ...[
        if (hist.isNotEmpty) ('Today', hist),
        ('Yesterday', songs.skip(10).take(5).toList()),
        ('Earlier', songs.skip(15).take(5).toList()),
      ],
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Listening History'),
        actions: [
          TextButton(
            onPressed: () {
              ctl.clearHistory();
              setState(() => _cleared = true);
            },
            child: const Text('Clear', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
      body: groups.isEmpty
          ? const EmptyState(icon: Icons.history_rounded, title: 'No history', message: 'Songs you play will show up here.')
          : ListView(children: [
              for (final g in groups) ...[
                SectionHeader(g.$1),
                for (var i = 0; i < g.$2.length; i++)
                  SongTile(song: g.$2[i], onTap: () => ctl.playQueue(g.$2, i)),
              ],
            ]),
    );
  }
}

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Downloads')),
        body: const EmptyState(
          icon: Icons.download_for_offline_rounded,
          title: 'No downloads yet',
          message: 'Downloaded songs will appear here for offline listening.',
        ),
      );
}
