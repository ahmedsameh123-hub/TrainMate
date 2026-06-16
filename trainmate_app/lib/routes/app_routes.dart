import 'package:flutter/material.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/verify_email_screen.dart';
import '../screens/main/main_shell.dart';
import '../screens/exercise/exercise_screen.dart';
import '../screens/chatbot/chatbot_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/onboarding/onboarding_plan_screen.dart';
import '../screens/onboarding/onboarding_profile_screen.dart';
import '../screens/notifications/notifications_history_screen.dart';
import '../screens/settings/chatbot_settings_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/profile/profile_screen.dart';

class AppRoutes {
  static Map<String, WidgetBuilder> routes = {
    '/login': (context) => const LoginScreen(),
    '/register': (context) => const RegisterScreen(),
    '/forgot-password': (context) => const ForgotPasswordScreen(),
    '/verify-email': (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      String email = '';
      String? code;
      if (args is String) {
        email = args;
      } else if (args is Map) {
        email = args['email'] as String? ?? '';
        code = args['code'] as String?;
      }
      return VerifyEmailScreen(initialEmail: email, initialCode: code);
    },
    '/home': (context) => const MainShell(),
    '/onboarding': (context) => const OnboardingScreen(),
    '/onboarding/profile': (context) => const OnboardingProfileScreen(),
    '/onboarding/plan': (context) => const OnboardingPlanScreen(),
    '/profile': (context) => const ProfileScreen(),
    '/exercise': (context) => const ExerciseScreen(),
    '/chatbot': (context) => const ChatbotScreen(),
    '/settings': (context) => const SettingsScreen(),
    '/settings/chatbot': (context) => const ChatbotSettingsScreen(),
    '/notifications/history': (context) => const NotificationsHistoryScreen(),
  };
}
