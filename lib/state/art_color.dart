import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _fallback = Color(0xFF2A1B4D);

/// Picks a rich, darkened colour from the artwork so the player background follows the song.
final artColorProvider = FutureProvider.family<Color, String>((ref, url) async {
  if (url.isEmpty) return _fallback;
  try {
    final small = url.replaceFirst(RegExp(r'=(w\d+-h\d+|s\d+)'), '=w96-h96');
    final provider = ResizeImage(CachedNetworkImageProvider(small), width: 32, height: 32, allowUpscaling: true);
    final done = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      if (!done.isCompleted) done.complete(info.image);
      stream.removeListener(l);
    }, onError: (Object e, StackTrace? st) {
      if (!done.isCompleted) done.completeError(e);
      stream.removeListener(l);
    });
    stream.addListener(l);
    final img = await done.future.timeout(const Duration(seconds: 10));
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return _fallback;
    double r = 0, g = 0, b = 0, w = 0;
    for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
      final pr = data.getUint8(i), pg = data.getUint8(i + 1), pb = data.getUint8(i + 2);
      final mx = max(pr, max(pg, pb)), mn = min(pr, min(pg, pb));
      final sat = (mx - mn) / 255;
      final lum = (mx + mn) / 510;
      final wt = 0.1 + sat * 2 * (1 - (lum - .5).abs());
      r += pr * wt;
      g += pg * wt;
      b += pb * wt;
      w += wt;
    }
    final avg = Color.fromARGB(255, (r / w).round(), (g / w).round(), (b / w).round());
    final hsl = HSLColor.fromColor(avg);
    return hsl.withSaturation(hsl.saturation.clamp(.35, .85).toDouble()).withLightness(.26).toColor();
  } catch (_) {
    return _fallback;
  }
});
