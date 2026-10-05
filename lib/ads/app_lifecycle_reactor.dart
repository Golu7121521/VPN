import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'app_open_ad_manager.dart';

class AppLifecycleReactor {
  final AppOpenAdManager appOpenAdManager;

  StreamSubscription<AppState>? _subscription;

  AppLifecycleReactor({
    required this.appOpenAdManager,
  });

  void listen() {
    AppStateEventNotifier.startListening();

    _subscription =
        AppStateEventNotifier.appStateStream.listen((state) {
      if (state == AppState.foreground) {
        appOpenAdManager.showAdIfAvailable();
      }
    });
  }

  void dispose() {
    _subscription?.cancel();
  }
}