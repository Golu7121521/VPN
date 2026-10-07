import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../state/providers.dart';

typedef _CountryInfo = ({List<String> langs, List<String> artists});

const _countries = <String, _CountryInfo>{
  'India': (
    langs: ['Hindi', 'English', 'Punjabi', 'Tamil', 'Telugu', 'Bengali', 'Marathi', 'Gujarati', 'Malayalam', 'Kannada', 'Haryanvi', 'Bhojpuri'],
    artists: ['Arijit Singh', 'Shreya Ghoshal', 'Neha Kakkar', 'Badshah', 'AP Dhillon', 'Diljit Dosanjh', 'Sidhu Moose Wala', 'Jubin Nautiyal', 'Darshan Raval', 'Armaan Malik', 'Sonu Nigam', 'A. R. Rahman', 'Anirudh Ravichander', 'Karan Aujla', 'Yo Yo Honey Singh', 'Pritam'],
  ),
  'Pakistan': (
    langs: ['Urdu', 'English', 'Punjabi', 'Hindi'],
    artists: ['Atif Aslam', 'Rahat Fateh Ali Khan', 'Ali Zafar', 'Asim Azhar', 'Abida Parveen', 'Nusrat Fateh Ali Khan', 'Hasan Raheem', 'Ali Sethi'],
  ),
  'Bangladesh': (
    langs: ['Bengali', 'English', 'Hindi'],
    artists: ['Tahsan', 'Arman Alif', 'Habib Wahid', 'Anupam Roy', 'Arijit Singh', 'Shreya Ghoshal'],
  ),
  'Nepal': (
    langs: ['Nepali', 'Hindi', 'English'],
    artists: ['Sugam Pokhrel', 'Pramod Kharel', 'Bipul Chettri', 'Yabesh Thapa', 'Arijit Singh'],
  ),
  'Sri Lanka': (
    langs: ['Sinhala', 'English', 'Tamil', 'Hindi'],
    artists: ['Yohani', 'Bathiya and Santhush', 'Nadeemal Perera', 'Kasun Kalhara', 'Arijit Singh'],
  ),
  'United States': (
    langs: ['English', 'Spanish'],
    artists: ['Taylor Swift', 'Drake', 'Billie Eilish', 'Ariana Grande', 'Post Malone', 'Olivia Rodrigo', 'Kendrick Lamar', 'Doja Cat'],
  ),
  'United Kingdom': (
    langs: ['English'],
    artists: ['Ed Sheeran', 'Dua Lipa', 'Adele', 'Harry Styles', 'Coldplay', 'Sam Smith', 'Stormzy', 'Arctic Monkeys'],
  ),
  'Canada': (
    langs: ['English', 'French'],
    artists: ['Justin Bieber', 'Shawn Mendes', 'Drake', 'Celine Dion', 'Avril Lavigne', 'AP Dhillon'],
  ),
  'Australia': (
    langs: ['English'],
    artists: ['The Kid LAROI', 'Sia', 'Tame Impala', 'Kylie Minogue', '5 Seconds of Summer', 'Tones and I'],
  ),
  'UAE': (
    langs: ['Arabic', 'English', 'Hindi'],
    artists: ['Amr Diab', 'Nancy Ajram', 'Fairuz', 'Mohammed Assaf', 'Balqees', 'Arijit Singh'],
  ),
  'Saudi Arabia': (
    langs: ['Arabic', 'English'],
    artists: ['Mohammed Abdu', 'Rashed Al-Majed', 'Abdulmajeed Abdullah', 'Amr Diab', 'Nancy Ajram'],
  ),
  'Egypt': (
    langs: ['Arabic', 'English'],
    artists: ['Amr Diab', 'Tamer Hosny', 'Mohamed Ramadan', 'Sherine', 'Wegz'],
  ),
  'Nigeria': (
    langs: ['English'],
    artists: ['Burna Boy', 'Wizkid', 'Davido', 'Rema', 'Tems', 'Asake', 'Ayra Starr'],
  ),
  'South Africa': (
    langs: ['English'],
    artists: ['Tyla', 'Black Coffee', 'Master KG', 'Kabza De Small', 'Nasty C'],
  ),
  'Kenya': (
    langs: ['Swahili', 'English'],
    artists: ['Sauti Sol', 'Diamond Platnumz', 'Nyashinski', 'Otile Brown', 'Khaligraph Jones'],
  ),
  'Germany': (
    langs: ['German', 'English'],
    artists: ['Rammstein', 'Helene Fischer', 'Apache 207', 'Cro', 'Tokio Hotel'],
  ),
  'France': (
    langs: ['French', 'English'],
    artists: ['Stromae', 'Aya Nakamura', 'Jul', 'Indila', 'Angèle', 'David Guetta'],
  ),
  'Spain': (
    langs: ['Spanish', 'English'],
    artists: ['Rosalía', 'C. Tangana', 'Aitana', 'Quevedo', 'Alejandro Sanz', 'Enrique Iglesias'],
  ),
  'Italy': (
    langs: ['Italian', 'English'],
    artists: ['Måneskin', 'Laura Pausini', 'Eros Ramazzotti', 'Mahmood', 'Andrea Bocelli'],
  ),
  'Brazil': (
    langs: ['Portuguese', 'English'],
    artists: ['Anitta', 'Luísa Sonza', 'Jorge & Mateus', 'Marília Mendonça', 'Ludmilla', 'Gusttavo Lima'],
  ),
  'Mexico': (
    langs: ['Spanish', 'English'],
    artists: ['Peso Pluma', 'Bad Bunny', 'Natanael Cano', 'Grupo Frontera', 'Karol G', 'Christian Nodal'],
  ),
  'Indonesia': (
    langs: ['Indonesian', 'English'],
    artists: ['Tulus', 'Raisa', 'Afgan', 'Rich Brian', 'Pamungkas', 'Dewa 19'],
  ),
  'Philippines': (
    langs: ['Tagalog', 'English'],
    artists: ['SB19', 'Moira Dela Torre', 'Ben&Ben', 'Sarah Geronimo', 'Zack Tabudlo', 'Arthur Nery'],
  ),
  'Japan': (
    langs: ['Japanese', 'English'],
    artists: ['YOASOBI', 'Kenshi Yonezu', 'Ado', 'LiSA', 'Fujii Kaze'],
  ),
  'South Korea': (
    langs: ['Korean', 'English'],
    artists: ['BTS', 'BLACKPINK', 'NewJeans', 'IU', 'Stray Kids', 'SEVENTEEN', 'aespa'],
  ),
  'China': (
    langs: ['Chinese', 'English'],
    artists: ['Jay Chou', 'Jackson Wang', 'G.E.M.', 'Jolin Tsai', 'Eason Chan'],
  ),
  'Russia': (
    langs: ['Russian', 'English'],
    artists: ['Zivert', 'Miyagi', 'Max Korzh', 'Dima Bilan', 'Little Big'],
  ),
  'Turkey': (
    langs: ['Turkish', 'English'],
    artists: ['Tarkan', 'Sezen Aksu', 'Mabel Matiz', 'Kenan Doğulu', 'Hadise'],
  ),
  'Other': (langs: ['English', 'Spanish', 'Hindi', 'French'], artists: []),
};

const _allLangs = [
  'Hindi', 'English', 'Punjabi', 'Haryanvi', 'Bhojpuri', 'Rajasthani', 'Gujarati', 'Marathi', 'Bengali', 'Tamil',
  'Telugu', 'Malayalam', 'Kannada', 'Odia', 'Assamese', 'Urdu', 'Nepali', 'Sinhala', 'Arabic', 'Spanish',
  'Portuguese', 'French', 'German', 'Italian', 'Russian', 'Turkish', 'Indonesian', 'Korean', 'Japanese',
  'Chinese', 'Swahili', 'Tagalog',
];

const _globalArtists = [
  'Taylor Swift', 'The Weeknd', 'Ed Sheeran', 'Dua Lipa', 'Bruno Mars', 'Billie Eilish', 'BTS', 'Shakira', 'Coldplay', 'Imagine Dragons',
];

/// First launch (and "Edit favorites"): pick your country, then as many languages and artists as you like.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final Set<String> _langs;
  late final Set<String> _artists;
  late String _country;
  final _extra = <String>[];
  final _search = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    final t = ref.read(tasteProvider);
    _langs = {...t.langs};
    _artists = {...t.artists};
    _country = t.country;
    _extra.addAll(t.artists);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _ready => _country.isNotEmpty && _langs.isNotEmpty && _artists.length >= 3;

  List<String> get _langOrder {
    final first = _countries[_country]?.langs ?? const <String>[];
    return [...first, ..._allLangs.where((l) => !first.contains(l))];
  }

  List<String> get _artistNames {
    final local = _countries[_country]?.artists ?? const <String>[];
    final all = <String>[...local, ..._globalArtists, ..._extra];
    return all.toSet().toList();
  }

  void _toggleArtist(String name) => setState(() {
        if (!_artists.remove(name)) _artists.add(name);
      });

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => const _CountrySheet(),
    );
    if (picked != null) setState(() => _country = picked);
  }

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

  String get _hint {
    if (_country.isEmpty) return 'Choose your country';
    if (_langs.isEmpty) return 'Pick at least 1 language';
    if (_artists.length < 3) return 'Pick ${3 - _artists.length} more artist(s)';
    return 'Continue';
  }

  @override
  Widget build(BuildContext context) {
    final results = _q.isEmpty ? null : ref.watch(artistsSearchProvider(_q));
    final names = _artistNames;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 16), children: [
              const Text('Make it yours', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Choose your country, then pick as many languages and artists as you like. Your home feed is built from them.',
                  style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              Material(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  leading: const Icon(Icons.public_rounded, color: AppColors.primary),
                  title: Text(_country.isEmpty ? 'Choose your country' : _country,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Used for trending music near you', style: TextStyle(color: AppColors.textSecondary)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _pickCountry,
                ),
              ),
              const SizedBox(height: 24),
              Text('Languages  (${_langs.length} selected)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final l in _langOrder)
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
              Text('Artists  (${_artists.length} selected, 3+)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) => setState(() => _q = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Search for any artist',
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
                    for (final a in list.take(5))
                      ListTile(
                        leading: Artwork(a.image, size: 44, circle: true),
                        title: Text(a.name),
                        trailing: Icon(_artists.contains(a.name) ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                            color: AppColors.primary),
                        onTap: () => setState(() {
                          if (!_extra.contains(a.name)) _extra.add(a.name);
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
                      ref.read(tasteProvider.notifier).setFavorites(_artists.toList(), _langs.toList(), _country);
                      context.go('/home');
                    }
                  : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: const StadiumBorder()),
              child: Text(_hint),
            ),
          ),
        ]),
      ),
    );
  }
}

class _CountrySheet extends StatefulWidget {
  const _CountrySheet();
  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  String _f = '';

  @override
  Widget build(BuildContext context) {
    final list = _countries.keys.where((c) => c.toLowerCase().contains(_f.toLowerCase())).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Your country', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (v) => setState(() => _f = v),
                decoration: InputDecoration(
                  hintText: 'Search country',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => ListTile(title: Text(list[i]), onTap: () => Navigator.pop(context, list[i])),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
