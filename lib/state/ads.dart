import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:startapp_sdk/startapp.dart';

/// Start.io (StartApp) ads, TEST mode. Before going live: set [kTestAds] to false and put your
/// own Start.io App ID in the workflow (STARTAPP_APP_ID in .github/workflows/build.yml).
const kTestAds = true;

enum RewardResult { earned, dismissed, unavailable }

/// Start.io interstitials (every 4 song changes, after the splash screen, and when you come back
/// to the app) and rewarded video, plus the "10 minutes ad-free per rewarded ad" timer
/// (saved, so it survives restarts).
class AdsController with WidgetsBindingObserver {
  AdsController._();
  static final instance = AdsController._();

  static const _reward = Duration(minutes: 10);
  static const _key = 'ad_free_until';
  static const _returnAfter = Duration(seconds: 20); // min time away to count as "returning"
  static const _cooldown = Duration(seconds: 90); // min gap between two return ads

  final StartAppSdk _sdk = StartAppSdk();
  SharedPreferences? _prefs;
  final adFreeUntil = ValueNotifier<DateTime?>(null);
  Timer? _expiry;

  StartAppInterstitialAd? _interstitial;
  Future<void>? _loading;
  Completer<void>? _closed;
  bool _showing = false;
  bool _ready = false; // set after the splash ad so a return ad never fires during start-up
  DateTime? _pausedAt;
  DateTime _lastShown = DateTime.fromMillisecondsSinceEpoch(0);
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
      _sdk.setTestAdsEnabled(kTestAds);
    } catch (_) {}
    WidgetsBinding.instance.addObserver(this);
    _preload();
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
      adFreeUntil.value = null;
      _prefs?.remove(_key);
    });
  }

  // ---------- interstitial plumbing ----------
  void _preload() {
    if (adFree) return;
    _loadInterstitial();
  }

  Future<void> _loadInterstitial() {
    if (_interstitial != null) return Future.value();
    return _loading ??= () async {
      try {
        _interstitial = await _sdk.loadInterstitialAd(
          onAdHidden: _onClosed,
          onAdNotDisplayed: _onClosed,
        );
      } catch (_) {
        _interstitial = null;
      } finally {
        _loading = null;
      }
    }();
  }

  void _onClosed() {
    _showing = false;
    _lastShown = DateTime.now();
    final c = _closed;
    _closed = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  /// Shows a full-screen interstitial and completes when it is closed. Returns false when nothing
  /// was shown. With [wait] the call also waits (up to 6 s) for the ad to finish loading.
  Future<bool> showInterstitial({bool wait = false}) async {
    if (adFree || _showing) return false;
    if (_interstitial == null) {
      final load = _loadInterstitial();
      if (!wait) return false;
      await load.timeout(const Duration(seconds: 6), onTimeout: () {});
    }
    final ad = _interstitial;
    if (ad == null) return false;
    _interstitial = null;
    _showing = true;
    final closed = _closed = Completer<void>();
    try {
      final dynamic r = (ad as dynamic).show();
      if (r is Future) {
        final v = await r;
        if (v == false) {
          _onClosed();
          return false;
        }
      }
    } catch (_) {
      _onClosed();
      return false;
    }
    await closed.future.timeout(const Duration(minutes: 3), onTimeout: _onClosed);
    try {
      (ad as dynamic).dispose();
    } catch (_) {}
    _loadInterstitial();
    return true;
  }

  // ---------- after the splash screen ----------
  Future<void> showStartupAd() async {
    try {
      await showInterstitial(wait: true);
    } finally {
      _ready = true;
    }
  }

  // ---------- every 4th song change ----------
  void onSongChanged() {
    _changes++;
    if (_changes % 4 != 0 || adFree) return;
    showInterstitial();
  }

  // ---------- return ad: shown when you come back to the app after a while ----------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (!_showing) _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final t = _pausedAt;
      _pausedAt = null;
      if (t == null || !_ready || _showing || adFree) return;
      final now = DateTime.now();
      if (now.difference(t) >= _returnAfter && now.difference(_lastShown) >= _cooldown) {
        showInterstitial();
      } else {
        _preload();
      }
    }
  }

  // ---------- rewarded ----------
  /// Shows a rewarded video. [RewardResult.unavailable] means no ad could be loaded.
  Future<RewardResult> showRewarded() async {
    if (_showing) return RewardResult.unavailable;
    final done = Completer<RewardResult>();
    var earned = false;
    _showing = true;
    void finish(RewardResult r) {
      _showing = false;
      _lastShown = DateTime.now();
      if (!done.isCompleted) done.complete(r);
    }

    try {
      final ad = await _sdk.loadRewardedVideoAd(
        onAdHidden: () => finish(earned ? RewardResult.earned : RewardResult.dismissed),
        onAdNotDisplayed: () => finish(RewardResult.unavailable),
        onVideoCompleted: () => earned = true,
      ).timeout(const Duration(seconds: 12));
      final dynamic r = (ad as dynamic).show();
      if (r is Future) {
        final v = await r;
        if (v == false) finish(RewardResult.unavailable);
      }
    } catch (_) {
      finish(RewardResult.unavailable);
    }
    return done.future.timeout(const Duration(minutes: 3), onTimeout: () {
      finish(earned ? RewardResult.earned : RewardResult.dismissed);
      return earned ? RewardResult.earned : RewardResult.dismissed;
    });
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
          const Text('Watch one short ad and enjoy 10 minutes with no ads at all: no full-screen ads between songs, '
              'no ad when you open the app and no download ad. Watch more ads to add more time.'),
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
