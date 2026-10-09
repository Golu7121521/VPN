import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Google's official TEST ad units. Replace these (and the App ID in the manifest patch inside
/// .github/workflows/build.yml) with your own IDs when you go live.
class AdIds {
  static const appOpen = 'ca-app-pub-3940256099942544/9257395921';
  static const banner = 'ca-app-pub-3940256099942544/6300978111';
  static const interstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const rewarded = 'ca-app-pub-3940256099942544/5224354917';
}

enum RewardResult { earned, dismissed, unavailable }

/// App open, interstitial (every 4 song changes) and rewarded ads, plus the "10 minutes ad-free
/// per rewarded ad" timer (saved, so it survives restarts).
class AdsController {
  AdsController._();
  static final instance = AdsController._();

  static const _reward = Duration(minutes: 10);
  static const _key = 'ad_free_until';

  SharedPreferences? _prefs;
  final adFreeUntil = ValueNotifier<DateTime?>(null);
  Timer? _expiry;

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  bool _appOpenShown = false;
  int _changes = 0;

  bool get adFree {
    final u = adFreeUntil.value;
    return u != null && u.isAfter(DateTime.now());
  }

  Duration get remaining => adFree ? adFreeUntil.value!.difference(DateTime.now()) : Duration.zero;

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    final ms = prefs.getInt(_key);
    if (ms != null) {
      final u = DateTime.fromMillisecondsSinceEpoch(ms);
      if (u.isAfter(DateTime.now())) {
        adFreeUntil.value = u;
        _scheduleExpiry();
      }
    }
    try {
      await MobileAds.instance.initialize();
    } catch (_) {
      return;
    }
    _loadAppOpen();
    _loadInterstitial();
    _loadRewarded();
  }

  /// One rewarded ad = 10 more ad-free minutes (added on top of what is left).
  void grantAdFree() {
    final base = adFree ? adFreeUntil.value! : DateTime.now();
    final u = base.add(_reward);
    adFreeUntil.value = u;
    _prefs?.setInt(_key, u.millisecondsSinceEpoch);
    _scheduleExpiry();
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    final u = adFreeUntil.value;
    if (u == null) return;
    _expiry = Timer(u.difference(DateTime.now()) + const Duration(milliseconds: 300), () {
      adFreeUntil.value = null; // notifies banners so they come back
      _prefs?.remove(_key);
    });
  }

  // ---------- app open ----------
  void _loadAppOpen() {
    AppOpenAd.load(
      adUnitId: AdIds.appOpen,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          if (_appOpenShown || adFree) {
            ad.dispose();
            return;
          }
          _appOpenShown = true;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (a) => a.dispose(),
            onAdFailedToShowFullScreenContent: (a, e) => a.dispose(),
          );
          ad.show();
        },
        onAdFailedToLoad: (_) {},
      ),
    );
  }

  // ---------- interstitial: every 4th song change ----------
  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: AdIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (_) => _interstitial = null,
      ),
    );
  }

  void onSongChanged() {
    _changes++;
    if (_changes % 4 != 0 || adFree) return;
    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitial();
      return;
    }
    _interstitial = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        _loadInterstitial();
      },
    );
    ad.show();
  }

  // ---------- rewarded ----------
  void _loadRewarded() {
    RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewarded = ad,
        onAdFailedToLoad: (_) => _rewarded = null,
      ),
    );
  }

  /// Shows a rewarded ad. [RewardResult.unavailable] means no ad could be loaded.
  Future<RewardResult> showRewarded() async {
    if (_rewarded == null) {
      _loadRewarded();
      for (var i = 0; i < 12 && _rewarded == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    final ad = _rewarded;
    if (ad == null) return RewardResult.unavailable;
    _rewarded = null;
    final done = Completer<RewardResult>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _loadRewarded();
        if (!done.isCompleted) done.complete(earned ? RewardResult.earned : RewardResult.dismissed);
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        _loadRewarded();
        if (!done.isCompleted) done.complete(RewardResult.unavailable);
      },
    );
    ad.show(onUserEarnedReward: (view, reward) => earned = true);
    return done.future;
  }
}

/// A banner that disappears while the user is in an ad-free period. Shows [fallback] instead.
class AppBanner extends StatefulWidget {
  const AppBanner({super.key, this.fallback});
  final Widget? fallback;
  @override
  State<AppBanner> createState() => _AppBannerState();
}

class _AppBannerState extends State<AppBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ad = BannerAd(
      adUnitId: AdIds.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) => ad.dispose(),
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: AdsController.instance.adFreeUntil,
      builder: (_, __, ___) {
        if (AdsController.instance.adFree || !_loaded || _ad == null) {
          return widget.fallback ?? const SizedBox.shrink();
        }
        return SizedBox(
          width: AdSize.banner.width.toDouble(),
          height: AdSize.banner.height.toDouble(),
          child: AdWidget(ad: _ad!),
        );
      },
    );
  }
}

/// Bottom sheet behind "Remove ads": watch an ad, get 10 ad-free minutes, repeat to extend.
void showRemoveAdsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF16141F),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const _RemoveAdsSheet(),
  );
}

class _RemoveAdsSheet extends StatefulWidget {
  const _RemoveAdsSheet();
  @override
  State<_RemoveAdsSheet> createState() => _RemoveAdsSheetState();
}

class _RemoveAdsSheetState extends State<_RemoveAdsSheet> {
  Timer? _tick;
  bool _busy = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Future<void> _watch() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    final r = await AdsController.instance.showRewarded();
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (r) {
        case RewardResult.earned:
          AdsController.instance.grantAdFree();
          _msg = '+10 minutes added!';
        case RewardResult.dismissed:
          _msg = 'Watch the full ad to get ad-free time.';
        case RewardResult.unavailable:
          _msg = 'No ad is available right now. Try again in a moment.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ads = AdsController.instance;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Remove ads', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Watch one short ad and enjoy 10 minutes with no ads at all: no banners, no full-screen ads, no download ad. '
              'Watch more ads to add more time.'),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF211E2E), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Icon(ads.adFree ? Icons.timer_rounded : Icons.timer_off_outlined, color: const Color(0xFF8B5CF6)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ads.adFree ? 'Ad-free time left: ${_fmt(ads.remaining)}' : 'You are currently seeing ads',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ]),
          ),
          if (_msg != null) ...[
            const SizedBox(height: 10),
            Text(_msg!, style: const TextStyle(color: Color(0xFF9A98A8))),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _watch,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.play_circle_outline_rounded),
            label: Text(ads.adFree ? 'Watch another ad (+10 min)' : 'Watch an ad (10 min ad-free)'),
          ),
        ]),
      ),
    );
  }
}
