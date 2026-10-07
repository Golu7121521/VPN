import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/mock_data.dart';
import '../data/models.dart';
import '../data/repositories.dart';
import 'audio_handler.dart';

const kUserAgent = 'Mozilla/5.0 (Windows NT 10.0; rv:128.0) Gecko/20100101 Firefox/128.0';

// ---------- infrastructure ----------
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());
final musicRepoProvider = Provider<MusicRepository>((ref) => NewPipeMusicRepository());

typedef QueryFilter = ({String q, String f});

final songsQueryProvider =
    FutureProvider.family<List<Song>, String>((ref, q) => ref.watch(musicRepoProvider).songs(q));
final songsFilterProvider = FutureProvider.family<List<Song>, QueryFilter>(
    (ref, k) => ref.watch(musicRepoProvider).songs(k.q, filter: k.f));
final playlistsFilterProvider = FutureProvider.family<List<Playlist>, QueryFilter>(
    (ref, k) => ref.watch(musicRepoProvider).playlists(k.q, filter: k.f));
final artistsSearchProvider =
    FutureProvider.family<List<Artist>, String>((ref, q) => ref.watch(musicRepoProvider).artists(q));
final playlistDetailsProvider = FutureProvider.family<Playlist, String>(
    (ref, url) => ref.watch(musicRepoProvider).playlistDetails(url));
final artistImageProvider =
    FutureProvider.family<String?, String>((ref, name) => ref.watch(musicRepoProvider).artistImage(name));
final suggestionsProvider = FutureProvider.family<List<String>, String>(
    (ref, q) => ref.watch(musicRepoProvider).suggestions(q));
final lyricsProvider =
    FutureProvider.family<List<LyricLine>, Song>((ref, s) => ref.watch(musicRepoProvider).lyrics(s));
final trendingProvider =
    FutureProvider<List<Song>>((ref) => ref.watch(songsQueryProvider('trending songs 2026').future));

// ---------- taste (favorites chosen at first launch + what you listen to) ----------
class TasteState {
  const TasteState({
    this.onboarded = false,
    this.artists = const [],
    this.langs = const [],
    this.country = '',
    this.plays = const {},
  });
  final bool onboarded;
  final List<String> artists, langs;
  final String country;
  final Map<String, int> plays;

  int get totalPlays => plays.values.fold(0, (a, b) => a + b);

  /// Every favourite artist plus the ones you actually play most (no limit).
  List<String> get topArtists {
    final score = <String, int>{for (final a in artists) a: 3};
    plays.forEach((k, v) => score[k] = (score[k] ?? 0) + v);
    final l = score.keys.toList()..sort((a, b) => score[b]!.compareTo(score[a]!));
    return l.take(60).toList();
  }

  TasteState copyWith({
    bool? onboarded,
    List<String>? artists,
    List<String>? langs,
    String? country,
    Map<String, int>? plays,
  }) =>
      TasteState(
        onboarded: onboarded ?? this.onboarded,
        artists: artists ?? this.artists,
        langs: langs ?? this.langs,
        country: country ?? this.country,
        plays: plays ?? this.plays,
      );
}

class TasteNotifier extends Notifier<TasteState> {
  @override
  TasteState build() {
    final p = ref.watch(prefsProvider);
    final plays = <String, int>{};
    try {
      (jsonDecode(p.getString('plays') ?? '{}') as Map).forEach((k, v) => plays[k as String] = v as int);
    } catch (_) {}
    return TasteState(
      onboarded: p.getBool('onboarded') ?? false,
      artists: p.getStringList('fav_artists') ?? [],
      langs: p.getStringList('fav_langs') ?? [],
      country: p.getString('country') ?? '',
      plays: plays,
    );
  }

  void setFavorites(List<String> artists, List<String> langs, String country) {
    final p = ref.read(prefsProvider);
    p.setBool('onboarded', true);
    p.setStringList('fav_artists', artists);
    p.setStringList('fav_langs', langs);
    p.setString('country', country);
    state = state.copyWith(onboarded: true, artists: artists, langs: langs, country: country);
  }

  void toggleArtist(String name) {
    final l = [...state.artists];
    if (!l.remove(name)) l.add(name);
    ref.read(prefsProvider).setStringList('fav_artists', l);
    state = state.copyWith(artists: l);
  }

  void recordPlay(String artistName) {
    final a = artistName.split(RegExp(r'[,&]')).first.trim();
    if (a.isEmpty || a == 'Unknown artist') return;
    final plays = {...state.plays, a: (state.plays[a] ?? 0) + 1};
    ref.read(prefsProvider).setString('plays', jsonEncode(plays));
    state = state.copyWith(plays: plays);
  }
}

final tasteProvider = NotifierProvider<TasteNotifier, TasteState>(TasteNotifier.new);
final topKeyProvider = Provider<String>((ref) => ref.watch(tasteProvider.select((t) => t.topArtists.join('|'))));
final langKeyProvider = Provider<String>((ref) => ref.watch(tasteProvider.select((t) => t.langs.join('|'))));
final countryProvider = Provider<String>((ref) => ref.watch(tasteProvider.select((t) => t.country)));

// ---------- personalised home feed (refreshes daily, as you listen, and on pull-to-refresh) ----------
class FeedRow {
  const FeedRow(this.title, {this.songs = const [], this.playlists = const []});
  final String title;
  final List<Song> songs;
  final List<Playlist> playlists;
}

class FeedSpec {
  const FeedSpec(this.title, this.query, {this.playlists = false});
  final String title, query;
  final bool playlists;
}

class RefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final refreshProvider = NotifierProvider<RefreshNotifier, int>(RefreshNotifier.new);

final feedSeedProvider = Provider<int>((ref) {
  final plays = ref.watch(tasteProvider.select((t) => t.totalPlays ~/ 5));
  final manual = ref.watch(refreshProvider);
  return DateTime.now().difference(DateTime(2024)).inDays * 31 + plays * 7 + manual;
});

Future<List<Song>> _safe(Future<List<Song>> f) => f.catchError((_) => <Song>[]);

List<String> _split(String key) => key.isEmpty ? <String>[] : key.split('|');

String _country(Ref ref) {
  final c = ref.watch(countryProvider);
  return c == 'Other' ? '' : c;
}

final quickPicksProvider = FutureProvider<List<Song>>((ref) async {
  final rnd = Random(ref.watch(feedSeedProvider) + 1);
  final artists = _split(ref.watch(topKeyProvider))..sort();
  final langs = _split(ref.watch(langKeyProvider))..sort();
  final country = _country(ref);
  artists.shuffle(rnd);
  langs.shuffle(rnd);
  final lists = await Future.wait([
    for (final a in artists.take(5)) _safe(ref.watch(songsQueryProvider('$a songs').future)),
    for (final l in langs.take(3)) _safe(ref.watch(songsQueryProvider('top $l songs').future)),
    if (country.isNotEmpty) _safe(ref.watch(songsQueryProvider('top songs $country').future)),
    if (artists.isEmpty && langs.isEmpty) _safe(ref.watch(trendingProvider.future)),
  ]);
  final out = <Song>[];
  final seen = <String>{};
  for (var i = 0; i < 8; i++) {
    for (final l in lists) {
      if (i < l.length && seen.add(l[i].id)) out.add(l[i]);
    }
  }
  return out.take(24).toList();
});

/// All rows of the home feed, built from every favourite artist / language / country.
/// Rows load lazily while you scroll, so a long list costs nothing up front.
final feedSpecsProvider = Provider<List<FeedSpec>>((ref) {
  final rnd = Random(ref.watch(feedSeedProvider));
  final artists = _split(ref.watch(topKeyProvider))..sort();
  final langs = _split(ref.watch(langKeyProvider))..sort();
  final c = _country(ref);
  artists.shuffle(rnd);
  langs.shuffle(rnd);
  final out = <FeedSpec>[if (c.isNotEmpty) FeedSpec('Trending in $c', 'top songs $c 2026')];
  final n = max(artists.length, langs.length);
  for (var i = 0; i < n; i++) {
    if (i < artists.length) {
      out.add(FeedSpec('More from ${artists[i]}', '${artists[i]} songs'));
      if (i.isEven) out.add(FeedSpec('Playlists for ${artists[i]} fans', '${artists[i]} playlist', playlists: true));
    }
    if (i < langs.length) {
      out.add(FeedSpec('Latest ${langs[i]} songs', 'latest ${langs[i]} songs 2026'));
      if (i.isOdd || langs.length < 3) out.add(FeedSpec('Best of ${langs[i]}', 'best ${langs[i]} songs playlist', playlists: true));
    }
  }
  if (c.isNotEmpty) out.add(FeedSpec('$c top playlists', '$c top hits playlist', playlists: true));
  out.add(const FeedSpec('Trending now', 'trending songs 2026'));
  return out;
});

const moodQueries = {
  'Romance': 'romantic',
  'Relax': 'relaxing chill',
  'Feel good': 'feel good happy',
  'Party': 'party dance',
  'Energise': 'energetic pump up',
  'Sad': 'sad heartbreak',
  'Work out': 'workout gym',
  'Sleep': 'sleep calm',
  'Focus': 'focus study lofi',
};

final moodFeedProvider = FutureProvider.family<List<FeedRow>, String>((ref, mood) async {
  final langs = _split(ref.watch(langKeyProvider));
  final rows = <FeedRow>[];
  if (mood == 'Podcasts') {
    final l = langs.isEmpty ? <String>['Hindi'] : langs.take(2).toList();
    for (final lang in l) {
      try {
        final p = await ref.watch(playlistsFilterProvider((q: '$lang podcast', f: 'playlists')).future);
        if (p.isNotEmpty) rows.add(FeedRow('$lang podcasts', playlists: p));
      } catch (_) {}
      try {
        final s = await ref.watch(songsFilterProvider((q: '$lang podcast episode', f: 'videos')).future);
        if (s.isNotEmpty) rows.add(FeedRow('Latest $lang episodes', songs: s));
      } catch (_) {}
    }
    return rows;
  }
  final phrase = moodQueries[mood] ?? mood.toLowerCase();
  final queries = <(String, String)>[
    for (final l in langs.take(4)) ('$mood · $l', '$phrase $l songs'),
    (mood, '$phrase songs'),
  ];
  for (final q in queries) {
    try {
      final s = await ref.watch(songsQueryProvider(q.$2).future);
      if (s.isNotEmpty) rows.add(FeedRow(q.$1, songs: s));
    } catch (_) {}
  }
  return rows;
});

// ---------- library (saved albums, playlists, podcasts and artists) ----------
class LibraryState {
  const LibraryState({this.collections = const [], this.artists = const []});
  final List<Playlist> collections;
  final List<String> artists;
  bool hasCollection(String id) => collections.any((c) => c.id == id);
  bool hasArtist(String name) => artists.contains(name);
}

class LibraryNotifier extends Notifier<LibraryState> {
  @override
  LibraryState build() {
    final p = ref.watch(prefsProvider);
    final cols = <Playlist>[];
    for (final r in p.getStringList('saved_collections') ?? const <String>[]) {
      final m = jsonDecode(r) as Map<String, dynamic>;
      cols.add(Playlist(
        id: m['id'] as String,
        name: m['name'] as String,
        description: m['desc'] as String,
        cover: m['cover'] as String,
        kind: m['kind'] as String,
      ));
    }
    return LibraryState(collections: cols, artists: p.getStringList('saved_artists') ?? []);
  }

  void toggleCollection(Playlist c) {
    final l = [...state.collections];
    final i = l.indexWhere((e) => e.id == c.id);
    if (i >= 0) {
      l.removeAt(i);
    } else {
      l.insert(0, c);
    }
    ref.read(prefsProvider).setStringList('saved_collections', [
      for (final e in l)
        jsonEncode({'id': e.id, 'name': e.name, 'desc': e.description, 'cover': e.cover, 'kind': e.kind}),
    ]);
    state = LibraryState(collections: l, artists: state.artists);
  }

  void toggleArtist(String name) {
    final l = [...state.artists];
    if (!l.remove(name)) l.insert(0, name);
    ref.read(prefsProvider).setStringList('saved_artists', l);
    state = LibraryState(collections: state.collections, artists: l);
  }
}

final libraryProvider = NotifierProvider<LibraryNotifier, LibraryState>(LibraryNotifier.new);

// ---------- likes ----------
class Likes {
  const Likes(this.songs);
  final List<Song> songs;
  bool contains(String id) => songs.any((s) => s.id == id);
  int get length => songs.length;
}

class LikesNotifier extends Notifier<Likes> {
  @override
  Likes build() {
    final raw = ref.watch(prefsProvider).getStringList('liked_songs') ?? [];
    return Likes([for (final r in raw) Song.fromJson(jsonDecode(r) as Map<String, dynamic>)]);
  }

  void toggle(Song s) {
    final l = [...state.songs];
    final i = l.indexWhere((e) => e.id == s.id);
    if (i >= 0) {
      l.removeAt(i);
    } else {
      l.insert(0, s);
    }
    state = Likes(l);
    ref.read(prefsProvider).setStringList('liked_songs', [for (final e in l) jsonEncode(e.toJson())]);
  }
}

final likesProvider = NotifierProvider<LikesNotifier, Likes>(LikesNotifier.new);

// ---------- recent searches ----------
class RecentsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => ref.watch(prefsProvider).getStringList('recents') ?? [];

  void _save() => ref.read(prefsProvider).setStringList('recents', state);

  void add(String q) {
    state = [q, ...state.where((e) => e != q)].take(8).toList();
    _save();
  }

  void remove(String q) {
    state = state.where((e) => e != q).toList();
    _save();
  }

  void clear() {
    state = [];
    _save();
  }
}

final recentsProvider = NotifierProvider<RecentsNotifier, List<String>>(RecentsNotifier.new);

// ---------- user playlists (saved on the phone) ----------
class UserPlaylistsNotifier extends Notifier<List<Playlist>> {
  @override
  List<Playlist> build() {
    final raw = ref.watch(prefsProvider).getStringList('user_playlists') ?? [];
    return [
      for (final r in raw)
        () {
          final m = jsonDecode(r) as Map<String, dynamic>;
          return Playlist(
            id: m['id'] as String,
            name: m['name'] as String,
            description: m['desc'] as String,
            cover: m['cover'] as String,
            songs: [for (final s in (m['songs'] as List)) Song.fromJson(s as Map<String, dynamic>)],
          );
        }(),
    ];
  }

  void _save() => ref.read(prefsProvider).setStringList('user_playlists', [
        for (final p in state)
          jsonEncode({
            'id': p.id,
            'name': p.name,
            'desc': p.description,
            'cover': p.cover,
            'songs': [for (final s in p.songs) s.toJson()],
          }),
      ]);

  Playlist add(String name, String desc) {
    final p = Playlist(
      id: 'u${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      description: desc.isEmpty ? 'My playlist' : desc,
      cover: img('user${state.length}${name.length}'),
    );
    state = [p, ...state];
    _save();
    return p;
  }

  void addSong(String pid, Song s) {
    state = [
      for (final p in state)
        if (p.id == pid && !p.songs.contains(s)) p.copyWith(songs: [...p.songs, s]) else p,
    ];
    _save();
  }

  void remove(String id) {
    state = state.where((p) => p.id != id).toList();
    _save();
  }
}

final userPlaylistsProvider =
    NotifierProvider<UserPlaylistsNotifier, List<Playlist>>(UserPlaylistsNotifier.new);

// ---------- downloads (best quality audio saved on the phone) ----------
class DownloadsState {
  const DownloadsState({this.items = const [], this.progress = const {}});
  final List<({Song song, String path})> items;
  final Map<String, double> progress;

  String? pathFor(String id) {
    for (final i in items) {
      if (i.song.id == id) return i.path;
    }
    return null;
  }
}

class DownloadsNotifier extends Notifier<DownloadsState> {
  @override
  DownloadsState build() {
    final raw = ref.watch(prefsProvider).getStringList('downloads') ?? [];
    final items = <({Song song, String path})>[];
    for (final r in raw) {
      final m = jsonDecode(r) as Map<String, dynamic>;
      final path = m['p'] as String;
      if (File(path).existsSync()) items.add((song: Song.fromJson(m['s'] as Map<String, dynamic>), path: path));
    }
    return DownloadsState(items: items);
  }

  void _save() => ref.read(prefsProvider).setStringList('downloads', [
        for (final i in state.items) jsonEncode({'s': i.song.toJson(), 'p': i.path}),
      ]);

  void _progress(String id, double? v) {
    final p = {...state.progress};
    if (v == null) {
      p.remove(id);
    } else {
      p[id] = v;
    }
    state = DownloadsState(items: state.items, progress: p);
  }

  Future<void> download(Song s) async {
    if (state.pathFor(s.id) != null || state.progress.containsKey(s.id)) return;
    _progress(s.id, 0);
    File? file;
    IOSink? sink;
    final client = HttpClient()..userAgent = kUserAgent;
    try {
      final srcs = await ref.read(musicRepoProvider).audioSources(s);
      final src = srcs.firstWhere((e) => e.method == 'progressive', orElse: () => srcs.first);
      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/downloads');
      await dir.create(recursive: true);
      final ext = src.url.contains('audio%2Fwebm') ? 'webm' : 'm4a';
      file = File('${dir.path}/${s.id.hashCode.toUnsigned(32)}.$ext');
      sink = file.openWrite();
      var start = 0;
      int? total;
      const chunk = 2 * 1024 * 1024;
      while (true) {
        final req = await client.getUrl(Uri.parse(src.url));
        req.headers.set('Range', 'bytes=$start-${start + chunk - 1}');
        final res = await req.close();
        if (res.statusCode >= 400) throw Exception('HTTP ${res.statusCode}');
        final cr = res.headers.value('content-range');
        if (cr != null && cr.contains('/')) total = int.tryParse(cr.split('/').last);
        var got = 0;
        await sink.addStream(res.map((b) {
          got += b.length;
          return b;
        }));
        start += got;
        if (res.statusCode != 206) break; // server sent the whole file
        if (total != null) {
          _progress(s.id, start / total);
          if (start >= total) break;
        } else if (got < chunk) {
          break;
        }
      }
      await sink.close();
      state = DownloadsState(items: [(song: s, path: file.path), ...state.items], progress: state.progress);
      _progress(s.id, null);
      _save();
    } catch (_) {
      try {
        await sink?.close();
        file?.deleteSync();
      } catch (_) {}
      _progress(s.id, null);
      ref.read(playerProvider.notifier).reportError('Download failed. Check your connection and try again.');
    } finally {
      client.close();
    }
  }

  void remove(String id) {
    final p = state.pathFor(id);
    if (p != null) {
      try {
        File(p).deleteSync();
      } catch (_) {}
    }
    state = DownloadsState(items: state.items.where((i) => i.song.id != id).toList(), progress: state.progress);
    _save();
  }
}

final downloadsProvider = NotifierProvider<DownloadsNotifier, DownloadsState>(DownloadsNotifier.new);

// ---------- player (single global controller) ----------
enum RepeatKind { off, all, one }

class PlayerStatus {
  const PlayerStatus({
    this.queue = const [],
    this.index = 0,
    this.playing = false,
    this.loading = false,
    this.shuffle = false,
    this.repeat = RepeatKind.off,
    this.duration = Duration.zero,
    this.history = const [],
    this.error,
    this.openCount = 0,
    this.sleepLabel,
  });
  final int openCount;
  final List<Song> queue;
  final int index;
  final bool playing, loading, shuffle;
  final RepeatKind repeat;
  final Duration duration;
  final List<Song> history;
  final String? error, sleepLabel;

  Song? get current => index >= 0 && index < queue.length ? queue[index] : null;

  PlayerStatus copyWith({
    List<Song>? queue,
    int? index,
    bool? playing,
    bool? loading,
    bool? shuffle,
    RepeatKind? repeat,
    Duration? duration,
    List<Song>? history,
    String? error,
    int? openCount,
    String? sleepLabel,
    bool clearError = false,
    bool clearSleep = false,
  }) =>
      PlayerStatus(
        queue: queue ?? this.queue,
        index: index ?? this.index,
        playing: playing ?? this.playing,
        loading: loading ?? this.loading,
        shuffle: shuffle ?? this.shuffle,
        repeat: repeat ?? this.repeat,
        duration: duration ?? this.duration,
        history: history ?? this.history,
        error: clearError ? null : (error ?? this.error),
        openCount: openCount ?? this.openCount,
        sleepLabel: clearSleep ? null : (sleepLabel ?? this.sleepLabel),
      );
}

class PlayerNotifier extends Notifier<PlayerStatus> {
  late final AudioPlayer _p;
  final _rng = Random();
  Timer? _sleepTimer;
  bool _sleepAtEnd = false;
  int _token = 0;
  bool _resolving = false;
  bool _completedHandled = false;

  Stream<Duration> get positionStream => _p.positionStream;

  @override
  PlayerStatus build() {
    _p = AudioPlayer(userAgent: kUserAgent);
    final h = audioHandler;
    if (h != null) {
      h.onPlay = () => _p.play();
      h.onPause = () => _p.pause();
      h.onNext = next;
      h.onPrev = previous;
      h.onSeek = seek;
      h.onStop = () => clearQueue();
    }
    listenSelf((prev, next) {
      final hh = audioHandler;
      final song = next.current;
      if (hh == null || song == null) return;
      if (prev?.current != song || prev?.duration != next.duration) hh.show(song, next.duration);
      if (prev?.playing != next.playing || prev?.loading != next.loading || prev?.current != song) {
        hh.sync(playing: next.playing, loading: next.loading, position: _p.position);
      }
    });
    final subs = <StreamSubscription<Object?>>[
      _p.playerStateStream.listen((s) {
        final done = s.processingState == ProcessingState.completed;
        state = state.copyWith(
          playing: s.playing && !done,
          loading: _resolving ||
              s.processingState == ProcessingState.loading ||
              s.processingState == ProcessingState.buffering,
        );
        if (done && !_completedHandled) {
          _completedHandled = true;
          _onCompleted();
        }
      }),
      _p.durationStream.listen((d) {
        if (d != null) state = state.copyWith(duration: d);
      }),
      _p.playbackEventStream.listen((_) {}, onError: (Object e, StackTrace st) {
        state = state.copyWith(error: 'Playback error. Check your internet connection.', playing: false);
      }),
    ];
    ref.onDispose(() {
      _sleepTimer?.cancel();
      for (final s in subs) {
        s.cancel();
      }
      _p.dispose();
    });
    return const PlayerStatus();
  }

  List<Song> _hist(Song s) => [s, ...state.history.where((e) => e != s)].take(15).toList();

  void reportError(String msg) => state = state.copyWith(error: msg);

  Future<void> playQueue(List<Song> songs, int index) async {
    if (songs.isEmpty) return;
    state = state.copyWith(
        queue: songs, index: index, history: _hist(songs[index]), openCount: state.openCount + 1);
    await _load();
  }

  AudioSource _source(AudioSrc a) {
    final uri = Uri.parse(a.url);
    switch (a.method) {
      case 'hls':
        return HlsAudioSource(uri);
      case 'dash':
        return DashAudioSource(uri);
      default:
        return AudioSource.uri(uri);
    }
  }

  Future<void> _load() async {
    final s = state.current;
    if (s == null) return;
    final my = ++_token;
    _completedHandled = false;
    _resolving = true;
    ref.read(tasteProvider.notifier).recordPlay(s.artistName);
    state = state.copyWith(loading: true, playing: false, duration: s.duration, clearError: true);
    var stage = 'stream';
    String? url;
    try {
      final local = ref.read(downloadsProvider).pathFor(s.id);
      final srcs = local != null
          ? [AudioSrc(Uri.file(local).toString(), 'file')]
          : (s.audioUrl.isNotEmpty ? [AudioSrc(s.audioUrl, 'progressive')] : await ref.read(musicRepoProvider).audioSources(s));
      if (my != _token) return;
      url = srcs.first.url;
      stage = 'player';
      var ok = false;
      for (final a in srcs) {
        try {
          await _p.setAudioSource(_source(a));
          ok = true;
          break;
        } catch (_) {
          if (my != _token) return;
        }
      }
      if (!ok) {
        stage = 'proxy';
        await _p.setAudioSource(_HttpStreamSource(srcs.first.url, kUserAgent));
      }
      if (my != _token) return;
      _resolving = false;
      _p.play();
    } catch (e) {
      if (my == _token) {
        _resolving = false;
        var msg = e.toString().replaceAll('\n', ' ');
        if (url != null) msg = '$msg | ${await _probe(url)}';
        state = state.copyWith(
          loading: false,
          playing: false,
          error: 'Play failed [$stage]: ${msg.length > 260 ? msg.substring(0, 260) : msg}',
        );
      }
    }
  }

  Future<String> _probe(String url) async {
    if (!url.startsWith('http')) return 'local file';
    try {
      final c = HttpClient()..userAgent = kUserAgent;
      final req = await c.getUrl(Uri.parse(url));
      req.headers.set('Range', 'bytes=0-1');
      final res = await req.close().timeout(const Duration(seconds: 10));
      await res.drain<void>();
      c.close();
      return 'probe HTTP ${res.statusCode} ${res.headers.contentType?.mimeType}';
    } catch (e) {
      return 'probe failed: $e';
    }
  }

  void _onCompleted() {
    if (_sleepAtEnd) {
      _sleepAtEnd = false;
      state = state.copyWith(playing: false, clearSleep: true);
      return;
    }
    if (state.repeat == RepeatKind.one) {
      _completedHandled = false;
      _p.seek(Duration.zero);
      _p.play();
      return;
    }
    final last = state.index + 1 >= state.queue.length;
    if (last && !state.shuffle && state.repeat == RepeatKind.off) {
      state = state.copyWith(playing: false);
      return;
    }
    next();
  }

  void _goto(int i) {
    state = state.copyWith(index: i, history: _hist(state.queue[i]));
    _load();
  }

  void toggle() => state.playing ? _p.pause() : _p.play();
  void seek(Duration d) {
    _p.seek(d);
    final s = state;
    audioHandler?.sync(playing: s.playing, loading: s.loading, position: d);
  }

  void next() {
    final n = state.queue.length;
    if (n == 0) return;
    int i;
    if (state.shuffle && n > 1) {
      do {
        i = _rng.nextInt(n);
      } while (i == state.index);
    } else {
      i = state.index + 1;
      if (i >= n) {
        if (state.repeat != RepeatKind.all) return;
        i = 0;
      }
    }
    _goto(i);
  }

  void previous() {
    final n = state.queue.length;
    if (n == 0) return;
    if (_p.position > const Duration(seconds: 3)) {
      _p.seek(Duration.zero);
      return;
    }
    var i = state.index - 1;
    if (i < 0) i = state.repeat == RepeatKind.all ? n - 1 : 0;
    _goto(i);
  }

  void skipTo(int i) => _goto(i);
  void toggleShuffle() => state = state.copyWith(shuffle: !state.shuffle);
  void cycleRepeat() => state = state.copyWith(repeat: RepeatKind.values[(state.repeat.index + 1) % 3]);

  /// Sleep timer: [d] minutes, or until the current song ends, or off.
  void setSleep(Duration? d, {bool endOfSong = false}) {
    _sleepTimer?.cancel();
    _sleepAtEnd = false;
    if (endOfSong) {
      _sleepAtEnd = true;
      state = state.copyWith(sleepLabel: 'End of song');
    } else if (d == null) {
      state = state.copyWith(clearSleep: true);
    } else {
      _sleepTimer = Timer(d, () {
        _p.pause();
        state = state.copyWith(clearSleep: true);
      });
      state = state.copyWith(sleepLabel: '${d.inMinutes} min');
    }
  }

  void playNext(Song s) {
    if (state.queue.isEmpty) {
      playQueue([s], 0);
      return;
    }
    state = state.copyWith(queue: [...state.queue]..insert(state.index + 1, s));
  }

  void addToQueue(Song s) {
    if (state.queue.isEmpty) {
      playQueue([s], 0);
      return;
    }
    state = state.copyWith(queue: [...state.queue, s]);
  }

  void move(int oldI, int newI) {
    if (newI > oldI) newI--;
    if (oldI == newI) return;
    final q = [...state.queue];
    final cur = state.current;
    q.insert(newI, q.removeAt(oldI));
    state = state.copyWith(queue: q, index: cur == null ? 0 : q.indexOf(cur));
  }

  void removeAt(int i) {
    if (i == state.index) return;
    final q = [...state.queue]..removeAt(i);
    state = state.copyWith(queue: q, index: i < state.index ? state.index - 1 : state.index);
  }

  Future<void> clearQueue() async {
    _token++;
    _resolving = false;
    await _p.stop();
    await audioHandler?.hide();
    state = PlayerStatus(history: state.history, shuffle: state.shuffle, repeat: state.repeat);
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final playerProvider = NotifierProvider<PlayerNotifier, PlayerStatus>(PlayerNotifier.new);

final positionProvider =
    StreamProvider<Duration>((ref) => ref.watch(playerProvider.notifier).positionStream);

/// Fallback source: downloads ranges with dart:io and serves them to the native player.
class _HttpStreamSource extends StreamAudioSource {
  _HttpStreamSource(this.url, this.userAgent);
  final String url, userAgent;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final c = HttpClient()..userAgent = userAgent;
    final req = await c.getUrl(Uri.parse(url));
    req.headers.set('Range', 'bytes=${start ?? 0}-${end != null ? end - 1 : ''}');
    final res = await req.close();
    if (res.statusCode >= 400) throw Exception('HTTP ${res.statusCode}');
    int? total;
    final cr = res.headers.value('content-range');
    if (cr != null && cr.contains('/')) total = int.tryParse(cr.split('/').last);
    final partial = res.statusCode == 206;
    total ??= res.contentLength > 0 && !partial ? res.contentLength : null;
    return StreamAudioResponse(
      sourceLength: total,
      contentLength: res.contentLength > 0 ? res.contentLength : null,
      offset: partial ? (start ?? 0) : 0,
      stream: res,
      contentType: res.headers.contentType?.mimeType ?? 'audio/mp4',
    );
  }
}
