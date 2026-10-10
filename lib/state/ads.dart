import 'dart:async';

import 'package:flutter/material.dart';
import 'package:startapp_sdk/startapp.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum RewardResult { earned, dismissed, unavailable }

/// Interstitial (every 4 song changes) and rewarded ads, plus the "10 minutes ad-free
/// per rewarded ad" timer (saved, so it survives restarts).
/// NOTE: Start.io automatically handles return/app-open ads based on Manifest.
class AdsController {
  AdsController._();
  static final instance = AdsController._();

  static const _reward = Duration(minutes: 10);
  static const _key = 'ad_free_until';

  SharedPreferences? _prefs;
  final adFreeUntil = ValueNotifier<DateTime?>(null);
  Timer? _expiry;

  final startAppSdk = StartAppSdk();
  StartAppInterstitialAd? _interstitial;
  StartAppRewardedVideoAd? _rewarded;
  
  Completer<RewardResult>? _rewardCompleter;
  bool _rewardEarned = false;
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
    
    // TODO: Comment or set to false before production release
    startAppSdk.setTestAdsEnabled(true);

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

  // ---------- interstitial: every 4th song change ----------
  void _loadInterstitial() {
    startAppSdk.loadInterstitialAd(
      onAdHidden: () {
        _interstitial?.dispose();
        _interstitial = null;
        _loadInterstitial();
      },
      onAdNotDisplayed: () {
        _interstitial?.dispose();
        _interstitial = null;
        _loadInterstitial();
      },
    ).then((ad) {
      _interstitial = ad;
    }).onError((error, stackTrace) {
      debugPrint("Start.io Interstitial error: $error");
      _interstitial = null;
    });
  }

  void onSongChanged() {
    _changes++;
    if (_changes % 4 != 0 || adFree) return;
    
    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitial();
      return;
    }
    
    ad.show().then((shown) {
      if (!shown) {
        ad.dispose();
        _interstitial = null;
        _loadInterstitial();
      }
    }).onError((error, stackTrace) {
      ad.dispose();
      _interstitial = null;
      _loadInterstitial();
    });
  }

  // ---------- rewarded ----------
  void _loadRewarded() {
    startAppSdk.loadRewardedVideoAd(
      onVideoCompleted: () {
        _rewardEarned = true;
      },
      onAdHidden: () {
        if (_rewardCompleter != null && !_rewardCompleter!.isCompleted) {
          _rewardCompleter!.complete(_rewardEarned ? RewardResult.earned : RewardResult.dismissed);
        }
        _rewarded?.dispose();
        _rewarded = null;
        _loadRewarded();
      },
      onAdNotDisplayed: () {
        if (_rewardCompleter != null && !_rewardCompleter!.isCompleted) {
          _rewardCompleter!.complete(RewardResult.unavailable);
        }
        _rewarded?.dispose();
        _rewarded = null;
        _loadRewarded();
      }
    ).then((ad) {
      _rewarded = ad;
    }).onError((error, stackTrace) {
      debugPrint("Start.io Rewarded error: $error");
      _rewarded = null;
    });
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
    
    _rewardCompleter = Completer<RewardResult>();
    _rewardEarned = false;
    
    ad.show().then((shown) {
      if (!shown && !_rewardCompleter!.isCompleted) {
        _rewardCompleter!.complete(RewardResult.unavailable);
        _rewarded?.dispose();
        _rewarded = null;
        _loadRewarded();
      }
    }).onError((error, stackTrace) {
      if (!_rewardCompleter!.isCompleted) {
        _rewardCompleter!.complete(RewardResult.unavailable);
      }
      _rewarded?.dispose();
      _rewarded = null;
      _loadRewarded();
    });
    
    return _rewardCompleter!.future;
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
  StartAppBannerAd? _ad;
  final startAppSdk = StartAppSdk();

  @override
  void initState() {
    super.initState();
    startAppSdk.loadBannerAd(StartAppBannerType.BANNER).then((bannerAd) {
      if (mounted) {
        setState(() => _ad = bannerAd);
      }
    }).onError((error, stackTrace) {
      debugPrint("Start.io Banner error: $error");
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: AdsController.instance.adFreeUntil,
      builder: (_, __, ___) {
        if (AdsController.instance.adFree || _ad == null) {
          return widget.fallback ?? const SizedBox.shrink();
        }
        return SizedBox(
          child: StartAppBanner(_ad!),
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
