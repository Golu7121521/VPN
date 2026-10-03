import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../data/mock_data.dart';
import '../data/models.dart';
import '../state/providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _c = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit(String v) {
    final q = v.trim();
    if (q.isEmpty) return;
    ref.read(recentsProvider.notifier).add(q);
    setState(() => _q = q);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Text('Search', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _c,
            textInputAction: TextInputAction.search,
            onChanged: (v) => setState(() {
              if (v.trim().isEmpty) _q = '';
            }),
            onSubmitted: _submit,
            decoration: InputDecoration(
              hintText: 'Search songs, artists, albums...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _c.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        _c.clear();
                        _q = '';
                      }),
                    ),
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _q.isEmpty ? _browse() : _results()),
      ]),
    );
  }

  Widget _browse() {
    final recents = ref.watch(recentsProvider);
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      const SectionHeader('Browse All'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 2.1,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            for (final c in categories)
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  _c.text = '${c.$1} songs';
                  _submit('${c.$1} songs');
                },
                child: Ink(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [c.$2, Color.lerp(c.$2, Colors.black, .45)!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(c.$1, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
          ],
        ),
      ),
      if (recents.isNotEmpty) ...[
        SectionHeader('Recent Searches', action: 'Clear All', onAction: ref.read(recentsProvider.notifier).clear),
        for (final r in recents)
          ListTile(
            leading: const Icon(Icons.history_rounded, color: AppColors.textSecondary),
            title: Text(r),
            trailing: IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
              onPressed: () => ref.read(recentsProvider.notifier).remove(r),
            ),
            onTap: () {
              _c.text = r;
              _submit(r);
            },
          ),
      ],
    ]);
  }

  Widget _results() {
    final ctl = ref.read(playerProvider.notifier);
    return AsyncView<SearchResults>(
      value: ref.watch(searchProvider(_q)),
      onRetry: () => ref.invalidate(searchProvider(_q)),
      builder: (r) => DefaultTabController(
        length: 3,
        child: Column(children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppColors.primary,
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textSecondary,
            dividerColor: Colors.transparent,
            tabs: [Tab(text: 'Songs'), Tab(text: 'Artists'), Tab(text: 'Playlists')],
          ),
          Expanded(
            child: TabBarView(children: [
              _list(r.songs.length, 'No songs found', (i) => SongTile(song: r.songs[i], onTap: () => ctl.playQueue(r.songs, i))),
              _list(
                r.artists.length,
                'No artists found',
                (i) => ListTile(
                  leading: Artwork(r.artists[i].image, size: 52, circle: true),
                  title: Text(r.artists[i].name),
                  subtitle: Text(r.artists[i].listeners, style: const TextStyle(color: AppColors.textSecondary)),
                  onTap: () => context.push('/artist/${Uri.encodeComponent(r.artists[i].id)}'),
                ),
              ),
              _list(
                r.playlists.length,
                'No playlists found',
                (i) => ListTile(
                  leading: Artwork(r.playlists[i].cover, size: 52, radius: 10),
                  title: Text(r.playlists[i].name),
                  subtitle: Text(r.playlists[i].description, style: const TextStyle(color: AppColors.textSecondary)),
                  onTap: () => context.push('/playlist/${r.playlists[i].id}'),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _list(int count, String empty, Widget Function(int) item) {
    if (count == 0) {
      return EmptyState(icon: Icons.search_off_rounded, title: empty, message: 'Try a different search.');
    }
    return ListView.builder(itemCount: count, itemBuilder: (_, i) => item(i));
  }
}
