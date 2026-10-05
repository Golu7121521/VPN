class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artistName,
    required this.artwork,
    this.audioUrl = '',
    this.duration = Duration.zero,
  });

  /// For real songs the id is the YouTube watch URL; the stream URL is resolved on demand.
  final String id, title, artistName, artwork, audioUrl;
  final Duration duration;

  Map<String, Object> toJson() =>
      {'id': id, 't': title, 'a': artistName, 'i': artwork, 'u': audioUrl, 'd': duration.inSeconds};

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        id: j['id'] as String,
        title: j['t'] as String,
        artistName: j['a'] as String,
        artwork: j['i'] as String,
        audioUrl: j['u'] as String,
        duration: Duration(seconds: j['d'] as int),
      );

  @override
  bool operator ==(Object other) => other is Song && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class Artist {
  const Artist({required this.id, required this.name, required this.image, required this.listeners});
  final String id, name, image, listeners;
}

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.description,
    required this.cover,
    this.songs = const [],
    this.query,
  });
  final String id, name, description, cover;
  final List<Song> songs;

  /// Featured playlists are filled by searching this query.
  final String? query;

  Playlist copyWith({List<Song>? songs}) => Playlist(
        id: id,
        name: name,
        description: description,
        cover: cover,
        songs: songs ?? this.songs,
        query: query,
      );
}

class LyricLine {
  const LyricLine(this.at, this.text);
  final Duration at;
  final String text;
}
