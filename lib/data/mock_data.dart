import 'package:flutter/material.dart';

import 'models.dart';

/// Artwork placeholder images (deterministic per seed). Replace with API data later.
String img(String seed, [int size = 500]) => 'https://picsum.photos/seed/$seed/$size';

const _artistNames = [
  'Aarav Sen', 'Luna Ray', 'Kabir Rao', 'Mira Vale', 'Neon Harbor',
  'Zoya Khan', 'Midnight Oak', 'Riya Dutta', 'Echo Park', 'Vihaan',
];
const _albumTitles = [
  'Golden Hour', 'Neon Nights', 'Monsoon', 'Paper Planes', 'Skyline',
  'Wildflower', 'Afterglow', 'Velvet Roads', 'Static Hearts', 'Daybreak',
];
const _songTitles = [
  'Midnight Drive', 'Neon Skyline', 'Chai & Rain', 'Paper Planes', 'Faded Streetlights',
  'Wildflower', 'Afterglow', 'Slow Burn', 'Echoes', 'First Light',
  'Golden Hour', 'City Lullaby', 'Summer Static', 'Dancing Alone', 'Blue Hours',
  'Ocean Eyes', 'Runaway', 'Coffee Stains', 'Lost in You', 'Home Again',
];

final mockArtists = List<Artist>.generate(
  10,
  (i) => Artist(
    id: 'a$i',
    name: _artistNames[i],
    image: img('artist$i', 400),
    listeners: '${(1.2 + i * 2.3).toStringAsFixed(1)}M monthly listeners',
  ),
);

final mockAlbums = List<Album>.generate(
  10,
  (i) => Album(
    id: 'al$i',
    title: _albumTitles[i],
    artistId: 'a$i',
    artistName: _artistNames[i],
    artwork: img('cover$i'),
    year: 2016 + i,
  ),
);

final mockSongs = List<Song>.generate(20, (i) {
  final k = i % 10;
  return Song(
    id: 's$i',
    title: _songTitles[i],
    artistId: 'a$k',
    artistName: _artistNames[k],
    albumId: 'al$k',
    albumName: _albumTitles[k],
    artwork: img('cover$i'),
    audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-${i % 16 + 1}.mp3',
    duration: Duration(seconds: 190 + i * 9),
  );
});

const _playlistInfo = [
  ('Daily Mix', 'Your everyday favorites'),
  ('Chill Vibes', 'A playlist by Musify'),
  ('Workout Mix', 'Energy for your session'),
  ('Party Hits', 'Turn it up'),
  ('Romantic', 'Songs for the heart'),
  ('Fresh Release', 'This week\'s new music'),
  ('Discover Weekly', 'Something new for you'),
  ('Lo-fi Nights', 'Calm focus beats'),
];

final mockPlaylists = List<Playlist>.generate(
  8,
  (i) => Playlist(
    id: 'p$i',
    name: _playlistInfo[i].$1,
    description: _playlistInfo[i].$2,
    cover: img('playlist$i'),
    songIds: [for (var j = 0; j < 8; j++) 's${(i * 3 + j) % 20}'],
  ),
);

const _lyricText = [
  'City lights are fading slow',
  'And I can hear the radio',
  'Every road leads back to you',
  'Under skies of violet blue',
  'Hold me till the morning comes',
  'Let the night go on and on',
  'We were young and we were free',
  'Dancing in the memory',
  'Play it louder, let it ring',
  'You are all the songs I sing',
  'Stay a little while with me',
  'Music for a better me',
];

List<LyricLine> mockLyrics() => [
      for (var i = 0; i < _lyricText.length; i++) LyricLine(Duration(seconds: 6 + i * 9), _lyricText[i]),
    ];

const categories = [
  ('Hindi', Color(0xFFEF4444)), ('English', Color(0xFF3B82F6)),
  ('Punjabi', Color(0xFFF59E0B)), ('Trending', Color(0xFFEC4899)),
  ('Romance', Color(0xFFE11D48)), ('Chill', Color(0xFF14B8A6)),
  ('Party', Color(0xFF7C3AED)), ('Workout', Color(0xFFD97706)),
  ('Devotional', Color(0xFF0EA5E9)), ('Lo-fi', Color(0xFF6366F1)),
  ('Classical', Color(0xFF84CC16)), ('Indie', Color(0xFFF97316)),
];
