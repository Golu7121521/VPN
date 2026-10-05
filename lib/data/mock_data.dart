import 'package:flutter/material.dart';

/// Decorative placeholder images (deterministic per seed).
String img(String seed, [int size = 500]) => 'https://picsum.photos/seed/$seed/$size';

const categories = [
  ('Hindi', Color(0xFFEF4444)), ('English', Color(0xFF3B82F6)),
  ('Punjabi', Color(0xFFF59E0B)), ('Trending', Color(0xFFEC4899)),
  ('Romance', Color(0xFFE11D48)), ('Chill', Color(0xFF14B8A6)),
  ('Party', Color(0xFF7C3AED)), ('Workout', Color(0xFFD97706)),
  ('Devotional', Color(0xFF0EA5E9)), ('Lo-fi', Color(0xFF6366F1)),
  ('Classical', Color(0xFF84CC16)), ('Indie', Color(0xFFF97316)),
];
