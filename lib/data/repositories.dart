import 'mock_data.dart';
import 'models.dart';

/// UI depends only on these interfaces. Swap the Mock* classes for API-backed
/// implementations (Dio/http) later without touching any screen.
abstract class MusicRepository {
  Future<List<Song>> songs();
  Future<List<Artist>> artists();
  Future<List<Album>> albums();
  Future<List<Playlist>> playlists();
  Future<List<LyricLine>> lyrics(String songId);
}

abstract class SearchRepository {
  Future<SearchResults> search(String query);
}

Future<T> _latency<T>(T value, [int ms = 350]) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
  return value;
}

class MockMusicRepository implements MusicRepository {
  @override
  Future<List<Song>> songs() => _latency(mockSongs);
  @override
  Future<List<Artist>> artists() => _latency(mockArtists);
  @override
  Future<List<Album>> albums() => _latency(mockAlbums);
  @override
  Future<List<Playlist>> playlists() => _latency(mockPlaylists);
  @override
  Future<List<LyricLine>> lyrics(String songId) => _latency(mockLyrics(), 200);
}

class MockSearchRepository implements SearchRepository {
  @override
  Future<SearchResults> search(String query) async {
    final t = query.toLowerCase();
    bool m(String s) => s.toLowerCase().contains(t);
    var songs = mockSongs.where((s) => m(s.title) || m(s.artistName) || m(s.albumName)).toList();
    final isCategory = categories.any((c) => c.$1.toLowerCase() == t);
    if (songs.isEmpty && isCategory) {
      final k = t.hashCode.abs() % 12;
      songs = [for (var i = 0; i < 8; i++) mockSongs[(k + i) % mockSongs.length]];
    }
    return _latency(
      SearchResults(
        songs: songs,
        artists: mockArtists.where((a) => m(a.name)).toList(),
        albums: mockAlbums.where((a) => m(a.title) || m(a.artistName)).toList(),
        playlists: mockPlaylists.where((p) => m(p.name)).toList(),
      ),
      250,
    );
  }
}
