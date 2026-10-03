import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.musify.audio',
    androidNotificationChannelName: 'Musify playback',
    androidNotificationOngoing: true,
  );
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const MusifyApp(),
  ));
}

class MusifyApp extends StatelessWidget {
  const MusifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Musify',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: appRouter,
    );
  }
}
