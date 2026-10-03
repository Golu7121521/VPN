import 'package:flutter/material.dart';

import 'models.dart';

/// Decorative placeholder images (deterministic per seed).
String img(String seed, [int size = 500]) => 'https://picsum.photos/seed/$seed/$size';

const _featured = [
  ('Daily Mix', 'Your everyday favorites', 'top hindi songs'),
  ('Chill Vibes', 'A playlist by Musify', 'chill songs'),
  ('Workout Mix', 'Energy for your session', 'workout songs'),
  ('Party Hits', 'Turn it up', 'party songs'),
  ('Romantic', 'Songs for the heart', 'romantic hindi songs'),
  ('Fresh Release', "This week's new music", 'new songs 2026'),
  ('Discover Weekly', 'Something new for you', 'indie songs'),
  ('Lo-fi Nights', 'Calm focus beats', 'lofi songs'),
];

final featuredPlaylists = List<Playlist>.generate(
  _featured.length,
  (i) => Playlist(
    id: 'p$i',
    name: _featured[i].$1,
    description: _featured[i].$2,
    cover: img('playlist$i'),
    query: _featured[i].$3,
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

/// Sample synchronized lyrics (replace with a real lyrics API later).
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
