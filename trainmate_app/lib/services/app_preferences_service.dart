import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferencesService extends ChangeNotifier {
  AppPreferencesService._();
  static final AppPreferencesService instance = AppPreferencesService._();

  static const _themeKey = 'app_theme_mode';
  static const _localeKey = 'app_locale_code';
  static const _notifEnabledKey = 'notif_enabled';
  static const _notifSoundKey = 'notif_sound';
  static const _notifHourKey = 'notif_hour';
  static const _notifMinuteKey = 'notif_minute';
  static const _weightUnitKey = 'weight_unit';
  static const _restTimerSecondsKey = 'rest_timer_seconds';
  static const _aiExerciseOnlyModeKey = 'ai_exercise_only_mode';
  static const _birthDateIsoKey = 'birth_date_iso';
  static const _chatbotToneKey = 'chatbot_tone';
  static const _chatbotWatermarkKey = 'chatbot_watermark';
  static const _chatbotShortRepliesKey = 'chatbot_short_replies';
  static const _smartFeedbackNotifKey = 'notif_smart_feedback';
  static const _streakNotifKey = 'notif_streak';
  static const _bodyGoalKey = 'body_goal';
  static const _trainingDaysPerWeekKey = 'training_days_per_week';

  ThemeMode _themeMode = ThemeMode.light;
  Locale _locale = const Locale('en');
  bool _notificationsEnabled = true;
  bool _notificationSoundEnabled = true;
  int _notificationHour = 20;
  int _notificationMinute = 0;
  String _weightUnit = 'kg';
  int _restTimerSeconds = 90;
  bool _aiExerciseOnlyMode = true;
  DateTime? _birthDate;
  String _chatbotTone = 'balanced';
  bool _chatbotWatermark = true;
  bool _chatbotShortReplies = false;
  bool _smartFeedbackNotifications = true;
  bool _streakNotifications = true;
  String _bodyGoal = 'balanced_fitness';
  int _trainingDaysPerWeek = 4;

  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get notificationSoundEnabled => _notificationSoundEnabled;
  int get notificationHour => _notificationHour;
  int get notificationMinute => _notificationMinute;
  String get weightUnit => _weightUnit;
  int get restTimerSeconds => _restTimerSeconds;
  bool get aiExerciseOnlyMode => _aiExerciseOnlyMode;
  DateTime? get birthDate => _birthDate;
  String get chatbotTone => _chatbotTone;
  bool get chatbotWatermark => _chatbotWatermark;
  bool get chatbotShortReplies => _chatbotShortReplies;
  bool get smartFeedbackNotifications => _smartFeedbackNotifications;
  bool get streakNotifications => _streakNotifications;
  String get bodyGoal => _bodyGoal;
  int get trainingDaysPerWeek => _trainingDaysPerWeek;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final t = p.getString(_themeKey);
    final l = p.getString(_localeKey);
    _notificationsEnabled = p.getBool(_notifEnabledKey) ?? true;
    _notificationSoundEnabled = p.getBool(_notifSoundKey) ?? true;
    _notificationHour = p.getInt(_notifHourKey) ?? 20;
    _notificationMinute = p.getInt(_notifMinuteKey) ?? 0;
    _weightUnit = p.getString(_weightUnitKey) == 'lb' ? 'lb' : 'kg';
    _restTimerSeconds = p.getInt(_restTimerSecondsKey) ?? 90;
    _aiExerciseOnlyMode = p.getBool(_aiExerciseOnlyModeKey) ?? true;
    final birthDateIso = p.getString(_birthDateIsoKey);
    _birthDate = birthDateIso == null ? null : DateTime.tryParse(birthDateIso);
    final tone = p.getString(_chatbotToneKey);
    _chatbotTone = switch (tone) {
      'strict' => 'strict',
      'motivational' => 'motivational',
      _ => 'balanced',
    };
    _chatbotWatermark = p.getBool(_chatbotWatermarkKey) ?? true;
    _chatbotShortReplies = p.getBool(_chatbotShortRepliesKey) ?? false;
    _smartFeedbackNotifications = p.getBool(_smartFeedbackNotifKey) ?? true;
    _streakNotifications = p.getBool(_streakNotifKey) ?? true;
    final goal = p.getString(_bodyGoalKey);
    _bodyGoal = switch (goal) {
      'fat_loss' => 'fat_loss',
      'muscle_building' => 'muscle_building',
      'strength_performance' => 'strength_performance',
      'body_recomposition' => 'body_recomposition',
      _ => 'balanced_fitness',
    };
    _trainingDaysPerWeek = (p.getInt(_trainingDaysPerWeekKey) ?? 4).clamp(2, 6);
    if (t == 'dark') _themeMode = ThemeMode.dark;
    if (t == 'light') _themeMode = ThemeMode.light;
    if (l == 'ar' || l == 'en') {
      _locale = Locale(l!);
    } else {
      final sys = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
      _locale = Locale(sys == 'ar' ? 'ar' : 'en');
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final p = await SharedPreferences.getInstance();
    await p.setString(_themeKey, mode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    _locale = Locale(locale.languageCode == 'ar' ? 'ar' : 'en');
    final p = await SharedPreferences.getInstance();
    await p.setString(_localeKey, _locale.languageCode);
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationsEnabled = enabled;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_notifEnabledKey, enabled);
    notifyListeners();
  }

  Future<void> setNotificationSoundEnabled(bool enabled) async {
    _notificationSoundEnabled = enabled;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_notifSoundKey, enabled);
    notifyListeners();
  }

  Future<void> setNotificationTime(TimeOfDay time) async {
    _notificationHour = time.hour;
    _notificationMinute = time.minute;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_notifHourKey, _notificationHour);
    await p.setInt(_notifMinuteKey, _notificationMinute);
    notifyListeners();
  }

  Future<void> setWeightUnit(String unit) async {
    _weightUnit = unit == 'lb' ? 'lb' : 'kg';
    final p = await SharedPreferences.getInstance();
    await p.setString(_weightUnitKey, _weightUnit);
    notifyListeners();
  }

  Future<void> setRestTimerSeconds(int seconds) async {
    _restTimerSeconds = seconds.clamp(30, 300);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_restTimerSecondsKey, _restTimerSeconds);
    notifyListeners();
  }

  Future<void> setAiExerciseOnlyMode(bool enabled) async {
    _aiExerciseOnlyMode = enabled;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_aiExerciseOnlyModeKey, enabled);
    notifyListeners();
  }

  Future<void> setBirthDate(DateTime? date) async {
    _birthDate = date == null ? null : DateTime(date.year, date.month, date.day);
    final p = await SharedPreferences.getInstance();
    if (_birthDate == null) {
      await p.remove(_birthDateIsoKey);
    } else {
      await p.setString(_birthDateIsoKey, _birthDate!.toIso8601String());
    }
    notifyListeners();
  }

  Future<void> setChatbotTone(String tone) async {
    _chatbotTone = switch (tone) {
      'strict' => 'strict',
      'motivational' => 'motivational',
      _ => 'balanced',
    };
    final p = await SharedPreferences.getInstance();
    await p.setString(_chatbotToneKey, _chatbotTone);
    notifyListeners();
  }

  Future<void> setChatbotWatermark(bool enabled) async {
    _chatbotWatermark = enabled;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_chatbotWatermarkKey, enabled);
    notifyListeners();
  }

  Future<void> setChatbotShortReplies(bool enabled) async {
    _chatbotShortReplies = enabled;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_chatbotShortRepliesKey, enabled);
    notifyListeners();
  }

  Future<void> setSmartFeedbackNotifications(bool enabled) async {
    _smartFeedbackNotifications = enabled;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_smartFeedbackNotifKey, enabled);
    notifyListeners();
  }

  Future<void> setStreakNotifications(bool enabled) async {
    _streakNotifications = enabled;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_streakNotifKey, enabled);
    notifyListeners();
  }

  Future<void> setBodyGoal(String goal) async {
    _bodyGoal = switch (goal) {
      'fat_loss' => 'fat_loss',
      'muscle_building' => 'muscle_building',
      'strength_performance' => 'strength_performance',
      'body_recomposition' => 'body_recomposition',
      _ => 'balanced_fitness',
    };
    final p = await SharedPreferences.getInstance();
    await p.setString(_bodyGoalKey, _bodyGoal);
    notifyListeners();
  }

  Future<void> setTrainingDaysPerWeek(int days) async {
    _trainingDaysPerWeek = days.clamp(2, 6);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_trainingDaysPerWeekKey, _trainingDaysPerWeek);
    notifyListeners();
  }
}
