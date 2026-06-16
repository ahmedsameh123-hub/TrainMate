import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../l10n/app_text.dart';
import '../../services/api_service.dart';
import '../../services/chatbot_service.dart';
import '../../services/chatbot_sessions_store.dart';
import '../../services/user_service.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatMessage {
  _ChatMessage({
    required this.text,
    required this.isUser,
    this.imagePath,
    this.imageBase64,
  });

  final String text;
  final bool isUser;
  final String? imagePath;
  /// Persisted / restored user image (camera path may be stale after restart).
  final String? imageBase64;
}

class _ChatbotScreenState extends State<ChatbotScreen>
    with SingleTickerProviderStateMixin {
  final _sessions = ChatbotSessionsStore.instance;
  final _svc = ChatbotService();
  final _user = UserService();
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();
  final _speech = stt.SpeechToText();
  final List<_ChatMessage> _uiMessages = [];
  final List<ChatTurn> _apiHistory = [];
  bool _sending = false;
  bool _speechReady = false;
  bool _listening = false;
  String _voiceDraft = '';
  bool _voiceCanceledGesture = false;
  DateTime? _voiceStartAt;
  Timer? _voiceTicker;
  int _voiceElapsedSec = 0;
  String? _error;
  String? _speechError;
  MeData? _me;
  String? _selectedImagePath;
  String? _selectedImageBase64;
  bool _loadingSessions = true;
  late final AnimationController _voiceWaveCtrl;

  @override
  void initState() {
    super.initState();
    _voiceWaveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _initChat();
    _initSpeech();
  }

  Future<void> _initChat() async {
    final cached = await _user.getCachedMe();
    await _sessions.bindUser(cached?.id);
    await _bootstrapSessions();
    await _loadMe();
  }

  Future<void> _bootstrapSessions() async {
    await _sessions.load();
    if (!mounted) return;
    final snap = _sessions.cached;
    final c = snap?.ensureActiveConversation();
    if (c != null && snap != null) {
      snap.activeConversationId = c.id;
    }
    if (!mounted) return;
    setState(() {
      _uiMessages.clear();
      _apiHistory.clear();
      if (c != null) {
        for (final b in c.uiMessages) {
          _uiMessages.add(
            _ChatMessage(
              text: b.text,
              isUser: b.isUser,
              imageBase64: b.imageBase64,
            ),
          );
        }
        _apiHistory.addAll(c.apiHistory);
      }
      _loadingSessions = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollDown());
  }

  void _flushStore() {
    if (_loadingSessions) return;
    final snap = _sessions.cached;
    final c = snap?.active;
    if (c == null) return;
    c.uiMessages
      ..clear()
      ..addAll(
        _uiMessages.map(
          (m) => StoredChatBubble(
            text: m.text,
            isUser: m.isUser,
            imageBase64: m.imageBase64,
          ),
        ),
      );
    c.apiHistory
      ..clear()
      ..addAll(_apiHistory);
    _sessions.touchActive();
    final fb = mounted ? AppText.of(context).tr('chat.newChatTitle') : 'New conversation';
    _sessions.updateTitleFromFirstUserMessageIfBlank(
      _firstUserSnippetForTitle(),
      fb,
    );
    unawaited(_sessions.save());
  }

  String _firstUserSnippetForTitle() {
    for (final m in _uiMessages) {
      if (m.isUser) {
        final s = m.text.trim();
        if (s.isNotEmpty) return s;
      }
    }
    return '';
  }

  Future<void> _startNewChat() async {
    if (_sending || _loadingSessions) return;
    _flushStore();
    _sessions.startNewConversation();
    if (!mounted) return;
    setState(() {
      _uiMessages.clear();
      _apiHistory.clear();
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollDown());
  }

  void _openConversationsSheet() {
    final t = AppText.of(context);
    _flushStore();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final snap = _sessions.cached;
        final list = [...?snap?.conversations];
        list.sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));
        final sheetH = MediaQuery.sizeOf(ctx).height * 0.52;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Text(
                    t.tr('chat.conversations'),
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                SizedBox(
                  height: sheetH,
                  child: list.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(t.tr('chat.noOtherChats')),
                        )
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final c = list[i];
                            final title = c.title.trim().isEmpty
                                ? t.tr('chat.newChatTitle')
                                : c.title;
                            final active = snap?.activeConversationId == c.id;
                            return ListTile(
                              leading: Icon(
                                active ? Icons.chat_bubble : Icons.chat_bubble_outline,
                                color:
                                    active ? Theme.of(ctx).colorScheme.primary : null,
                              ),
                              title: Text(title),
                              subtitle: Text(
                                DateTime.fromMillisecondsSinceEpoch(c.updatedAtMillis)
                                    .toLocal()
                                    .toString()
                                    .split('.')
                                    .first,
                              ),
                              onTap: active
                                  ? null
                                  : () {
                                      _sessions.switchToConversation(c.id);
                                      if (!mounted) return;
                                      Navigator.pop(ctx);
                                      final cur = _sessions.cached!.active!;
                                      setState(() {
                                        _uiMessages
                                          ..clear()
                                          ..addAll(
                                            cur.uiMessages.map(
                                              (b) => _ChatMessage(
                                                text: b.text,
                                                isUser: b.isUser,
                                                imageBase64: b.imageBase64,
                                              ),
                                            ),
                                          );
                                        _apiHistory
                                          ..clear()
                                          ..addAll(cur.apiHistory);
                                      });
                                      WidgetsBinding.instance.addPostFrameCallback(
                                        (_) => _scrollDown(),
                                      );
                                    },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadMe() async {
    final cached = await _user.getCachedMe();
    if (cached != null) {
      if (_sessions.boundUserId != cached.id) {
        await _sessions.bindUser(cached.id);
        await _reloadSessionsUi();
      } else if (mounted) {
        setState(() => _me = cached);
      }
    }
    try {
      final me = await _user.getMe().timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (_sessions.boundUserId != me.id) {
        await _sessions.bindUser(me.id);
        await _reloadSessionsUi();
      }
      setState(() => _me = me);
    } catch (_) {}
  }

  Future<void> _reloadSessionsUi() async {
    final snap = _sessions.cached;
    final c = snap?.ensureActiveConversation();
    if (c != null && snap != null) {
      snap.activeConversationId = c.id;
    }
    if (!mounted) return;
    setState(() {
      _uiMessages.clear();
      _apiHistory.clear();
      if (c != null) {
        for (final b in c.uiMessages) {
          _uiMessages.add(
            _ChatMessage(
              text: b.text,
              isUser: b.isUser,
              imageBase64: b.imageBase64,
            ),
          );
        }
        _apiHistory.addAll(c.apiHistory);
      }
      _loadingSessions = false;
    });
  }

  @override
  void dispose() {
    _flushStore();
    _voiceTicker?.cancel();
    _voiceWaveCtrl.dispose();
    _speech.stop();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      final ok = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'notListening' || status == 'done') {
            setState(() => _listening = false);
            _stopVoiceClock();
            _voiceWaveCtrl.stop();
          }
        },
        onError: (err) {
          if (!mounted) return;
          final msg = (err.errorMsg).toLowerCase();
          final isTimeout =
              msg.contains('timeout') || msg.contains('error_no_match');
          setState(() {
            _listening = false;
            _speechError = isTimeout ? null : err.errorMsg;
          });
          _stopVoiceClock();
          _voiceWaveCtrl.stop();
        },
      );
      if (!mounted) return;
      setState(() => _speechReady = ok);
    } catch (_) {
      if (!mounted) return;
      setState(() => _speechReady = false);
    }
  }

  Future<void> _startListening() async {
    if (_sending || _listening) return;
    if (!_speechReady) {
      await _initSpeech();
      if (!mounted) return;
      if (!_speechReady) return;
    }

    final lang = Localizations.localeOf(context).languageCode;
    final localeId = lang.startsWith('ar') ? 'ar' : 'en_US';

    setState(() {
      _speechError = null;
      _listening = true;
      _voiceCanceledGesture = false;
    });
    _startVoiceClock();
    _voiceWaveCtrl.repeat();
    await _speech.listen(
      localeId: localeId,
      listenFor: const Duration(minutes: 30),
      pauseFor: const Duration(minutes: 5),
      // ignore: deprecated_member_use
      listenMode: stt.ListenMode.dictation,
      // ignore: deprecated_member_use
      partialResults: true,
      // ignore: deprecated_member_use
      cancelOnError: true,
      onResult: (result) {
        final text = result.recognizedWords.trim();
        if (!mounted || text.isEmpty) return;
        setState(() {
          _voiceDraft = text;
          _ctrl.text = text;
          _ctrl.selection = TextSelection.fromPosition(
            TextPosition(offset: _ctrl.text.length),
          );
        });
      },
    );
  }

  Future<void> _stopListening({bool cancel = false, bool allowAutoSend = false}) async {
    if (_listening) {
      await _speech.stop();
    }
    if (!mounted) return;
    setState(() {
      _listening = false;
    });
    _stopVoiceClock();
    _voiceWaveCtrl.stop();
    if (cancel) {
      setState(() {
        _voiceDraft = '';
        _speechError = null;
      });
      return;
    }
    if (allowAutoSend && _voiceDraft.trim().isNotEmpty) {
      await _sendVoiceDraft();
    }
  }

  void _startVoiceClock() {
    _voiceTicker?.cancel();
    _voiceStartAt = DateTime.now();
    _voiceElapsedSec = 0;
    _voiceTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = _voiceStartAt;
      if (!mounted || s == null) return;
      setState(() => _voiceElapsedSec = DateTime.now().difference(s).inSeconds);
    });
  }

  void _stopVoiceClock() {
    _voiceTicker?.cancel();
    _voiceTicker = null;
  }

  String _voiceTimerText() {
    final m = _voiceElapsedSec ~/ 60;
    final s = _voiceElapsedSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _sendVoiceDraft() async {
    if (_voiceDraft.trim().isEmpty) return;
    _ctrl.text = _voiceDraft.trim();
    _ctrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _ctrl.text.length),
    );
    setState(() => _speechError = null);
    await _send();
  }

  Future<void> _finalizeVoiceAndSend() async {
    if (_listening) {
      await _stopListening(cancel: false, allowAutoSend: false);
    }
    if (!mounted) return;
    if (_voiceDraft.trim().isNotEmpty) {
      await _sendVoiceDraft();
      return;
    }
    if (_ctrl.text.trim().isNotEmpty) {
      await _send();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppText.of(context).isArabic
              ? 'لم يتم التقاط كلام واضح، جرّب مرة تانية واتكلم بالقرب من الميكروفون.'
              : 'No clear speech captured. Try again and speak closer to the microphone.',
        ),
      ),
    );
  }

  Widget _buildVoiceWave(Color color) {
    return SizedBox(
      height: 24,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const barWidth = 3.0;
          const barGap = 2.0;
          final maxBars = (constraints.maxWidth / (barWidth + barGap)).floor();
          final bars = math.max(6, math.min(18, maxBars));
          return AnimatedBuilder(
            animation: _voiceWaveCtrl,
            builder: (context, child) {
              final t = _voiceWaveCtrl.value * 2 * math.pi;
              return Row(
                mainAxisSize: MainAxisSize.max,
                children: List.generate(bars, (i) {
                  final phase = t + (i * 0.45);
                  final amp = _listening
                      ? (0.25 + 0.75 * (math.sin(phase).abs()))
                      : 0.2;
                  final h = 4.0 + (16.0 * amp);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Container(
                      width: barWidth,
                      height: h,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: _listening ? 0.95 : 0.45),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  );
                }),
              );
            },
          );
        },
      ),
    );
  }

  String _chatFailureMessage(AppText t, Object e) {
    if (e is ApiException) {
      if (e.statusCode == 401) return t.tr('chat.errorSession');
      final low = e.body.toLowerCase();
      if (e.statusCode == 502 ||
          low.contains('llm') ||
          low.contains('bad gateway')) {
        return t.tr('chat.errorModel');
      }
      final b = e.body.trim();
      if (b.isNotEmpty) {
        return b.length > 400 ? '${b.substring(0, 400)}…' : b;
      }
      return t.tr('chat.errorServer');
    }
    if (e is SocketException || e is http.ClientException) {
      return t.tr('chat.networkError');
    }
    return t.tr('chat.errorServer');
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedImagePath = picked.path;
        _selectedImageBase64 = base64Encode(bytes);
      });
    } catch (_) {}
  }

  void _removeImage() {
    setState(() {
      _selectedImagePath = null;
      _selectedImageBase64 = null;
    });
  }

  Future<void> _send() async {
    final userText = _ctrl.text.trim();
    final hasImage =
        _selectedImageBase64 != null && _selectedImageBase64!.isNotEmpty;
    if ((userText.isEmpty && !hasImage) || _sending) return;
    final imagePath = _selectedImagePath;
    final imageBase64 = _selectedImageBase64;
    final snap = _sessions.cached;
    final activeId = snap?.activeConversationId ?? '';
    final crossSummary = activeId.isEmpty
        ? null
        : _sessions.buildCrossChatSummary(activeId);

    final tLocale = AppText.of(context);
    String? enhancedSummary = crossSummary;
    final cachedMe = await UserService().getCachedMe();
    if (!mounted) return;
    final activePlan = cachedMe?.activePlan;
    if (activePlan != null) {
      final planContext =
          "The user is currently following the training plan '${activePlan.name}' for ${activePlan.durationWeeks} weeks. Exercises: ${activePlan.exercises.join(', ')}.";
      enhancedSummary = enhancedSummary == null ? planContext : '$enhancedSummary\n\n$planContext';
    }

    _ctrl.clear();
    setState(() {
      _voiceDraft = '';
      _uiMessages.add(
        _ChatMessage(
          text: userText.isNotEmpty
              ? userText
              : (tLocale.isArabic ? 'تم إرفاق صورة' : 'Image attached'),
          isUser: true,
          imagePath: imagePath,
          imageBase64: hasImage ? imageBase64 : null,
        ),
      );
      _sending = true;
      _error = null;
      _selectedImagePath = null;
      _selectedImageBase64 = null;
    });
    _scrollDown();

    try {
      final reply = await _svc.send(
        history: _apiHistory,
        userMessage: userText,
        imageBase64: imageBase64,
        crossChatSummary: enhancedSummary,
      );
      if (userText.isNotEmpty) {
        _apiHistory.add(ChatTurn(role: 'user', content: userText));
      } else if (hasImage) {
        _apiHistory.add(
          ChatTurn(
            role: 'user',
            content: tLocale.isArabic ? '[صورة]' : '[image]',
          ),
        );
      }
      _apiHistory.add(ChatTurn(role: 'assistant', content: reply));
      if (!mounted) return;
      setState(() {
        _uiMessages.add(_ChatMessage(text: reply, isUser: false));
      });
    } on ApiException catch (e) {
      if (mounted) {
        final t = AppText.of(context);
        final msg = _chatFailureMessage(t, e);
        setState(() => _error = null);
        final errTurn = ChatTurn(role: 'assistant', content: msg);
        _uiMessages.add(_ChatMessage(text: msg, isUser: false));
        if (userText.isNotEmpty) {
          _apiHistory.add(ChatTurn(role: 'user', content: userText));
        } else if (hasImage) {
          _apiHistory.add(
            ChatTurn(
              role: 'user',
              content: t.isArabic ? '[صورة]' : '[image]',
            ),
          );
        }
        _apiHistory.add(errTurn);
      }
    } catch (e) {
      if (mounted) {
        final t = AppText.of(context);
        setState(() => _error = null);
        final msg = _chatFailureMessage(t, e);
        _uiMessages.add(_ChatMessage(text: msg, isUser: false));
        if (userText.isNotEmpty) {
          _apiHistory.add(ChatTurn(role: 'user', content: userText));
        } else if (hasImage) {
          _apiHistory.add(
            ChatTurn(
              role: 'user',
              content: t.isArabic ? '[صورة]' : '[image]',
            ),
          );
        }
        _apiHistory.add(ChatTurn(role: 'assistant', content: msg));
      }
    } finally {
      _flushStore();
      if (mounted) setState(() => _sending = false);
      _scrollDown();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.tr('chat.title')),
            Text(
              t.tr('chat.subtitle'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: t.tr('chat.conversations'),
            onPressed: _loadingSessions ? null : _openConversationsSheet,
            icon: const Icon(Icons.forum_outlined),
          ),
          IconButton(
            tooltip: t.tr('chat.newChat'),
            onPressed: _loadingSessions || _sending ? null : _startNewChat,
            icon: const Icon(Icons.note_add_rounded),
          ),
        ],
      ),
      body: _loadingSessions
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: cs.primary),
                  const SizedBox(height: 16),
                  Text(
                    AppText.of(context).tr('common.loading'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.primary.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 20, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t.tr('chat.personalized'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              t.tr('chat.memoryHint'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
          if (_me?.plan?.category != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                t.tr(
                  'chat.plan',
                  args: {
                    'category': _me!.plan!.category ?? '-',
                    'weeks': '${_me!.plan!.durationWeeks ?? "-"}',
                  },
                ),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                _error!,
                style: TextStyle(color: cs.error, fontSize: 12),
              ),
            ),
          if (_listening || _speechError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _speechError ??
                    (t.isArabic ? 'جاري الاستماع...' : 'Listening...'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _speechError != null ? cs.error : cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount: _uiMessages.length,
              itemBuilder: (context, i) {
                final m = _uiMessages[i];
                final bubble = m.isUser
                    ? cs.primary
                    : cs.surfaceContainerHighest;
                final textColor = m.isUser ? cs.onPrimary : cs.onSurface;
                return Align(
                  alignment: m.isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.85,
                    ),
                    decoration: BoxDecoration(
                      color: bubble,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(m.isUser ? 18 : 4),
                        bottomRight: Radius.circular(m.isUser ? 4 : 18),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (m.imagePath != null && m.imagePath!.isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(m.imagePath!),
                              height: 140,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ] else if (m.imageBase64 != null &&
                            m.imageBase64!.trim().isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Builder(
                              builder: (context) {
                                try {
                                  return Image.memory(
                                    base64Decode(m.imageBase64!),
                                    height: 140,
                                    fit: BoxFit.cover,
                                  );
                                } catch (_) {
                                  return SizedBox(
                                    height: 80,
                                    child: Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: textColor,
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Text(
                          m.text,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: textColor,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_sending)
            LinearProgressIndicator(minHeight: 2, color: cs.primary),
          if (_selectedImagePath != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_selectedImagePath!),
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t.isArabic ? 'تم إرفاق صورة' : 'Image attached',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    onPressed: _removeImage,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          Material(
            elevation: 8,
            shadowColor: Colors.black26,
            color: cs.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      onPressed: _sending
                          ? null
                          : () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_rounded),
                      tooltip: t.isArabic ? 'التقاط صورة' : 'Take photo',
                    ),
                    IconButton(
                      onPressed: _sending
                          ? null
                          : () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.image_rounded),
                      tooltip: t.isArabic ? 'اختيار صورة' : 'Pick image',
                    ),
                    GestureDetector(
                      onTap: _sending
                          ? null
                          : () {
                              if (_listening) {
                                _stopListening(
                                  cancel: false,
                                  allowAutoSend: false,
                                );
                              } else {
                                _startListening();
                              }
                            },
                      onLongPressStart: _sending ? null : (_) => _startListening(),
                      onLongPressMoveUpdate: _sending || !_listening
                          ? null
                          : (d) {
                              final dx = d.offsetFromOrigin.dx;
                              final cancelNow = dx < -70;
                              setState(() {
                                _voiceCanceledGesture = cancelNow;
                              });
                            },
                      onLongPressEnd: _sending
                          ? null
                          : (_) => _stopListening(
                                cancel: _voiceCanceledGesture,
                                allowAutoSend: !_voiceCanceledGesture,
                              ),
                      child: Tooltip(
                        message: t.isArabic
                            ? 'اضغط مطولًا للتسجيل واسحب لليسار للإلغاء'
                            : 'Hold to record, swipe left to cancel',
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _listening
                                ? (_voiceCanceledGesture
                                      ? cs.errorContainer
                                      : cs.primaryContainer)
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                            color: _voiceCanceledGesture
                                ? cs.error
                                : (_listening ? cs.primary : cs.onSurfaceVariant),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _listening || _voiceDraft.trim().isNotEmpty
                          ? Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _voiceCanceledGesture
                                        ? Icons.delete_outline_rounded
                                        : Icons.graphic_eq_rounded,
                                    size: 18,
                                    color: _voiceCanceledGesture ? cs.error : cs.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: _buildVoiceWave(cs.primary)),
                                  const SizedBox(width: 8),
                                  Text(
                                    _listening
                                        ? _voiceTimerText()
                                        : (t.isArabic ? 'جاهز' : 'Ready'),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : TextField(
                              controller: _ctrl,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              decoration: InputDecoration(
                                hintText: t.tr('chat.hint'),
                                filled: true,
                                fillColor: cs.surfaceContainerHighest.withValues(
                                  alpha: 0.4,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 4),
                    IconButton.filled(
                      onPressed: _sending
                          ? null
                          : () async {
                              if (_listening) {
                                await _finalizeVoiceAndSend();
                                return;
                              }
                              if (_voiceDraft.trim().isNotEmpty) {
                                await _sendVoiceDraft();
                                return;
                              }
                              await _send();
                            },
                      icon: Icon(
                        (_voiceDraft.trim().isNotEmpty && !_listening)
                            ? Icons.send_and_archive_rounded
                            : Icons.send_rounded,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
