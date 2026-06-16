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

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _auth = AuthService();
  final _user = UserService();
  final _sessionHydration = SessionHydrationService();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _auth.register(
        email: _email.text.trim(),
        password: _password.text,
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
      );
      if (!mounted) return;

      final token = result.accessToken;
      if (token != null && token.isNotEmpty) {
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
        return;
      }

      Navigator.pushReplacementNamed(
        context,
        '/verify-email',
        arguments: {
          'email': _email.text.trim(),
          if (result.verificationCode != null && result.verificationCode!.isNotEmpty)
            'code': result.verificationCode,
        },
      );
    } on ApiException catch (e) {
      setState(() => _error = e.toString());
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
        heroTitle: t.tr('auth.joinTitle'),
        heroSubtitle: t.tr('auth.joinSubtitle'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  t.tr('auth.register'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            CustomTextField(
              controller: _name,
              hint: t.tr('auth.nameHint'),
              label: t.tr('auth.nameOptional'),
              prefixIcon: Icons.person_outline_rounded,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
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
              hint: t.tr('auth.passwordHint'),
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
            ],
            const SizedBox(height: 28),
            CustomButton(
              text: _loading
                  ? t.tr('auth.creating')
                  : t.tr('auth.createAccount'),
              onPressed: _loading ? null : _register,
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
                      Icons.person_add_rounded,
                      size: 20,
                      color: theme.colorScheme.onPrimary,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
