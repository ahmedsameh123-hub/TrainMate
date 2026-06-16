import 'package:flutter/material.dart';

import '../../l10n/app_text.dart';
import '../../services/app_preferences_service.dart';
import '../../services/notification_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final prefs = AppPreferencesService.instance;
    return AnimatedBuilder(
      animation: prefs,
      builder: (context, child) {
        final t = AppText.of(context);
        return Scaffold(
          appBar: AppBar(title: Text(t.tr('settings.notifications'))),
          body: ListView(
            children: [
              SwitchListTile(
                value: prefs.notificationsEnabled,
                title: Text(t.tr('settings.enableNotifications')),
                subtitle: Text(t.tr('settings.notificationsSubtitle')),
                onChanged: (v) async {
                  await prefs.setNotificationsEnabled(v);
                  if (v) {
                    await NotificationService.instance
                        .scheduleDailyWorkoutReminder(
                          arabic: prefs.locale.languageCode == 'ar',
                          hour: prefs.notificationHour,
                          minute: prefs.notificationMinute,
                        );
                  } else {
                    await NotificationService.instance.cancelDailyReminder();
                  }
                },
              ),
              SwitchListTile(
                value: prefs.notificationSoundEnabled,
                title: Text(t.tr('settings.notificationSound')),
                subtitle: Text(t.tr('settings.notificationSoundSubtitle')),
                onChanged: prefs.notificationsEnabled
                    ? (v) => prefs.setNotificationSoundEnabled(v)
                    : null,
              ),
              ListTile(
                title: Text(t.tr('settings.dailyReminderTime')),
                subtitle: Text(
                  '${prefs.notificationHour.toString().padLeft(2, '0')}:${prefs.notificationMinute.toString().padLeft(2, '0')}',
                ),
                trailing: const Icon(Icons.access_time_rounded),
                onTap: prefs.notificationsEnabled
                    ? () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(
                            hour: prefs.notificationHour,
                            minute: prefs.notificationMinute,
                          ),
                        );
                        if (picked == null) return;
                        await prefs.setNotificationTime(picked);
                        await NotificationService.instance
                            .scheduleDailyWorkoutReminder(
                              arabic: prefs.locale.languageCode == 'ar',
                              hour: picked.hour,
                              minute: picked.minute,
                            );
                      }
                    : null,
              ),
              SwitchListTile(
                value: prefs.smartFeedbackNotifications,
                title: Text(t.tr('settings.smartFeedbackNotif')),
                subtitle: Text(t.tr('settings.smartFeedbackNotifSubtitle')),
                onChanged: prefs.notificationsEnabled
                    ? (v) => prefs.setSmartFeedbackNotifications(v)
                    : null,
              ),
              SwitchListTile(
                value: prefs.streakNotifications,
                title: Text(t.tr('settings.streakNotif')),
                subtitle: Text(t.tr('settings.streakNotifSubtitle')),
                onChanged: prefs.notificationsEnabled
                    ? (v) => prefs.setStreakNotifications(v)
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}
