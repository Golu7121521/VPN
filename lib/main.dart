import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'state/providers.dart';

/// ===============================================================
/// APP OPEN AD MANAGER
/// ===============================================================
class AppOpenAdManager {
  AppOpenAd? _appOpenAd;

  DateTime? _loadTime;

  bool _isLoadingAd = false;
  bool _isShowingAd = false;

  /// =============================================================
  /// TEST MODE
  ///
  /// true  = Google test ad
  /// false = Your real AdMob ad
  ///
  /// Testing ke time TRUE hi rakho.
  /// =============================================================
  static const bool useTestAd = true;

  /// Google official Android App Open test ID.
  static const String androidTestAdUnit =
      'ca-app-pub-3940256099942544/9257395921';

  /// Your real App Open Ad Unit ID.
  static const String androidProductionAdUnit =
      'ca-app-pub-1021473146993515/1406283648';

  String get adUnitId {
    if (useTestAd) {
      return androidTestAdUnit;
    }

    return androidProductionAdUnit;
  }

  /// Check whether a valid ad is available.
  bool get isAdAvailable {
    if (_appOpenAd == null) {
      return false;
    }

    if (_loadTime == null) {
      return false;
    }

    // App Open ads should not be kept for too long.
    final age = DateTime.now().difference(_loadTime!);

    if (age >= const Duration(hours: 4)) {
      _appOpenAd?.dispose();
      _appOpenAd = null;
      _loadTime = null;

      return false;
    }

    return true;
  }

  /// =============================================================
  /// LOAD APP OPEN AD
  /// =============================================================
  void loadAd() {
    if (_isLoadingAd) {
      return;
    }

    if (isAdAvailable) {
      return;
    }

    _isLoadingAd = true;

    AppOpenAd.load(
      adUnitId: adUnitId,
      adRequest: const AdRequest(),

      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _isLoadingAd = false;

          _appOpenAd = ad;
          _loadTime = DateTime.now();

          debugPrint('Musify: App Open Ad loaded.');
        },

        onAdFailedToLoad: (error) {
          _isLoadingAd = false;

          debugPrint(
            'Musify: App Open Ad failed to load: $error',
          );
        },
      ),
    );
  }

  /// =============================================================
  /// SHOW APP OPEN AD
  /// =============================================================
  void showAdIfAvailable() {
    if (_isShowingAd) {
      return;
    }

    if (!isAdAvailable) {
      debugPrint(
        'Musify: App Open Ad not available yet.',
      );

      // Try loading another ad.
      loadAd();

      return;
    }

    final ad = _appOpenAd!;

    // Remove reference before showing.
    _appOpenAd = null;
    _loadTime = null;

    _isShowingAd = true;

    ad.fullScreenContentCallback =
        FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        debugPrint(
          'Musify: App Open Ad showed.',
        );
      },

      onAdFailedToShowFullScreenContent: (
        ad,
        error,
      ) {
        debugPrint(
          'Musify: App Open Ad failed to show: $error',
        );

        _isShowingAd = false;

        ad.dispose();

        // Prepare next ad.
        loadAd();
      },

      onAdDismissedFullScreenContent: (ad) {
        debugPrint(
          'Musify: App Open Ad dismissed.',
        );

        _isShowingAd = false;

        ad.dispose();

        // Load next App Open Ad.
        loadAd();
      },
    );

    ad.show();
  }

  /// Cleanup.
  void dispose() {
    _appOpenAd?.dispose();

    _appOpenAd = null;
    _loadTime = null;
  }
}

/// ===============================================================
/// APP LIFECYCLE REACTOR
/// ===============================================================
class AppLifecycleReactor {
  final AppOpenAdManager appOpenAdManager;

  StreamSubscription<AppState>? _subscription;

  AppLifecycleReactor({
    required this.appOpenAdManager,
  });

  void listen() {
    AppStateEventNotifier.startListening();

    _subscription =
        AppStateEventNotifier.appStateStream.listen(
      (state) {
        debugPrint(
          'Musify: App state = $state',
        );

        if (state == AppState.foreground) {
          appOpenAdManager.showAdIfAvailable();
        }
      },
    );
  }

  void dispose() {
    _subscription?.cancel();
  }
}

/// ===============================================================
/// MAIN
/// ===============================================================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /// -------------------------------------------------------------
  /// Initialize Google Mobile Ads
  /// -------------------------------------------------------------
  await MobileAds.instance.initialize();

  /// -------------------------------------------------------------
  /// Initialize Audio Background
  /// -------------------------------------------------------------
  await JustAudioBackground.init(
    androidNotificationChannelId:
        'com.example.musify.audio',

    androidNotificationChannelName:
        'Musify playback',

    androidNotificationOngoing: true,
  );

  /// -------------------------------------------------------------
  /// Shared Preferences
  /// -------------------------------------------------------------
  final prefs =
      await SharedPreferences.getInstance();

  /// -------------------------------------------------------------
  /// App Open Ad Manager
  /// -------------------------------------------------------------
  final appOpenAdManager =
      AppOpenAdManager();

  /// Pre-load first App Open Ad.
  appOpenAdManager.loadAd();

  /// Listen for app foreground/background events.
  final appLifecycleReactor =
      AppLifecycleReactor(
    appOpenAdManager: appOpenAdManager,
  );

  appLifecycleReactor.listen();

  /// -------------------------------------------------------------
  /// Start Flutter app
  /// -------------------------------------------------------------
  runApp(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
      ],
      child: const MusifyApp(),
    ),
  );
}

/// ===============================================================
/// MUSIFY APP
/// ===============================================================
class MusifyApp extends StatelessWidget {
  const MusifyApp({
    super.key,
  });

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