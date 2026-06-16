import 'package:flutter/material.dart';

import '../../l10n/app_text.dart';
import '../../services/api_service.dart';
import '../../services/app_sync_signal.dart';
import '../../services/auth_service.dart';
import '../../services/session_hydration_service.dart';
import '../../services/user_service.dart';
import '../../widgets/auth_shell.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_textfield.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _auth = AuthService();
  final _user = UserService();
  final _sessionHydration = SessionHydrationService();
  bool _loading = false;
  String? _error;
  bool _suggestVerifyEmail = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _looksLikeUnverifiedEmail(ApiException e) {
    final b = e.body.toUpperCase();
    return e.statusCode == 403 ||
        b.contains('NOT_VERIFIED') ||
        b.contains('EMAIL_NOT_VERIFIED') ||
        (b.contains('VERIFY') && b.contains('EMAIL'));
  }

  String _loginErrorMessage(ApiException e, AppText t) {
    final body = e.body.toLowerCase();
    if (_looksLikeUnverifiedEmail(e)) {
      return t.tr('auth.loginEmailNotVerified');
    }
    if (body.contains('no account') || body.contains('register first')) {
      return t.tr('auth.loginNoAccount');
    }
    if (body.contains('wrong password')) {
      return t.tr('auth.loginWrongPassword');
    }
    return e.body.isNotEmpty ? e.body : 'Login failed (${e.statusCode})';
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    final password = _password.text;
    final validEmail = email.contains('@') && email.split('@').last.contains('.');
    if (!validEmail) {
      setState(() {
        _error = 'Please enter a valid email address.';
        _suggestVerifyEmail = false;
      });
      return;
    }
    if (password.isEmpty) {
      setState(() {
        _error = 'Please enter your password.';
        _suggestVerifyEmail = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _suggestVerifyEmail = false;
    });
    try {
      await _auth.login(email, password);
      if (!mounted) return;
      final lang = Localizations.localeOf(context).languageCode;
      try {
        await _sessionHydration.hydrate(languageCode: lang);
      } catch (_) {
        // Keep login resilient: screens still do their own fetch.
      }
      final me = await _user.getMe();
      AppSyncSignal.notifyRefresh();
      if (!mounted) return;
      final target = me.needsOnboarding ? '/onboarding' : '/home';
      Navigator.pushReplacementNamed(context, target);
    } on ApiException catch (e) {
      if (!mounted) return;
      final t = AppText.of(context);
      setState(() {
        _error = _loginErrorMessage(e, t);
        _suggestVerifyEmail = _looksLikeUnverifiedEmail(e);
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppText.of(context);

    return Scaffold(
      body: AuthShell(
        heroTitle: t.tr('auth.welcomeBack'),
        heroSubtitle: t.tr('auth.signInSubtitle'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.tr('auth.signIn'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 24),
            CustomTextField(
              controller: _email,
              hint: 'you@example.com',
              label: t.tr('common.email'),
              prefixIcon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: _password,
              hint: '••••••••',
              label: t.tr('common.password'),
              obscure: true,
              prefixIcon: Icons.lock_outline_rounded,
              textInputAction: TextInputAction.done,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: theme.colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_suggestVerifyEmail) ...[
                const SizedBox(height: 10),
                Text(
                  t.tr('auth.loginEmailNotVerified'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _email.text.trim().isEmpty
                        ? null
                        : () {
                            Navigator.pushNamed(
                              context,
                              '/verify-email',
                              arguments: _email.text.trim(),
                            );
                          },
                    icon: const Icon(Icons.mark_email_read_outlined, size: 18),
                    label: Text(t.tr('auth.goToVerifyEmail')),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 28),
            CustomButton(
              text: _loading ? t.tr('auth.signingIn') : t.tr('auth.signIn'),
              onPressed: _loading ? null : _login,
              leading: _loading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : Icon(
                      Icons.login_rounded,
                      size: 20,
                      color: theme.colorScheme.onPrimary,
                    ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pushNamed(context, '/forgot-password'),
                child: Text(t.tr('auth.forgotPassword')),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  t.tr('auth.newHere'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/register'),
                  child: Text(t.tr('auth.createAccount')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
