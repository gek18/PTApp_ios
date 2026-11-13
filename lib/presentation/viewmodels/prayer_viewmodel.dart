import 'dart:async';
import 'package:adhan/adhan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:prayer_times_app/data/repositories/location_repository.dart';
import 'package:prayer_times_app/data/services/notification_service.dart';

final prayerViewModelProvider = ChangeNotifierProvider<PrayerViewModel>((ref) {
  final locationRepo = ref.watch(locationRepositoryProvider);
  final notificationService = ref.watch(notificationServiceProvider);
  return PrayerViewModel(locationRepo, notificationService);
});

class PrayerViewModel extends ChangeNotifier {
  final LocationRepository _locationRepo;
  final NotificationService _notificationService;
  Timer? _timer;

  bool _isLoading = true;
  String _city = '... جاري تحديد الموقع';
  String _hijriDate = '...';
  PrayerTimes? _prayerTimes;
  Prayer _nextPrayer = Prayer.none;
  String _nextPrayerName = '...';
  Duration _timeUntilNextPrayer = Duration.zero;
  String _errorMessage = '';
  bool _disposed = false;
  DateTime? _calculatedForDate;

  bool get isLoading => _isLoading;
  String get city => _city;
  String get hijriDate => _hijriDate;
  PrayerTimes? get prayerTimes => _prayerTimes;
  Prayer get nextPrayer => _nextPrayer;
  String get nextPrayerName => _nextPrayerName;
  Duration get timeUntilNextPrayer => _timeUntilNextPrayer;
  String get errorMessage => _errorMessage;

  PrayerViewModel(this._locationRepo, this._notificationService) {
    _initialize();
  }

  Future<void> _initialize() async {
    Future.delayed(Duration.zero, () {
      _notificationService.requestPermissions();
    });

    _updateHijriDate();

    LocationData? cachedLocation;
    try {
      cachedLocation = await _locationRepo.loadCachedLocation();
    } catch (error) {
      debugPrint('Failed to load cached location: $error');
    }
    if (_disposed) return;

    if (cachedLocation != null) {
      _city = cachedLocation.city;
      _isLoading = false;
      notifyListeners();

      _calculateAndSchedule(cachedLocation.latitude, cachedLocation.longitude);

      _fetchLocation(isBackgroundCheck: true);
    } else {
      _isLoading = true;
      notifyListeners();
      await _fetchLocation();
    }
  }

  Future<void> refreshNotifications() async {
    if (_prayerTimes != null) {
      await _notificationService.scheduleAllNotifications(_prayerTimes!);
    }
  }

  Future<void> _fetchLocation({bool isBackgroundCheck = false}) async {
    if (_disposed) return;
    if (!isBackgroundCheck) {
      _isLoading = true;
      _errorMessage = '';
      notifyListeners();
    }

    try {
      final location = await _locationRepo.fetchCurrentLocation(
        oldLat: _prayerTimes?.coordinates.latitude,
        oldLon: _prayerTimes?.coordinates.longitude,
      );
      if (_disposed) return;

      final currentCoordinates = _prayerTimes?.coordinates;
      if (location.city != _city ||
          currentCoordinates == null ||
          currentCoordinates.latitude != location.latitude ||
          currentCoordinates.longitude != location.longitude) {
        _city = location.city;
        _isLoading = false;
        notifyListeners();
        _calculateAndSchedule(location.latitude, location.longitude);
      }
    } catch (e) {
      if (!_disposed && !isBackgroundCheck) {
        _city = 'حدث خطأ في تحديد الموقع';
        _errorMessage = e.toString();
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _calculateAndSchedule(double lat, double lon) async {
    if (_disposed) return;
    final coordinates = Coordinates(lat, lon);
    final params = CalculationMethod.turkey.getParameters();
    params.madhab = Madhab.shafi;
    params.highLatitudeRule = HighLatitudeRule.middle_of_the_night;
    params.adjustments = PrayerAdjustments(dhuhr: 2);

    final prayerTimes = PrayerTimes.today(coordinates, params);

    _prayerTimes = prayerTimes;
    _calculatedForDate = DateTime.now();
    notifyListeners();

    try {
      await _notificationService.scheduleAllNotifications(prayerTimes);
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to schedule prayer notifications: $error\n$stackTrace',
      );
    }

    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCountdown();
    });

    _updateCountdown();
  }

  void _updateCountdown() {
    if (_disposed) return;
    if (_prayerTimes == null) return;

    final now = DateTime.now();
    final calculated = _calculatedForDate;
    if (calculated != null &&
        (calculated.year != now.year ||
            calculated.month != now.month ||
            calculated.day != now.day)) {
      final coordinates = _prayerTimes!.coordinates;
      _calculateAndSchedule(coordinates.latitude, coordinates.longitude);
      return;
    }

    final nowInTimezone = DateTime.now();
    final nextPrayer = _prayerTimes!.nextPrayer();

    DateTime nextPrayerTime;
    String nextPrayerName;
    Prayer nextPrayerEnum;

    if (nextPrayer == Prayer.none) {
      nextPrayerName = 'الفجر';
      nextPrayerEnum = Prayer.fajr;
      nextPrayerTime = _prayerTimes!.fajr.add(const Duration(days: 1));
      _updateHijriDate();
    } else {
      nextPrayerEnum = nextPrayer;
      nextPrayerName = _getPrayerName(nextPrayer);
      nextPrayerTime = _prayerTimes!.timeForPrayer(nextPrayer)!;
    }

    _nextPrayer = nextPrayerEnum;
    _nextPrayerName = nextPrayerName;
    _timeUntilNextPrayer = nextPrayerTime.difference(nowInTimezone);

    notifyListeners();
  }

  void _updateHijriDate() {
    final hijri = HijriCalendar.now();
    _hijriDate = hijri.toFormat("dd MMMM yyyy");
    notifyListeners();
  }

  String _getPrayerName(Prayer prayer) {
    switch (prayer) {
      case Prayer.fajr:
        return 'الفجر';
      case Prayer.sunrise:
        return 'الشروق';
      case Prayer.dhuhr:
        return 'الظهر';
      case Prayer.asr:
        return 'العصر';
      case Prayer.maghrib:
        return 'المغرب';
      case Prayer.isha:
        return 'العشاء';
      default:
        return '...';
    }
  }

  String formatDuration(Duration duration) {
    if (duration.isNegative) return '00:00:00';
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(duration.inHours)}:${two(duration.inMinutes % 60)}:${two(duration.inSeconds % 60)}";
  }

  String formatTime(DateTime? time) {
    if (time == null) return '--:--';
    return DateFormat.Hm().format(time);
  }

  Prayer _getCurrentPrayer() {
    return _prayerTimes?.currentPrayer() ?? Prayer.none;
  }

  Gradient getDynamicGradient() {
    Color start;
    final end = const Color(0xFF121212);
    final current = _getCurrentPrayer();

    switch (current) {
      case Prayer.fajr:
        start = const Color(0xFF1a237e);
        break;
      case Prayer.sunrise:
        start = const Color(0xFF4a148c);
        break;
      case Prayer.dhuhr:
        start = const Color(0xFF01579b);
        break;
      case Prayer.asr:
        start = const Color(0xFFe65100);
        break;
      case Prayer.maghrib:
        start = const Color(0xFFb71c1c);
        break;
      case Prayer.isha:
      case Prayer.none:
        start = const Color(0xFF000000);
        break;
    }

    return LinearGradient(
      colors: [start.withOpacity(0.5), end],
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      stops: const [0.0, 0.7],
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
