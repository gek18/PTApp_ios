import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adhan/adhan.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:hooks_riverpod/hooks_riverpod.dart';

final notificationServiceProvider = Provider((ref) => NotificationService());

const String kPrayerVoiceKey = 'prayer_voice_key';
const String kPreFajrReminderEnabled = 'pre_fajr_reminder_enabled';

class NotificationService {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void>? _initializing;
  final Map<String, Future<void>> _iosSoundPreparations = {};

  Future<void> _initializeNotifications() async {
    if (_isInitialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    _initializing ??= () async {
      await flutterLocalNotificationsPlugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (response) {
          developer.log('Notification tapped: ${response.payload}');
        },
      );

      if (Platform.isAndroid) {
        await _createAndroidChannels();
      }

      _isInitialized = true;
    }();

    try {
      await _initializing;
    } catch (_) {
      _initializing = null;
      rethrow;
    }
    developer.log('✅ NotificationService initialized');
  }

  static const List<String> _muezzinRawSounds = [
    'yasir',
    'naseer',
    'mishary',
    'abdulbasit',
    'mekkah',
    'notification',
  ];

  Future<void> _createAndroidChannels() async {
    final android =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (android == null) return;

    for (final sound in _muezzinRawSounds) {
      final channel = AndroidNotificationChannel(
        'prayer_channel_$sound',
        'أذان/تنبيه (${sound.toUpperCase()})',
        description: 'تنبيهات الصلاة بصوت $sound',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(sound),
      );
      await android.createNotificationChannel(channel);
    }

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'prayer_reminder_channel',
        'تذكيرات الصلاة',
        description: 'تنبيهات بدون صوت مخصص',
        importance: Importance.high,
      ),
    );
  }

  Future<bool> ensureExactAlarmsEnabled() async {
    if (!Platform.isAndroid) return true;

    final android =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;

    try {
      return await android.canScheduleExactNotifications() ?? false;
    } catch (e) {
      developer.log('⚠️ Exact alarm permission error: $e');
      return false;
    }
  }

  Future<bool> areNotificationsEnabled() async {
    try {
      await _ensureInitialized();
      if (Platform.isAndroid) {
        final android = flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (android != null) {
          return await android.areNotificationsEnabled() ?? true;
        }
      }

      final ios =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        return (await ios.checkPermissions())?.isEnabled ?? false;
      }

      return true;
    } catch (e) {
      developer.log('⚠️ areNotificationsEnabled error: $e');
      return true;
    }
  }

  Future<bool> requestPermissions() async {
    try {
      await _ensureInitialized();
      if (Platform.isAndroid) {
        final android = flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (android != null) {
          final granted = await android.requestNotificationsPermission();
          return granted ?? true;
        }
        return true;
      }

      final ios =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final result = await ios.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return result ?? false;
      }

      final mac =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>();
      if (mac != null) {
        final result = await mac.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return result ?? false;
      }

      return true;
    } catch (e) {
      developer.log('⚠️ requestPermissions error: $e');
      return false;
    }
  }

  Future<void> showImmediateNotification({
    required String title,
    required String body,
    required int id,
    String? soundFileName,
  }) async {
    await _ensureInitialized();
    final iosSound = _iosSoundName(soundFileName);
    if (Platform.isIOS) await _prepareIosNotificationSound(iosSound);

    AndroidNotificationDetails? androidDetails;
    DarwinNotificationDetails? iosDetails;

    if (Platform.isAndroid) {
      final raw = soundFileName != null ? _rawName(soundFileName) : null;
      final channelId =
          raw != null ? 'prayer_channel_$raw' : 'prayer_reminder_channel';

      androidDetails = AndroidNotificationDetails(
        channelId,
        'مواقيت الصلاة',
        importance: Importance.max,
        priority: Priority.high,
        playSound: raw != null,
        sound: raw != null ? RawResourceAndroidNotificationSound(raw) : null,
      );

      iosDetails = const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      );
    } else if (Platform.isIOS) {
      iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        sound: iosSound,
      );
    } else {
      iosDetails = const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      );
    }

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await flutterLocalNotificationsPlugin.show(id, title, body, details);
  }

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) await _initializeNotifications();
  }

  Future<void> _schedulePrayerNotification({
    required DateTime scheduledTime,
    required String title,
    required String body,
    required int id,
    required String soundFileName,
    required bool exactAlarmsAllowed,
    bool isSilent = false,
  }) async {
    await _ensureInitialized();

    if (!scheduledTime.isAfter(DateTime.now())) {
      return;
    }

    final iosSound = _iosSoundName(soundFileName);
    if (Platform.isIOS && !isSilent) {
      await _prepareIosNotificationSound(iosSound);
    }

    final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);

    if (Platform.isAndroid) {
      final mode = exactAlarmsAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;

      final raw = _rawName(soundFileName);
      final channelId =
          isSilent ? 'prayer_reminder_channel' : 'prayer_channel_$raw';

      final androidDetails = AndroidNotificationDetails(
        channelId,
        isSilent ? 'تذكير' : 'أذان',
        importance: Importance.max,
        priority: Priority.high,
        playSound: !isSilent,
        sound: isSilent ? null : RawResourceAndroidNotificationSound(raw),
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      );

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
        androidScheduleMode: mode,
        matchDateTimeComponents: null,
      );
      return;
    }

    if (Platform.isIOS) {
      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentSound: !isSilent,
        sound: isSilent ? null : iosSound,
      );

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        NotificationDetails(iOS: iosDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: null,
      );
      return;
    }

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tzTime,
      const NotificationDetails(
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: null,
    );
  }

  Future<void> scheduleAllNotifications(PrayerTimes times) async {
    await _ensureInitialized();
    final prefs = await SharedPreferences.getInstance();

    final androidVoice = prefs.getString(kPrayerVoiceKey) ?? 'mishary.mp3';
    final reminderEnabled = prefs.getBool(kPreFajrReminderEnabled) ?? true;
    final exactAlarmsAllowed = await ensureExactAlarmsEnabled();

    await flutterLocalNotificationsPlugin.cancelAll();

    final prayers = {
      Prayer.fajr: 'الفجر',
      Prayer.dhuhr: 'الظهر',
      Prayer.asr: 'العصر',
      Prayer.maghrib: 'المغرب',
      Prayer.isha: 'العشاء',
    };

    final now = DateTime.now();
    // iOS allows up to 64 pending local notifications; 10 days at six per
    // day stays below that limit and keeps reminders available when the app
    // is not opened every day.
    for (var dayOffset = 0; dayOffset < 10; dayOffset++) {
      final date = DateTime(now.year, now.month, now.day + dayOffset);
      final dayTimes = dayOffset == 0
          ? times
          : PrayerTimes(
              times.coordinates,
              DateComponents.from(date),
              times.calculationParameters,
            );

      if (reminderEnabled) {
        final reminderTime =
            dayTimes.fajr.subtract(const Duration(minutes: 10));
        if (reminderTime.isAfter(now)) {
          await _schedulePrayerNotification(
            scheduledTime: reminderTime,
            title: 'تذكير قبل الفجر',
            body: 'تبقى 10 دقائق على أذان الفجر.',
            id: dayOffset * 6,
            soundFileName: 'notification.mp3',
            exactAlarmsAllowed: exactAlarmsAllowed,
          );
        }
      }

      var prayerIndex = 1;
      for (final entry in prayers.entries) {
        final prayerTime = dayTimes.timeForPrayer(entry.key);
        if (prayerTime != null && prayerTime.isAfter(now)) {
          await _schedulePrayerNotification(
            scheduledTime: prayerTime,
            title: 'حان الآن موعد ${entry.value}',
            body: 'الله أكبر، حي على الصلاة.',
            id: dayOffset * 6 + prayerIndex,
            soundFileName: androidVoice,
            exactAlarmsAllowed: exactAlarmsAllowed,
          );
        }
        prayerIndex++;
      }
    }
  }

  /// Schedules a short-lived notification so notification permission/sound
  /// can be checked immediately without waiting for a prayer time.
  Future<void> scheduleTestNotificationAfterFiveSeconds() async {
    await _ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    final selectedVoice = _rawName(
      prefs.getString(kPrayerVoiceKey) ?? 'mishary.mp3',
    );
    final iosSound = _iosSoundName('$selectedVoice.mp3');
    if (Platform.isIOS) await _prepareIosNotificationSound(iosSound);
    final scheduledAt = tz.TZDateTime.now(tz.local).add(
      const Duration(seconds: 5),
    );
    final android = Platform.isAndroid
        ? AndroidNotificationDetails(
            'prayer_channel_$selectedVoice',
            'اختبار الإشعارات',
            channelDescription: 'اختبار مؤقت لصوت الإشعارات',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            sound: RawResourceAndroidNotificationSound(selectedVoice),
          )
        : null;
    final darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: Platform.isIOS ? iosSound : null,
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      999999,
      'اختبار الإشعارات',
      'إذا ظهر هذا الإشعار، فالجدولة تعمل.',
      scheduledAt,
      NotificationDetails(android: android, iOS: darwin),
      androidScheduleMode: await ensureExactAlarmsEnabled()
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: null,
    );
  }

  Future<void> _prepareIosNotificationSound(String soundName) async {
    final preparation = _iosSoundPreparations.putIfAbsent(soundName, () async {
      final libraryDirectory = await getLibraryDirectory();
      final soundsDirectory = Directory(
        '${libraryDirectory.path}${Platform.pathSeparator}Sounds',
      );
      await soundsDirectory.create(recursive: true);
      final soundFile = File(
        '${soundsDirectory.path}${Platform.pathSeparator}$soundName',
      );
      final soundData = await rootBundle.load('assets/audio/ios/$soundName');
      if (!await soundFile.exists() ||
          await soundFile.length() != soundData.lengthInBytes) {
        await soundFile.writeAsBytes(
          soundData.buffer.asUint8List(
            soundData.offsetInBytes,
            soundData.lengthInBytes,
          ),
          flush: true,
        );
      }
    });

    try {
      await preparation;
    } catch (_) {
      _iosSoundPreparations.remove(soundName);
      rethrow;
    }
  }

  String _iosSoundName(String? soundFileName) =>
      '${_rawName(soundFileName ?? 'notification.mp3')}.caf';

  Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  String _rawName(String fileName) => fileName.split('.').first;
}
