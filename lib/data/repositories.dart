import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'models.dart';

class AudioSrc {
  const AudioSrc(this.url, this.method);
  final String url;
  final String method; // progressive | hls | dash | file
}

/// Screens depend only on this interface.
abstract class MusicRepository {
  Future<List<Song>> songs(String query, {String filter});
  Future<List<Playlist>> playlists(String query, {String filter});
  Future<List<Artist>> artists(String query);
  Future<Playlist> playlistDetails(String url);
  Future<Song> songFromUrl(String url);
  Future<List<AudioSrc>> audioSources(Song song);
  Future<List<String>> suggestions(String query);
  Future<String?> artistImage(String name);
  Future<List<LyricLine>> lyrics(Song song);
}

/// Real YouTube Music data through NewPipeExtractor (Android channel) + LRCLIB lyrics.
class NewPipeMusicRepository implements MusicRepository {
  static const _ch = MethodChannel('roxyfy/newpipe');
  final _sources = <String, ({List<AudioSrc> list, DateTime at})>{};
  final _artistImages = <String, String?>{};

  Future<List<Map<String, dynamic>>> _raw(String q, String filter) async {
    final raw = await _ch.invokeMethod<List<dynamic>>('search', {'query': q, 'filter': filter}) ?? const [];
    return [for (final e in raw) Map<String, dynamic>.from(e as Map)];
  }

  Song _song(Map<String, dynamic> m) {
    final artist = (m['artist'] as String?) ?? '';
    return Song(
      id: m['url'] as String,
      title: m['title'] as String,
      artistName: artist.isEmpty ? 'Unknown artist' : artist,
      artwork: (m['thumb'] as String?) ?? '',
      duration: Duration(seconds: (m['duration'] as int?) ?? 0),
    );
  }

  @override
  Future<List<Song>> songs(String query, {String filter = 'music_songs'}) async =>
      [for (final m in await _raw(query, filter)) if (m['type'] == 'stream') _song(m)];

  @override
  Future<List<Playlist>> playlists(String query, {String filter = 'music_playlists'}) async => [
        for (final m in await _raw(query, filter))
          if (m['type'] == 'playlist')
            Playlist(
              id: m['url'] as String,
              name: m['title'] as String,
              description: [
                if (((m['artist'] as String?) ?? '').isNotEmpty) m['artist'] as String,
                if (((m['count'] as int?) ?? -1) > 0) '${m['count']} songs',
              ].join(' • '),
              cover: (m['thumb'] as String?) ?? '',
            ),
      ];

  @override
  Future<List<Artist>> artists(String query) async => [
        for (final m in await _raw(query, 'music_artists'))
          if (m['type'] == 'channel')
            Artist(id: m['title'] as String, name: m['title'] as String, image: (m['thumb'] as String?) ?? '', listeners: 'Artist'),
      ];

  @override
  Future<Playlist> playlistDetails(String url) async {
    final m = Map<String, dynamic>.from(
        (await _ch.invokeMethod<Map<dynamic, dynamic>>('playlist', {'url': url}))! as Map);
    final items = [for (final e in (m['items'] as List? ?? const [])) _song(Map<String, dynamic>.from(e as Map))];
    return Playlist(
      id: url,
      name: (m['name'] as String?) ?? 'Playlist',
      description: (m['artist'] as String?) ?? '',
      cover: (m['thumb'] as String?) ?? '',
      songs: items,
    );
  }

  @override
  Future<Song> songFromUrl(String url) async {
    final m = Map<String, dynamic>.from((await _ch.invokeMethod<Map<dynamic, dynamic>>('info', {'url': url}))! as Map);
    final live = m['live'] == true;
    final s = _song(m);
    return live
        ? Song(id: s.id, title: s.title, artistName: '${s.artistName} • LIVE', artwork: s.artwork)
        : s;
  }

  Future<List<AudioSrc>> _sourcesFor(String url) async {
    final m = await _ch.invokeMapMethod<String, dynamic>('stream', {'url': url});
    final sources = [
      for (final e in (m?['sources'] as List? ?? const []))
        AudioSrc((e as Map)['url'] as String, e['method'] as String),
    ];
    
    // HTTP 206 audio/mp4 error ko fix karne ke liye WebM streams ko priority list mein upar laana
    sources.sort((a, b) {
      final aIsWebm = a.url.contains('webm') || a.url.contains('mime=audio%2Fwebm');
      final bIsWebm = b.url.contains('webm') || b.url.contains('mime=audio%2Fwebm');
      if (aIsWebm && !bIsWebm) return -1;
      if (!aIsWebm && bIsWebm) return 1;
      return 0;
    });

    return sources;
  }

  @override
  Future<List<AudioSrc>> audioSources(Song song) async {
    final c = _sources[song.id];
    if (c != null && DateTime.now().difference(c.at) < const Duration(minutes: 20)) return c.list;
    List<AudioSrc>? list;
    Object? lastError;
    // 1) the song itself; YouTube occasionally hiccups, so retry once.
    for (var attempt = 0; attempt < 2 && list == null; attempt++) {
      try {
        list = await _sourcesFor(song.id);
      } catch (e) {
        lastError = e;
        if (attempt == 0) await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    }
    // 2) the same song as a normal video result (some official audio tracks are restricted).
    if (list == null) {
      try {
        final alt = await songs('${song.title} ${song.artistName}', filter: 'videos');
        final close = alt.where((s) {
          final d = (s.duration - song.duration).inSeconds.abs();
          return song.duration == Duration.zero || d <= 20;
        }).toList();
        for (final s in [...close, ...alt].take(3)) {
          try {
            list = await _sourcesFor(s.id);
            break;
          } catch (e) {
            lastError = e;
          }
        }
      } catch (e) {
        lastError = e;
      }
    }
    // 3) a looser search (title only, no language/type filter) as a last resort.
    if (list == null) {
      try {
        final alt = await songs(song.title, filter: 'all');
        for (final s in alt.take(3)) {
          try {
            list = await _sourcesFor(s.id);
            break;
          } catch (e) {
            lastError = e;
          }
        }
      } catch (e) {
        lastError = e;
      }
    }
    if (list == null || list.isEmpty) {
      throw lastError ?? Exception('No audio stream');
    }
    _sources[song.id] = (list: list, at: DateTime.now());
    return list;
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

  // ---------- lyrics (LRCLIB: free, timestamped) ----------
  Future<dynamic> _getJson(Uri u) async {
    try {
      final c = HttpClient()
        ..userAgent = 'Roxyfy/1.0'
        ..connectionTimeout = const Duration(seconds: 8);
      final req = await c.getUrl(u);
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        await res.drain<void>();
        c.close();
        return null;
      }
      final body = await res.transform(utf8.decoder).join();
      c.close();
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<LyricLine>> lyrics(Song s) async {
    final title = s.title.replaceAll(RegExp(r'\s*[\(\[].*?[\)\]]'), '').split(' - ').first.trim();
    final artist = s.artistName.split(RegExp(r'[,&]')).first.trim();
    dynamic j = await _getJson(Uri.https('lrclib.net', '/api/get', {
      'artist_name': artist,
      'track_name': title,
      if (s.duration > Duration.zero) 'duration': '${s.duration.inSeconds}',
    }));
    if (j is! Map) {
      final r = await _getJson(Uri.https('lrclib.net', '/api/search', {'q': '$title $artist'}));
      if (r is List && r.isNotEmpty) {
        j = r.firstWhere((e) => e is Map && ((e['syncedLyrics'] as String?)?.trim().isNotEmpty ?? false),
            orElse: () => r.first);
      }
    }
    if (j is! Map) return const [];
    final synced = j['syncedLyrics'] as String?;
    if (synced != null && synced.trim().isNotEmpty) return _parseLrc(synced);
    final plain = j['plainLyrics'] as String?;
    if (plain != null && plain.trim().isNotEmpty) {
      return [
        for (final l in plain.split('\n'))
          if (l.trim().isNotEmpty) LyricLine(const Duration(milliseconds: -1), l.trim()),
      ];
    }
    return const [];
  }

  List<LyricLine> _parseLrc(String lrc) {
    final re = RegExp(r'\[(\d+):(\d+)(?:[.:](\d+))?\]');
    final out = <LyricLine>[];
    for (final line in lrc.split('\n')) {
      final ms = re.allMatches(line).toList();
      if (ms.isEmpty) continue;
      final text = line.replaceAll(re, '').trim();
      if (text.isEmpty) continue;
      for (final m in ms) {
        final frac = m[3];
        final msv = frac == null ? 0 : int.parse(frac.padRight(3, '0').substring(0, 3));
        out.add(LyricLine(Duration(minutes: int.parse(m[1]!), seconds: int.parse(m[2]!), milliseconds: msv), text));
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }
}

List<Artist> artistsFrom(List<Song> songs) {
  final seen = <String>{};
  return [
    for (final s in songs)
      if (seen.add(s.artistName)) Artist(id: s.artistName, name: s.artistName, image: s.artwork, listeners: 'Artist'),
  ];
}
