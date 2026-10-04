import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/mock_data.dart';
import '../data/models.dart';
import '../data/repositories.dart';

const kUserAgent = 'Mozilla/5.0 (Windows NT 10.0; rv:128.0) Gecko/20100101 Firefox/128.0';

// ---------- infrastructure ----------
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());
final musicRepoProvider = Provider<MusicRepository>((ref) => NewPipeMusicRepository());
final searchRepoProvider =
    Provider<SearchRepository>((ref) => NewPipeSearchRepository(ref.watch(musicRepoProvider)));

final songsQueryProvider =
    FutureProvider.family<List<Song>, String>((ref, q) => ref.watch(musicRepoProvider).songs(q));
final songsProvider = FutureProvider<List<Song>>((ref) => ref.watch(songsQueryProvider('trending songs').future));
final newReleasesProvider =
    FutureProvider<List<Song>>((ref) => ref.watch(songsQueryProvider('new songs 2026').future));
final recommendedProvider =
    FutureProvider<List<Song>>((ref) => ref.watch(songsQueryProvider('latest hindi songs').future));
final artistsProvider = FutureProvider<List<Artist>>((ref) async {
  final a = await ref.watch(songsProvider.future);
  final b = await ref.watch(newReleasesProvider.future);
  return artistsFrom([...a, ...b]).take(10).toList();
});
final playlistsProvider = FutureProvider<List<Playlist>>((ref) async => featuredPlaylists);
final lyricsProvider = FutureProvider.family<List<LyricLine>, String>(
    (ref, id) => ref.watch(musicRepoProvider).lyrics(id));
final searchProvider =
    FutureProvider.family<SearchResults, String>((ref, q) => ref.watch(searchRepoProvider).search(q));

// ---------- likes (full songs are stored so they survive restarts) ----------
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

// ---------- settings ----------
class SettingsNotifier extends Notifier<Map<String, Object>> {
  static const defaults = <String, Object>{
    'quality': 'High',
    'crossfade': false,
    'gapless': true,
    'normalize': true,
    'wifiOnly': true,
    'newReleases': true,
    'recs': true,
    'playlists': false,
  };

  @override
  Map<String, Object> build() {
    final p = ref.watch(prefsProvider);
    return {for (final e in defaults.entries) e.key: p.get(e.key) ?? e.value};
  }

  void set(String key, Object value) {
    state = {...state, key: value};
    final p = ref.read(prefsProvider);
    if (value is bool) {
      p.setBool(key, value);
    } else if (value is String) {
      p.setString(key, value);
    }
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, Map<String, Object>>(SettingsNotifier.new);

// ---------- user playlists (session only for now) ----------
class UserPlaylistsNotifier extends Notifier<List<Playlist>> {
  @override
  List<Playlist> build() => const [];

  Playlist add(String name, String desc) {
    final p = Playlist(
      id: 'u${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      description: desc.isEmpty ? 'My playlist' : desc,
      cover: img('user${state.length}${name.length}'),
    );
    state = [p, ...state];
    return p;
  }

  void addSong(String pid, Song s) {
    state = [
      for (final p in state)
        if (p.id == pid && !p.songs.contains(s)) p.copyWith(songs: [...p.songs, s]) else p,
    ];
  }

  void remove(String id) => state = state.where((p) => p.id != id).toList();
}

final userPlaylistsProvider =
    NotifierProvider<UserPlaylistsNotifier, List<Playlist>>(UserPlaylistsNotifier.new);

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
  });
  final List<Song> queue;
  final int index;
  final bool playing, loading, shuffle;
  final RepeatKind repeat;
  final Duration duration;
  final List<Song> history;
  final String? error;

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
    bool clearError = false,
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
      );
}

class PlayerNotifier extends Notifier<PlayerStatus> {
  late final AudioPlayer _p;
  final _rng = Random();
  int _token = 0;
  bool _resolving = false;
  bool _completedHandled = false;

  Stream<Duration> get positionStream => _p.positionStream;

  @override
  PlayerStatus build() {
    _p = AudioPlayer(userAgent: kUserAgent);
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
      for (final s in subs) {
        s.cancel();
      }
      _p.dispose();
    });
    return const PlayerStatus();
  }

  List<Song> _hist(Song s) => [s, ...state.history.where((e) => e != s)].take(15).toList();

  Future<void> playQueue(List<Song> songs, int index) async {
    if (songs.isEmpty) return;
    state = state.copyWith(queue: songs, index: index, history: _hist(songs[index]));
    await _load();
  }

  Future<void> _load() async {
    final s = state.current;
    if (s == null) return;
    final my = ++_token;
    _completedHandled = false;
    _resolving = true;
    state = state.copyWith(loading: true, playing: false, duration: s.duration, clearError: true);
    var stage = 'stream';
    String? url;
    try {
      url = s.audioUrl.isNotEmpty ? s.audioUrl : await ref.read(musicRepoProvider).streamUrl(s);
      if (my != _token) return;
      stage = 'player';
      final tag = MediaItem(
        id: s.id,
        title: s.title,
        artist: s.artistName,
        artUri: s.artwork.isEmpty ? null : Uri.parse(s.artwork),
      );
      try {
        await _p.setAudioSource(AudioSource.uri(Uri.parse(url), tag: tag));
      } catch (_) {
        if (my != _token) return;
        // ExoPlayer could not open the URL directly; fetch it ourselves and feed the bytes.
        stage = 'proxy';
        await _p.setAudioSource(_HttpStreamSource(url, kUserAgent, tag));
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
  void seek(Duration d) => _p.seek(d);

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
    state = PlayerStatus(history: state.history, shuffle: state.shuffle, repeat: state.repeat);
  }

  void clearHistory() => state = state.copyWith(history: const []);
  void clearError() => state = state.copyWith(clearError: true);
}

final playerProvider = NotifierProvider<PlayerNotifier, PlayerStatus>(PlayerNotifier.new);

final positionProvider =
    StreamProvider<Duration>((ref) => ref.watch(playerProvider.notifier).positionStream);

/// Fallback source: downloads ranges with dart:io and serves them to the native player.
class _HttpStreamSource extends StreamAudioSource {
  _HttpStreamSource(this.url, this.userAgent, MediaItem tag) : super(tag: tag);
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
