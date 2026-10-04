import 'package:flutter/services.dart';

import 'mock_data.dart';
import 'models.dart';

/// Screens depend only on these interfaces.
abstract class MusicRepository {
  Future<List<Song>> songs(String query);
  Future<List<String>> streamUrls(Song song);
  Future<List<String>> suggestions(String query);
  Future<String?> artistImage(String name);
  Future<List<LyricLine>> lyrics(String songId);
}

abstract class SearchRepository {
  Future<SearchResults> search(String query);
}

List<Artist> artistsFrom(List<Song> songs) {
  final seen = <String>{};
  return [
    for (final s in songs)
      if (seen.add(s.artistName)) Artist(id: s.artistName, name: s.artistName, image: s.artwork, listeners: 'Artist'),
  ];
}

/// Real YouTube Music search + streams through NewPipeExtractor (Android, see MainActivity.kt).
class NewPipeMusicRepository implements MusicRepository {
  static const _ch = MethodChannel('musify/newpipe');
  final _urls = <String, ({List<String> urls, DateTime at})>{};

  @override
  Future<List<Song>> songs(String query) async {
    final raw = await _ch.invokeMethod<List<dynamic>>('search', {'query': query}) ?? const [];
    return [
      for (final e in raw)
        () {
          final m = Map<String, dynamic>.from(e as Map);
          final artist = (m['artist'] as String?) ?? '';
          return Song(
            id: m['url'] as String,
            title: m['title'] as String,
            artistName: artist.isEmpty ? 'Unknown artist' : artist,
            artwork: (m['thumb'] as String?) ?? '',
            duration: Duration(seconds: (m['duration'] as int?) ?? 0),
          );
        }(),
    ];
  }

  final _artistImages = <String, String?>{};

  @override
  Future<List<String>> streamUrls(Song song) async {
    final c = _urls[song.id];
    if (c != null && DateTime.now().difference(c.at) < const Duration(minutes: 20)) return c.urls;
    final m = await _ch.invokeMapMethod<String, dynamic>('stream', {'url': song.id});
    final urls = ((m?['audios'] as List?) ?? const []).cast<String>();
    if (urls.isEmpty) throw Exception('No audio stream');
    _urls[song.id] = (urls: urls, at: DateTime.now());
    return urls;
  }

  @override
  Future<List<String>> suggestions(String query) async {
    final r = await _ch.invokeMethod<List<dynamic>>('suggest', {'query': query}) ?? const [];
    return r.cast<String>();
  }

  @override
  Future<String?> artistImage(String name) async {
    if (_artistImages.containsKey(name)) return _artistImages[name];
    try {
      final r = await _ch.invokeMethod<String>('artistImage', {'name': name});
      _artistImages[name] = r;
      return r;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<LyricLine>> lyrics(String songId) async => mockLyrics();
}

class NewPipeSearchRepository implements SearchRepository {
  NewPipeSearchRepository(this._music);
  final MusicRepository _music;

  @override
  Future<SearchResults> search(String query) async {
    final songs = await _music.songs(query);
    final t = query.toLowerCase();
    return SearchResults(
      songs: songs,
      artists: artistsFrom(songs),
      playlists: featuredPlaylists.where((p) => p.name.toLowerCase().contains(t)).toList(),
    );
  }
}
