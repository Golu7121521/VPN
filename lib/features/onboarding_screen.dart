import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../state/providers.dart';

/// First launch: pick at least 3 languages and 3 artists (more is fine).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _langList = [
    'Hindi', 'English', 'Punjabi', 'Haryanvi', 'Bhojpuri', 'Tamil',
    'Telugu', 'Malayalam', 'Kannada', 'Marathi', 'Bengali', 'Gujarati',
  ];
  static const _suggested = [
    'Arijit Singh', 'Shreya Ghoshal', 'Atif Aslam', 'Neha Kakkar', 'Badshah', 'AP Dhillon',
    'Diljit Dosanjh', 'Sidhu Moose Wala', 'Jubin Nautiyal', 'Darshan Raval', 'Armaan Malik', 'Sonu Nigam',
    'Taylor Swift', 'The Weeknd', 'Ed Sheeran', 'Dua Lipa',
  ];
  final _langs = <String>{};
  final _artists = <String>{};
  final _extra = <String>[];
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _ready => _langs.length >= 3 && _artists.length >= 3;

  void _toggleArtist(String name) => setState(() {
        if (!_artists.remove(name)) _artists.add(name);
      });

  Widget _artistTile(String name) {
    final on = _artists.contains(name);
    return Semantics(
      button: true,
      selected: on,
      label: name,
      child: GestureDetector(
        onTap: () => _toggleArtist(name),
        child: Column(children: [
          Expanded(
            child: LayoutBuilder(builder: (_, box) {
              final d = box.biggest.shortestSide;
              return Stack(alignment: Alignment.center, children: [
                ArtistImage(name, size: d),
                if (on)
                  Container(
                    width: d,
                    height: d,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withAlpha(150),
                      border: Border.all(color: AppColors.primary, width: 3),
                    ),
                    child: const Icon(Icons.check_rounded, size: 36),
                  ),
              ]);
            }),
          ),
          const SizedBox(height: 6),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _q.isEmpty ? null : ref.watch(artistsSearchProvider(_q));
    final names = [..._suggested, ..._extra.where((e) => !_suggested.contains(e))];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 16), children: [
              const Text('Make it yours', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Pick at least 3 languages and 3 artists. You can choose more.',
                  style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 24),
              Text('Languages  ${_langs.length}/3+', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final l in _langList)
                  FilterChip(
                    label: Text(l),
                    selected: _langs.contains(l),
                    showCheckmark: false,
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surfaceVariant,
                    side: BorderSide.none,
                    shape: const StadiumBorder(),
                    onSelected: (v) => setState(() => v ? _langs.add(l) : _langs.remove(l)),
                  ),
              ]),
              const SizedBox(height: 28),
              Text('Artists  ${_artists.length}/3+', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) => setState(() => _q = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Search for another artist',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              if (results != null)
                results.when(
                  loading: () => const Padding(padding: EdgeInsets.all(16), child: LoadingState()),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (list) => Column(children: [
                    for (final a in list.take(4))
                      ListTile(
                        leading: Artwork(a.image, size: 44, circle: true),
                        title: Text(a.name),
                        trailing: Icon(_artists.contains(a.name) ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                            color: AppColors.primary),
                        onTap: () => setState(() {
                          if (!names.contains(a.name)) _extra.add(a.name);
                          _artists.add(a.name);
                        }),
                      ),
                  ]),
                ),
              const SizedBox(height: 14),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                childAspectRatio: .78,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [for (final n in names) _artistTile(n)],
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton(
              onPressed: _ready
                  ? () {
                      ref.read(tasteProvider.notifier).setFavorites(_artists.toList(), _langs.toList());
                      context.go('/home');
                    }
                  : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: const StadiumBorder()),
              child: Text(_ready ? 'Continue' : 'Pick ${3 - _langs.length > 0 ? "${3 - _langs.length} more language(s)" : "${3 - _artists.length} more artist(s)"}'),
            ),
          ),
        ]),
      ),
    );
  }
}
