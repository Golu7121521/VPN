import 'dart:io';

import 'package:google_mobile_ads/google_mobile_ads.dart';

class AppOpenAdManager {
  AppOpenAd? _appOpenAd;
  DateTime? _loadTime;

  bool _isShowingAd = false;
  bool _isLoadingAd = false;

  // IMPORTANT:
  // Testing ke time Google ka TEST App Open ID use karo.
  // Publish se pehle apna real AdMob App Open Ad Unit ID lagao.
  static const bool useTestAd = true;

  static const String androidTestAdUnit =
      'ca-app-pub-3940256099942544/9257395921';

  static const String androidProductionAdUnit =
      'ca-app-pub-1021473146993515/1406283648';

  String get adUnitId {
    if (Platform.isAndroid) {
      return useTestAd
          ? androidTestAdUnit
          : androidProductionAdUnit;
    }

    throw UnsupportedError('This app is configured for Android.');
  }

  bool get isAdAvailable {
    return _appOpenAd != null && !_isExpired;
  }

  bool get _isExpired {
    if (_loadTime == null) return true;

    // Google recommends not keeping App Open ads longer than 4 hours.
    return DateTime.now().difference(_loadTime!) >=
        const Duration(hours: 4);
  }

  void loadAd() {
    if (_isLoadingAd || isAdAvailable) {
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

          print('App Open Ad loaded successfully.');
        },
        onAdFailedToLoad: (error) {
          _isLoadingAd = false;

          print('App Open Ad failed to load: $error');
        },
      ),
    );
  }

  void showAdIfAvailable() {
    if (_isShowingAd) {
      return;
    }

    if (!isAdAvailable) {
      loadAd();
      return;
    }

    final ad = _appOpenAd!;

    _appOpenAd = null;
    _loadTime = null;

    _isShowingAd = true;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        print('App Open Ad showed.');
      },

      onAdFailedToShowFullScreenContent: (ad, error) {
        print('App Open Ad failed to show: $error');

        _isShowingAd = false;

        ad.dispose();

        loadAd();
      },

      onAdDismissedFullScreenContent: (ad) {
        print('App Open Ad dismissed.');

        _isShowingAd = false;

        ad.dispose();

        // Next App Open ad ke liye preload.
        loadAd();
      },
    );

    ad.show();
  }

  void dispose() {
    _appOpenAd?.dispose();
    _appOpenAd = null;
  }
}