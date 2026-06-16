import 'dart:async';

import 'chatbot_service.dart';
import 'user_service.dart';
import 'workout_service.dart';

/// Ensures core app data is fresh right after auth/session restore.
class SessionHydrationService {
  SessionHydrationService({
    UserService? userService,
    WorkoutService? workoutService,
    ChatbotService? chatbotService,
  }) : _user = userService ?? UserService(),
       _workouts = workoutService ?? WorkoutService(),
       _chatbot = chatbotService ?? ChatbotService();

  final UserService _user;
  final WorkoutService _workouts;
  final ChatbotService _chatbot;

  Future<void> hydrate({required String languageCode}) async {
    MeData? me;
    await _retry(
      () async {
        me = await _user.getMe().timeout(const Duration(seconds: 10));
      },
      attempts: 2,
    );
    await Future.wait<void>([
      _retry(
        () => _workouts.listWorkouts(limit: 40).timeout(
          const Duration(seconds: 10),
        ),
        attempts: 2,
      ),
      _retry(
        () => _chatbot.progressFeedback(
          userId: me?.id,
          languageCode: languageCode,
        ).timeout(
          const Duration(seconds: 10),
        ),
        attempts: 2,
      ),
    ]);
  }

  Future<T> _retry<T>(
    Future<T> Function() action, {
    int attempts = 2,
    Duration delay = const Duration(milliseconds: 350),
  }) async {
    Object? lastError;
    for (var i = 0; i < attempts; i++) {
      try {
        return await action();
      } catch (e) {
        lastError = e;
        if (i < attempts - 1) {
          await Future<void>.delayed(delay);
        }
      }
    }
    throw lastError!;
  }
}
