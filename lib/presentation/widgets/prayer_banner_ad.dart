import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class PrayerBannerAd extends StatefulWidget {
  final String adUnitId;
  const PrayerBannerAd({super.key, required this.adUnitId});

  @override
  State<PrayerBannerAd> createState() => _PrayerBannerAdState();
}

class _PrayerBannerAdState extends State<PrayerBannerAd> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBanner());
  }

  Future<void> _loadBanner() async {
    final ad = BannerAd(
      size: AdSize.banner,
      adUnitId: widget.adUnitId,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad as BannerAd;
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('❌ Failed to load banner ad: $error');
        },
      ),
      request: const AdRequest(),
    );

    try {
      await ad.load();
    } catch (error) {
      ad.dispose();
      debugPrint('Banner ads are unavailable on this platform: $error');
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
