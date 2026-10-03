class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artistId,
    required this.artistName,
    required this.albumId,
    required this.albumName,
    required this.artwork,
    required this.audioUrl,
    required this.duration,
  });
  final String id, title, artistId, artistName, albumId, albumName, artwork, audioUrl;
  final Duration duration;

  @override
  bool operator ==(Object other) => other is Song && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class Artist {
  const Artist({required this.id, required this.name, required this.image, required this.listeners});
  final String id, name, image, listeners;
}

class Album {
  const Album({
    required this.id,
    required this.title,
    required this.artistId,
    required this.artistName,
    required this.artwork,
    required this.year,
  });
  final String id, title, artistId, artistName, artwork;
  final int year;
}

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.description,
    required this.cover,
    required this.songIds,
  });
  final String id, name, description, cover;
  final List<String> songIds;

  Playlist copyWith({List<String>? songIds}) => Playlist(
        id: id,
        name: name,
        description: description,
        cover: cover,
        songIds: songIds ?? this.songIds,
      );
}

class LyricLine {
  const LyricLine(this.at, this.text);
  final Duration at;
  final String text;
}

class SearchResults {
  const SearchResults({
    this.songs = const [],
    this.artists = const [],
    this.albums = const [],
    this.playlists = const [],
  });
  final List<Song> songs;
  final List<Artist> artists;
  final List<Album> albums;
  final List<Playlist> playlists;
}
