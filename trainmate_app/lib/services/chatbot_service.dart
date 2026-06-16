import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_preferences_service.dart';
import 'api_service.dart';

class ChatTurn {
  ChatTurn({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

class ChatbotService {
  static String _progressKey(int? userId, String lang) =>
      'trainmate_progress_feedback_v1_${userId ?? 0}_$lang';

  Future<String?> getCachedProgressFeedback({
    required int? userId,
    required String languageCode,
  }) async {
    final lang = languageCode.trim().isEmpty ? 'en' : languageCode.trim();
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_progressKey(userId, lang));
    if (raw == null) return null;
    final v = raw.trim();
    return v.isEmpty ? null : v;
  }

  Future<String> send({
    required List<ChatTurn> history,
    required String userMessage,
    String? imageBase64,
    String? crossChatSummary,
  }) async {
    final messages = [
      ...history.map((e) => e.toJson()),
      {'role': 'user', 'content': userMessage},
    ];
    final prefs = AppPreferencesService.instance;
    final summary = crossChatSummary?.trim();
    final r = await ApiService.post(
      '/api/chat',
      body: {
        'messages': messages,
        if (imageBase64 != null && imageBase64.isNotEmpty)
          'imageBase64': imageBase64,
        if (summary != null && summary.isNotEmpty) 'crossChatSummary': summary,
        'assistant_tone': prefs.chatbotTone,
        'prefer_short_reply': prefs.chatbotShortReplies,
      },
      auth: true,
    );
    if (r.statusCode == 200) {
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      return m['reply'] as String? ?? '';
    }
    throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
  }

  Future<String> progressFeedback({
    required int? userId,
    required String languageCode,
  }) async {
    final lang = languageCode.trim().isEmpty ? 'en' : languageCode.trim();
    final r = await ApiService.post(
      '/api/chat/progress-feedback?lang=$lang',
      body: {},
      auth: true,
    );
    if (r.statusCode == 200) {
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      final reply = (m['reply'] as String? ?? '').trim();
      if (reply.isNotEmpty) {
        final p = await SharedPreferences.getInstance();
        await p.setString(_progressKey(userId, lang), reply);
      }
      return reply;
    }
    throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
  }
}
