import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme.dart';
import 'routes/app_routes.dart';
import 'services/app_preferences_service.dart';
import 'services/notification_service.dart';
import 'screens/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPreferencesService.instance.load();
  await NotificationService.instance.init();
  if (AppPreferencesService.instance.notificationsEnabled) {
    try {
      await NotificationService.instance.scheduleDailyWorkoutReminder(
        arabic: AppPreferencesService.instance.locale.languageCode == 'ar',
        hour: AppPreferencesService.instance.notificationHour,
        minute: AppPreferencesService.instance.notificationMinute,
      );
    } catch (_) {
      // Never block app startup because of notification scheduling failures.
    }
  }
  runApp(const TrainMateApp());
}

class TrainMateApp extends StatelessWidget {
  const TrainMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppPreferencesService.instance,
      builder: (context, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: "TrainMate",
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: AppPreferencesService.instance.themeMode,
          locale: AppPreferencesService.instance.locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routes: AppRoutes.routes,
          home: const SplashScreen(),
        );
      },
    );
  }
}
