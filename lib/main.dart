import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/integrity.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'state/audio_handler.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bad = await Integrity.failure();
  if (bad != null) {
    runApp(BlockedApp(code: bad));
    return;
  }
  audioHandler = await AudioService.init(
    builder: () => RoxyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.roxyfy.audio',
      androidNotificationChannelName: 'Roxyfy playback',
      androidNotificationIcon: 'drawable/ic_notification',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: true,
    ),
  );
  final prefs = await SharedPreferences.getInstance();
  // Re-check while the app runs, so a hook started later is caught too.
  Timer.periodic(const Duration(seconds: 45), (_) async {
    final b = await Integrity.failure();
    if (b != null) runApp(BlockedApp(code: b));
  });
  runApp(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const RoxyfyApp(),
  ));
}

class RoxyfyApp extends ConsumerStatefulWidget {
  const RoxyfyApp({super.key});
  @override
  ConsumerState<RoxyfyApp> createState() => _RoxyfyAppState();
}

class _RoxyfyAppState extends ConsumerState<RoxyfyApp> {
  static const _ch = MethodChannel('roxyfy/newpipe');

  // youtu.be/ID, youtube.com/watch?v=ID, /live/ID, /shorts/ID, music.youtube.com/watch?v=ID
  static final _idRe = RegExp(
      r'(?:youtu\.be/|youtube\.com/(?:watch\?(?:.*&)?v=|live/|shorts/|embed/)|music\.youtube\.com/watch\?(?:.*&)?v=)([\w-]{11})');

  @override
  void initState() {
    super.initState();
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'shared') _handleShared(call.arguments as String?);
    });
    // A share that launched the app from cold; wait until the splash screen is done.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final url = await _ch.invokeMethod<String>('initialShare');
      if (url != null) {
        await Future<void>.delayed(const Duration(milliseconds: 3200));
        _handleShared(url);
      }
    });
  }

  Future<void> _handleShared(String? text) async {
    if (text == null) return;
    final id = _idRe.firstMatch(text)?.group(1);
    final msg = appMessengerKey.currentState;
    if (id == null) {
      msg?.showSnackBar(const SnackBar(content: Text('That is not a YouTube link')));
      return;
    }
    try {
      final song = await ref.read(musicRepoProvider).songFromUrl('https://www.youtube.com/watch?v=$id');
      await ref.read(playerProvider.notifier).playQueue([song], 0);
    } catch (e) {
      msg?.showSnackBar(const SnackBar(content: Text('Could not open this video')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Roxyfy',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: appMessengerKey,
      theme: AppTheme.dark,
      routerConfig: appRouter,
    );
  }
}

final appMessengerKey = GlobalKey<ScaffoldMessengerState>();
