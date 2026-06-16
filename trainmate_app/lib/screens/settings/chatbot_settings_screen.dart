import 'package:flutter/material.dart';

import '../../l10n/app_text.dart';
import '../../services/app_preferences_service.dart';

class ChatbotSettingsScreen extends StatelessWidget {
  const ChatbotSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = AppPreferencesService.instance;
    return AnimatedBuilder(
      animation: prefs,
      builder: (context, child) {
        final t = AppText.of(context);
        return Scaffold(
          appBar: AppBar(title: Text(t.tr('settings.chatbotSettings'))),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(t.tr('settings.chatbotTone')),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'balanced', label: Text(t.tr('chat.toneBalanced'))),
                  ButtonSegment(value: 'strict', label: Text(t.tr('chat.toneStrict'))),
                  ButtonSegment(
                    value: 'motivational',
                    label: Text(t.tr('chat.toneMotivational')),
                  ),
                ],
                selected: {prefs.chatbotTone},
                onSelectionChanged: (v) => prefs.setChatbotTone(v.first),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: prefs.chatbotShortReplies,
                title: Text(t.tr('settings.chatbotShortReplies')),
                subtitle: Text(t.tr('settings.chatbotShortRepliesSubtitle')),
                onChanged: (v) => prefs.setChatbotShortReplies(v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: prefs.chatbotWatermark,
                title: Text(t.tr('settings.chatbotWatermark')),
                subtitle: Text(t.tr('settings.chatbotWatermarkSubtitle')),
                onChanged: (v) => prefs.setChatbotWatermark(v),
              ),
            ],
          ),
        );
      },
    );
  }
}
