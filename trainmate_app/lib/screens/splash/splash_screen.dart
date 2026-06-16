import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/colors.dart';
import '../../l10n/app_text.dart';
import '../../services/app_sync_signal.dart';
import '../../services/auth_service.dart';
import '../../services/session_hydration_service.dart';
import '../../services/user_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  final _auth = AuthService();
  final _user = UserService();
  final _sessionHydration = SessionHydrationService();
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(
      begin: 0.985,
      end: 1.025,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _entered = true);
    });
    _go();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    bool ok = false;
    try {
      ok = await _auth.validateSession();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    try {
      final lang = Localizations.localeOf(context).languageCode;
      try {
        await _sessionHydration.hydrate(languageCode: lang);
      } catch (_) {}
      final me = await _user.getMe();
      AppSyncSignal.notifyRefresh();
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        me.needsOnboarding ? '/onboarding' : '/home',
      );
    } catch (e) {
      if (!mounted) return;
      if (AuthService.isUnauthorizedError(e)) {
        await _auth.invalidateSession();
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.splashGradient,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                opacity: _entered ? 1 : 0,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 500),
                  offset: _entered ? Offset.zero : const Offset(0, 0.08),
                  curve: Curves.easeOutCubic,
                  child: ScaleTransition(
                    scale: _pulseScale,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        color: Colors.white.withValues(alpha: 0.14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 26,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: 118,
                          height: 118,
                          child: Image.asset(
                            'assets/images/splash_logo.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.fitness_center_rounded,
                              size: 56,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'TrainMate',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t.tr('splash.tag'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 40),
              Text(
                t.tr('common.loading'),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.75),
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
