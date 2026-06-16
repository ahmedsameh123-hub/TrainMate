import 'package:flutter/material.dart';

import '../../l10n/app_text.dart';
import '../../services/user_service.dart';
import 'onboarding_plan_screen.dart';
import 'onboarding_profile_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _user = UserService();
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _routeToStep();
  }

  Route<void> _slideRoute(Widget page) {
    return PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: const Duration(milliseconds: 320),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final offset =
            Tween<Offset>(
              begin: const Offset(0.14, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
        return SlideTransition(
          position: offset,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );
  }

  Future<void> _routeToStep() async {
    try {
      final cached = await _user.getCachedMe();
      if (cached != null && mounted) {
        final route = cached.needsProfileStep
            ? _slideRoute(const OnboardingProfileScreen())
            : _slideRoute(const OnboardingPlanScreen());
        Navigator.of(context).pushReplacement(route);
        return;
      }
      final me = await _user.getMe().timeout(const Duration(seconds: 8));
      if (!mounted) return;
      final route = me.needsProfileStep
          ? _slideRoute(const OnboardingProfileScreen())
          : _slideRoute(const OnboardingPlanScreen());
      Navigator.of(context).pushReplacement(route);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppText.of(context);
    return Scaffold(
      body: Center(
        child: _loading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(t.tr('onboarding.preparing')),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _failed
                        ? t.tr('onboarding.failed')
                        : t.tr('onboarding.unexpected'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/home',
                      (_) => false,
                    ),
                    child: Text(t.tr('onboarding.goHome')),
                  ),
                ],
              ),
      ),
    );
  }
}
