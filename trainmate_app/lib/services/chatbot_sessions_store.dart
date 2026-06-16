import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'chatbot_service.dart';

const _storeVersion = 1;
const _filePrefix = 'trainmate_chat_sessions_v1';
const _maxConversations = 60;
/// Cap for text sent as cross-thread memory context (characters).
const kCrossChatSummaryMaxChars = 12000;

class StoredChatBubble {
  StoredChatBubble({
    required this.text,
    required this.isUser,
    this.imageBase64,
  });

  final String text;
  final bool isUser;
  final String? imageBase64;

  Map<String, dynamic> toJson() => {
        'text': text,
        'isUser': isUser,
        if (imageBase64 != null && imageBase64!.isNotEmpty) 'imageBase64': imageBase64,
      };

  factory StoredChatBubble.fromJson(Map<String, dynamic> m) => StoredChatBubble(
        text: m['text'] as String? ?? '',
        isUser: m['isUser'] as bool? ?? false,
        imageBase64: m['imageBase64'] as String?,
      );
}

class StoredChatConversation {
  StoredChatConversation({
    required this.id,
    required this.title,
    required this.updatedAtMillis,
    required this.uiMessages,
    required this.apiHistory,
  });

  final String id;
  String title;
  int updatedAtMillis;
  final List<StoredChatBubble> uiMessages;
  final List<ChatTurn> apiHistory;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAtMillis': updatedAtMillis,
        'uiMessages': uiMessages.map((e) => e.toJson()).toList(),
        'apiHistory': apiHistory.map((e) => e.toJson()).toList(),
      };

  factory StoredChatConversation.fromJson(Map<String, dynamic> m) {
    final rawUi = (m['uiMessages'] as List<dynamic>? ?? [])
        .map((e) => StoredChatBubble.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final rawApi = (m['apiHistory'] as List<dynamic>? ?? []).map((e) {
      final map = Map<String, dynamic>.from(e as Map);
      return ChatTurn(
        role: map['role'] as String? ?? 'user',
        content: map['content'] as String? ?? '',
      );
    }).toList();
    return StoredChatConversation(
      id: m['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: m['title'] as String? ?? 'Chat',
      updatedAtMillis: m['updatedAtMillis'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      uiMessages: rawUi,
      apiHistory: rawApi,
    );
  }

}

class ChatSessionsSnapshot {
  ChatSessionsSnapshot({
    required this.activeConversationId,
    required this.conversations,
  });

  String activeConversationId;
  List<StoredChatConversation> conversations;

  Map<String, dynamic> toJson() => {
        'version': _storeVersion,
        'activeConversationId': activeConversationId,
        'conversations': conversations.map((e) => e.toJson()).toList(),
      };

  StoredChatConversation? get active {
    for (final c in conversations) {
      if (c.id == activeConversationId) return c;
    }
    return conversations.isEmpty ? null : conversations.first;
  }

  StoredChatConversation ensureActiveConversation() {
    if (conversations.isEmpty) {
      final created = StoredChatConversation(
        id: _newId(),
        title: '',
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        uiMessages: [],
        apiHistory: [],
      );
      conversations.add(created);
      activeConversationId = created.id;
      return created;
    }
    for (final c in conversations) {
      if (c.id == activeConversationId) return c;
    }
    activeConversationId = conversations.first.id;
    return conversations.first;
  }

  Future<void> trimIfNeeded() async {
    if (conversations.length <= _maxConversations) return;
    conversations.sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));
    final kept = conversations.take(_maxConversations).toList();
    conversations
      ..clear()
      ..addAll(kept);
    if (!conversations.any((c) => c.id == activeConversationId)) {
      activeConversationId = conversations.first.id;
    }
  }
}

String _newId() => 'c_${DateTime.now().microsecondsSinceEpoch}';

class ChatbotSessionsStore {
  ChatbotSessionsStore._();

  static final ChatbotSessionsStore instance = ChatbotSessionsStore._();

  ChatSessionsSnapshot? _snapshot;
  bool _busy = false;
  int? _boundUserId;

  ChatSessionsSnapshot? get cached => _snapshot;
  int? get boundUserId => _boundUserId;

  String _fileNameForUser(int? userId) {
    if (userId == null || userId <= 0) {
      return '${_filePrefix}_guest.json';
    }
    return '${_filePrefix}_u$userId.json';
  }

  Future<File> _fileForUser(int? userId) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/${_fileNameForUser(userId)}');
  }

  /// Switch chat storage to the signed-in user. Clears in-memory state and reloads.
  Future<void> bindUser(int? userId) async {
    if (_boundUserId == userId && _snapshot != null) return;
    _boundUserId = userId;
    _snapshot = null;
    await load();
  }

  Future<void> resetForLogout() async {
    _boundUserId = null;
    _snapshot = null;
  }

  Future<File> _file() => _fileForUser(_boundUserId);

  Future<ChatSessionsSnapshot> load() async {
    if (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (_snapshot != null) return _snapshot!;
    }
    _busy = true;
    try {
      final f = await _file();
      if (!await f.exists()) {
        final fresh = ChatSessionsSnapshot(
          activeConversationId: '',
          conversations: [],
        );
        fresh.ensureActiveConversation();
        fresh.activeConversationId = fresh.active!.id;
        _snapshot = fresh;
        await save();
        return fresh;
      }
      final raw = await f.readAsString();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final convs = (map['conversations'] as List<dynamic>? ?? [])
          .map((e) => StoredChatConversation.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final activeId =
          map['activeConversationId'] as String? ?? (convs.isEmpty ? '' : convs.first.id);
      final snap = ChatSessionsSnapshot(activeConversationId: activeId, conversations: convs);
      if (snap.conversations.isEmpty) {
        snap.ensureActiveConversation();
        snap.activeConversationId = snap.active!.id;
      } else if (!snap.conversations.any((c) => c.id == snap.activeConversationId)) {
        snap.activeConversationId = snap.conversations.first.id;
      }
      _snapshot = snap;
      await snap.trimIfNeeded();
      return snap;
    } catch (_) {
      final fallback = ChatSessionsSnapshot(activeConversationId: '', conversations: []);
      fallback.ensureActiveConversation();
      fallback.activeConversationId = fallback.active!.id;
      _snapshot = fallback;
      return fallback;
    } finally {
      _busy = false;
    }
  }

  Future<void> save() async {
    final snap = _snapshot;
    if (snap == null) return;
    try {
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(snap.toJson()));
      await tmp.rename(f.path);
    } catch (e, st) {
      debugPrint('ChatbotSessionsStore.save failed: $e\n$st');
    }
  }

  StoredChatConversation startNewConversation() {
    final snap = _snapshot;
    if (snap == null) {
      throw StateError('load() must be called first');
    }
    final c = StoredChatConversation(
      id: _newId(),
      title: '',
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      uiMessages: [],
      apiHistory: [],
    );
    snap.conversations.insert(0, c);
    snap.activeConversationId = c.id;
    unawaited(snap.trimIfNeeded());
    unawaited(save());
    return c;
  }

  void touchActive() {
    final snap = _snapshot;
    if (snap == null) return;
    final c = snap.active;
    if (c == null) return;
    c.updatedAtMillis = DateTime.now().millisecondsSinceEpoch;
  }

  void updateTitleFromFirstUserMessageIfBlank(String userText, String fallbackTitle) {
    final snap = _snapshot;
    final c = snap?.active;
    if (c == null) return;
    final trimmed = userText.trim();
    if (trimmed.isEmpty) return;
    if (c.title.trim().isNotEmpty) return;
    c.title =
        trimmed.length > 56 ? '${trimmed.substring(0, 53).trim()}…' : trimmed;
    if (c.title.trim().isEmpty) c.title = fallbackTitle;
  }

  bool switchToConversation(String id) {
    final snap = _snapshot;
    if (snap == null) return false;
    if (!snap.conversations.any((e) => e.id == id)) return false;
    snap.activeConversationId = id;
    unawaited(save());
    return true;
  }

  /// Build summarized chat memory from conversations other than [exceptId].
  String buildCrossChatSummary(String exceptId) {
    final snap = _snapshot;
    if (snap == null) return '';
    final others = snap.conversations
        .where((c) => c.id != exceptId)
        .toList()
      ..sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));

    final buf = StringBuffer();
    for (final c in others) {
      buf.writeln('--- ${c.title.isEmpty ? c.id.substring(0, c.id.length.clamp(0, 8)) : c.title} ---');
      for (final turn in c.apiHistory) {
        buf.writeln('${turn.role}: ${turn.content}');
      }
      buf.writeln();
      if (buf.length >= kCrossChatSummaryMaxChars) break;
    }
    var out = buf.toString().trimRight();
    if (out.length > kCrossChatSummaryMaxChars) {
      out = out.substring(out.length - kCrossChatSummaryMaxChars);
    }
    return out;
  }
}
