import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'app_preferences_service.dart';

class NotificationRecord {
  NotificationRecord({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAtIso,
    required this.kind,
    this.read = false,
  });

  final int id;
  final String title;
  final String body;
  final String createdAtIso;
  final String kind;
  final bool read;

  factory NotificationRecord.fromJson(Map<String, dynamic> j) {
    return NotificationRecord(
      id: j['id'] as int,
      title: j['title'] as String,
      body: j['body'] as String,
      createdAtIso: j['created_at'] as String,
      kind: j['kind'] as String? ?? 'general',
      read: j['read'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'created_at': createdAtIso,
    'kind': kind,
    'read': read,
  };

  NotificationRecord copyWith({bool? read}) {
    return NotificationRecord(
      id: id,
      title: title,
      body: body,
      createdAtIso: createdAtIso,
      kind: kind,
      read: read ?? this.read,
    );
  }
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _historyKey = 'notification_history_v1';
  static const _dailyKeyPrefix = 'notif_daily_key_';
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    tzdata.initializeTimeZones();
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  Future<void> sendNow({
    required String title,
    required String body,
    String kind = 'general',
  }) async {
    await init();
    final prefs = AppPreferencesService.instance;
    if (!prefs.notificationsEnabled) return;

    final id = DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);
    final android = AndroidNotificationDetails(
      'trainmate_general',
      'TrainMate reminders',
      channelDescription: 'Workout and progress reminders',
      importance: Importance.max,
      priority: Priority.high,
      playSound: prefs.notificationSoundEnabled,
      enableVibration: prefs.notificationSoundEnabled,
    );
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: android),
    );
    await _saveRecord(
      NotificationRecord(
        id: id,
        title: title,
        body: body,
        createdAtIso: DateTime.now().toIso8601String(),
        kind: kind,
        read: false,
      ),
    );
  }

  Future<void> scheduleDailyWorkoutReminder({
    required bool arabic,
    required int hour,
    required int minute,
  }) async {
    await init();
    if (!AppPreferencesService.instance.notificationsEnabled) return;
    await _plugin.cancel(id: 7001);
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'trainmate_daily',
        'Daily reminders',
        channelDescription: 'Daily workout reminder',
        playSound: AppPreferencesService.instance.notificationSoundEnabled,
        enableVibration:
            AppPreferencesService.instance.notificationSoundEnabled,
      ),
    );

    try {
      await _plugin.zonedSchedule(
        id: 7001,
        title: arabic ? 'تذكير تمرين اليوم' : 'Today workout reminder',
        body: arabic
            ? 'عندك تمرين النهارده. افتح التطبيق وكمل الخطة.'
            : 'You have a workout today. Open app and stay on plan.',
        scheduledDate: scheduled,
        notificationDetails: details,
        matchDateTimeComponents: DateTimeComponents.time,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } on PlatformException catch (e) {
      // Android 12+ may block exact alarms without permission.
      if (e.code == 'exact_alarms_not_permitted') {
        await _plugin.zonedSchedule(
          id: 7001,
          title: arabic ? 'تذكير تمرين اليوم' : 'Today workout reminder',
          body: arabic
              ? 'عندك تمرين النهارده. افتح التطبيق وكمل الخطة.'
              : 'You have a workout today. Open app and stay on plan.',
          scheduledDate: scheduled,
          notificationDetails: details,
          matchDateTimeComponents: DateTimeComponents.time,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        return;
      }
      rethrow;
    }
  }

  Future<bool> shouldSendToday(String key) async {
    final p = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final fullKey = '$_dailyKeyPrefix$key';
    final last = p.getString(fullKey);
    if (last == today) return false;
    await p.setString(fullKey, today);
    return true;
  }

  Future<List<NotificationRecord>> getHistory() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_historyKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => NotificationRecord.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAtIso.compareTo(a.createdAtIso));
  }

  Future<void> markAsRead(int id) async {
    final p = await SharedPreferences.getInstance();
    final old = await getHistory();
    final updated = old
        .map((e) => e.id == id ? e.copyWith(read: true) : e)
        .toList();
    await p.setString(
      _historyKey,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clearHistory() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_historyKey);
  }

  Future<void> cancelDailyReminder() async {
    await init();
    await _plugin.cancel(id: 7001);
  }

  Future<void> _saveRecord(NotificationRecord record) async {
    final p = await SharedPreferences.getInstance();
    final old = await getHistory();
    final updated = [record, ...old].take(200).toList();
    await p.setString(
      _historyKey,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
  }
}
