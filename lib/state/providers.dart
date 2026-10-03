import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/mock_data.dart';
import '../data/models.dart';
import '../data/repositories.dart';

// ---------- infrastructure ----------
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());
final musicRepoProvider = Provider<MusicRepository>((ref) => MockMusicRepository());
final searchRepoProvider = Provider<SearchRepository>((ref) => MockSearchRepository());

final songsProvider = FutureProvider<List<Song>>((ref) => ref.watch(musicRepoProvider).songs());
final artistsProvider = FutureProvider<List<Artist>>((ref) => ref.watch(musicRepoProvider).artists());
final albumsProvider = FutureProvider<List<Album>>((ref) => ref.watch(musicRepoProvider).albums());
final playlistsProvider = FutureProvider<List<Playlist>>((ref) => ref.watch(musicRepoProvider).playlists());
final lyricsProvider = FutureProvider.family<List<LyricLine>, String>(
    (ref, id) => ref.watch(musicRepoProvider).lyrics(id));
final searchProvider = FutureProvider.family<SearchResults, String>(
    (ref, q) => ref.watch(searchRepoProvider).search(q));

// ---------- likes ----------
class LikesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final p = ref.watch(prefsProvider);
    return (p.getStringList('likes') ?? ['s0', 's3', 's5', 's8', 's11']).toSet();
  }

  void toggle(String id) {
    final n = {...state};
    if (!n.remove(id)) n.add(id);
    state = n;
    ref.read(prefsProvider).setStringList('likes', n.toList());
  }
}

final likesProvider = NotifierProvider<LikesNotifier, Set<String>>(LikesNotifier.new);

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
      songIds: const [],
    );
    state = [p, ...state];
    return p;
  }

  void addSong(String pid, String sid) {
    state = [
      for (final p in state)
        if (p.id == pid && !p.songIds.contains(sid)) p.copyWith(songIds: [...p.songIds, sid]) else p,
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
  ConcatenatingAudioSource? _src;

  Stream<Duration> get positionStream => _p.positionStream;

  @override
  PlayerStatus build() {
    _p = AudioPlayer();
    final subs = <StreamSubscription<Object?>>[
      _p.playerStateStream.listen((s) {
        state = state.copyWith(
          playing: s.playing && s.processingState != ProcessingState.completed,
          loading: s.processingState == ProcessingState.loading ||
              s.processingState == ProcessingState.buffering,
        );
      }),
      _p.durationStream.listen((d) => state = state.copyWith(duration: d ?? Duration.zero)),
      _p.currentIndexStream.listen((i) {
        if (i != null && i != state.index && i < state.queue.length) {
          state = state.copyWith(index: i, history: _hist(state.queue[i]));
        }
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

  AudioSource _toSource(Song s) => AudioSource.uri(
        Uri.parse(s.audioUrl),
        tag: MediaItem(
          id: s.id,
          title: s.title,
          artist: s.artistName,
          album: s.albumName,
          artUri: Uri.parse(s.artwork),
        ),
      );

  Future<void> playQueue(List<Song> songs, int index) async {
    if (songs.isEmpty) return;
    state = state.copyWith(queue: songs, index: index, history: _hist(songs[index]), clearError: true);
    _src = ConcatenatingAudioSource(children: songs.map(_toSource).toList());
    try {
      await _p.setAudioSource(_src!, initialIndex: index, initialPosition: Duration.zero);
      _p.play();
    } catch (_) {
      state = state.copyWith(error: 'Could not play this song.', playing: false);
    }
  }

  void toggle() => state.playing ? _p.pause() : _p.play();
  void seek(Duration d) => _p.seek(d);
  void next() => _p.seekToNext();
  void previous() {
    if (_p.position > const Duration(seconds: 3)) {
      _p.seek(Duration.zero);
    } else {
      _p.seekToPrevious();
    }
  }

  Future<void> skipTo(int i) async {
    await _p.seek(Duration.zero, index: i);
    _p.play();
  }

  Future<void> toggleShuffle() async {
    final v = !state.shuffle;
    if (v) await _p.shuffle();
    await _p.setShuffleModeEnabled(v);
    state = state.copyWith(shuffle: v);
  }

  Future<void> cycleRepeat() async {
    final next = RepeatKind.values[(state.repeat.index + 1) % 3];
    await _p.setLoopMode(
        next == RepeatKind.off ? LoopMode.off : (next == RepeatKind.all ? LoopMode.all : LoopMode.one));
    state = state.copyWith(repeat: next);
  }

  Future<void> playNext(Song s) async {
    if (state.queue.isEmpty || _src == null) return playQueue([s], 0);
    final at = state.index + 1;
    await _src!.insert(at, _toSource(s));
    state = state.copyWith(queue: [...state.queue]..insert(at, s));
  }

  Future<void> addToQueue(Song s) async {
    if (state.queue.isEmpty || _src == null) return playQueue([s], 0);
    await _src!.add(_toSource(s));
    state = state.copyWith(queue: [...state.queue, s]);
  }

  Future<void> move(int oldI, int newI) async {
    if (newI > oldI) newI--;
    if (oldI == newI) return;
    final q = [...state.queue];
    final cur = state.current;
    q.insert(newI, q.removeAt(oldI));
    state = state.copyWith(queue: q, index: cur == null ? 0 : q.indexOf(cur));
    await _src?.move(oldI, newI);
  }

  Future<void> removeAt(int i) async {
    if (i == state.index) return;
    final q = [...state.queue]..removeAt(i);
    state = state.copyWith(queue: q, index: i < state.index ? state.index - 1 : state.index);
    await _src?.removeAt(i);
  }

  Future<void> clearQueue() async {
    await _p.stop();
    _src = null;
    state = PlayerStatus(history: state.history, shuffle: state.shuffle, repeat: state.repeat);
  }

  void clearHistory() => state = state.copyWith(history: const []);
  void clearError() => state = state.copyWith(clearError: true);
}

final playerProvider = NotifierProvider<PlayerNotifier, PlayerStatus>(PlayerNotifier.new);

final positionProvider = StreamProvider<Duration>(
    (ref) => ref.watch(playerProvider.notifier).positionStream);
