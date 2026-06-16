import 'package:flutter/material.dart';
import '../../l10n/app_text.dart';

import 'account_settings_screen.dart';
import 'app_settings_screen.dart';
import 'chatbot_settings_screen.dart';
import 'notification_settings_screen.dart';
import 'plan_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.tr('settings.title'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: Text(t.tr('settings.account')),
              subtitle: Text(t.tr('settings.accountSubtitle')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AccountSettingsScreen(),
                ),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.fitness_center_rounded),
              title: Text(t.tr('settings.planSettings')),
              subtitle: Text(t.tr('settings.planSubtitle')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PlanSettingsScreen(),
                ),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_none_rounded),
              title: Text(t.tr('settings.notifications')),
              subtitle: Text(t.tr('settings.notificationsSubtitle')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen(),
                ),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.smart_toy_outlined),
              title: Text(t.tr('settings.chatbotSettings')),
              subtitle: Text(t.tr('settings.chatbotSettingsSubtitle')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ChatbotSettingsScreen(),
                ),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: Text(t.tr('settings.appSettings')),
              subtitle: Text(t.tr('settings.appSubtitle')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
