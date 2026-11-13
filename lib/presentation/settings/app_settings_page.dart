import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prayer_times_app/data/services/notification_service.dart';
import 'dart:developer' as developer;

class AppSettingsPage extends ConsumerStatefulWidget {
  final FlutterLocalNotificationsPlugin notificationsPlugin;
  final VoidCallback? onSettingsChanged;

  const AppSettingsPage({
    super.key,
    required this.notificationsPlugin,
    this.onSettingsChanged,
  });

  @override
  ConsumerState<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends ConsumerState<AppSettingsPage> {
  final List<String> muezzins = [
    'yasir.mp3',
    'naseer.mp3',
    'mishary.mp3',
    'abdulbasit.mp3',
    'mekkah.mp3',
  ];

  final List<String> muezzinNames = [
    'ياسر الدوسري',
    'ناصر القطامي',
    'مشاري العفاسي',
    'عبد الباسط عبد الصمد',
    'أذان الحرم',
  ];

  String _selectedMuezzin = 'mishary.mp3';
  bool _preFajrReminder = true;

  bool _notificationsEnabled = true;
  bool _exactAlarmsAllowed = true;
  bool _isSchedulingTest = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final notificationService = ref.read(notificationServiceProvider);

    try {
      final notif = await notificationService.areNotificationsEnabled();
      final exact = await notificationService.ensureExactAlarmsEnabled();

      if (mounted) {
        setState(() {
          _notificationsEnabled = notif;
          _exactAlarmsAllowed = exact;
        });
      }

      if (!notif || !exact) {
        _showPermissionDialog(notifEnabled: notif, exactAllowed: exact);
      }
    } catch (e) {
      developer.log("⚠️ Permission check error: $e");
    }
  }

  void _showPermissionDialog({
    required bool notifEnabled,
    required bool exactAllowed,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        title: Text(
          '⚠️ الصلاحيات مطلوبة',
          style: GoogleFonts.tajawal(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          !notifEnabled && !exactAllowed
              ? 'الإشعارات والجدولة الدقيقة معطلتان.\nيرجى تفعليهما من إعدادات الجهاز.'
              : !notifEnabled
                  ? 'الإشعارات معطلة.\nيرجى تفعيلها من إعدادات الجهاز.'
                  : 'الجدولة الدقيقة (Exact Alarm) غير مفعلة.\nقد تتأخر الإشعارات.',
          style: GoogleFonts.tajawal(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'حسناً',
              style: GoogleFonts.tajawal(
                color: Colors.deepPurpleAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      _selectedMuezzin = prefs.getString(kPrayerVoiceKey) ?? 'mishary.mp3';
      _preFajrReminder = prefs.getBool(kPreFajrReminderEnabled) ?? true;
    });

    developer.log(
      "⚙️ Settings loaded: $_selectedMuezzin | reminder=$_preFajrReminder",
    );
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(kPrayerVoiceKey, _selectedMuezzin);
    await prefs.setBool(kPreFajrReminderEnabled, _preFajrReminder);

    developer.log("💾 Settings saved!");

    widget.onSettingsChanged?.call();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم حفظ التعديلات بنجاح',
          style: GoogleFonts.tajawal(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
      ),
    );
  }

  Future<void> _scheduleTestNotification() async {
    if (_isSchedulingTest) return;
    setState(() => _isSchedulingTest = true);
    try {
      final service = ref.read(notificationServiceProvider);
      final granted = await service.requestPermissions();
      if (!granted) {
        throw StateError('لم يتم منح إذن الإشعارات.');
      }
      await service.scheduleTestNotificationAfterFiveSeconds();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تمت جدولة إشعار الاختبار بعد 5 ثوانٍ',
            style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر جدولة الإشعار: $error',
            style: GoogleFonts.tajawal(),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSchedulingTest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      appBar: AppBar(
        title: Text(
          'إعدادات المؤذن',
          style: GoogleFonts.tajawal(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: const Color(0xFF2C2C2E),
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            SizedBox(height: h * 0.14),
            if (!_notificationsEnabled || !_exactAlarmsAllowed)
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.redAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        !_notificationsEnabled && !_exactAlarmsAllowed
                            ? "الإشعارات والجدولة الدقيقة معطلتان"
                            : !_notificationsEnabled
                                ? "الإشعارات معطلة"
                                : "الجدولة الدقيقة غير مفعلة",
                        style: GoogleFonts.tajawal(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Text(
              'اختيار المؤذن',
              style: GoogleFonts.tajawal(
                fontSize: 22,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              dropdownColor: const Color(0xFF2C2C2E),
              value: _selectedMuezzin,
              decoration: InputDecoration(
                prefixIcon: const Icon(
                  Icons.record_voice_over,
                  color: Colors.deepPurpleAccent,
                ),
                filled: true,
                fillColor: const Color(0xFF2C2C2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              items: List.generate(
                muezzins.length,
                (i) => DropdownMenuItem(
                  value: muezzins[i],
                  child: Text(
                    muezzinNames[i],
                    style: GoogleFonts.tajawal(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              onChanged: (v) => setState(() => _selectedMuezzin = v!),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'يستخدم iOS مقطعاً متوافقاً مدته 29 ثانية من صوت المؤذن المختار، ويستخدم Android ملف الصوت كاملاً.',
                textAlign: TextAlign.right,
                style: GoogleFonts.tajawal(
                  color: Colors.white60,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 40),
            const Divider(color: Colors.white24),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "التذكيرات",
                style: GoogleFonts.tajawal(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFF2C2C2E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                title: Text(
                  "تذكير قبل الفجر",
                  style: GoogleFonts.tajawal(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  "إرسال تذكير قبل أذان الفجر بـ 10 دقائق",
                  style: GoogleFonts.tajawal(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                value: _preFajrReminder,
                secondary: const Icon(
                  Icons.alarm,
                  color: Colors.deepPurpleAccent,
                ),
                onChanged: (v) => setState(() => _preFajrReminder = v),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _isSchedulingTest ? null : _scheduleTestNotification,
                icon: _isSchedulingTest
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.notifications_active_outlined),
                label: Text(
                  'اختبار الإشعار (بعد 5 ثوانٍ)',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.tealAccent,
                  side: const BorderSide(color: Colors.tealAccent),
                ),
              ),
            ),
            const SizedBox(height: 60),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  "حفظ التعديلات",
                  style: GoogleFonts.tajawal(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
