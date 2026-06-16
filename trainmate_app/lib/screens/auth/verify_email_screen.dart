import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_text.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../widgets/auth_shell.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_textfield.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    this.initialEmail = '',
    this.initialCode,
  });

  final String initialEmail;
  final String? initialCode;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _auth = AuthService();
  final _user = UserService();
  bool _loading = false;
  bool _resending = false;
  String? _error;
  String? _devCode;

  @override
  void initState() {
    super.initState();
    _email.text = widget.initialEmail;
    final code = widget.initialCode?.trim();
    if (code != null && code.isNotEmpty) {
      _devCode = code;
      _code.text = code;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _auth.verifyEmail(email: _email.text.trim(), code: _code.text.trim());
      if (!mounted) return;
      final me = await _user.getMe();
      if (!mounted) return;
      final target = me.needsOnboarding ? '/onboarding' : '/home';
      Navigator.pushNamedAndRemoveUntil(context, target, (_) => false);
    } on ApiException catch (e) {
      setState(() => _error = e.toString());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      final code = await _auth.resendVerification(_email.text.trim());
      if (!mounted) return;
      final t = AppText.of(context);
      setState(() {
        if (code != null && code.trim().isNotEmpty) {
          _devCode = code.trim();
          _code.text = code.trim();
        } else {
          _code.clear();
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            code != null && code.isNotEmpty
                ? t.tr('auth.codeShownInApp')
                : t.tr('auth.codeSent'),
          ),
        ),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.toString());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppText.of(context);

    return Scaffold(
      body: AuthShell(
        heroTitle: t.tr('auth.verifyTitle'),
        heroSubtitle: t.tr('auth.verifySubtitle'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  t.tr('auth.verifyTitle'),
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 20),
            CustomTextField(
              controller: _email,
              hint: t.tr('auth.emailHint'),
              label: t.tr('common.email'),
              prefixIcon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            if (_devCode != null && _devCode!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.tr('auth.codeShownInApp'),
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _devCode!,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            CustomTextField(
              controller: _code,
              hint: '000000',
              label: t.tr('auth.verificationCode'),
              prefixIcon: Icons.pin_rounded,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded, color: theme.colorScheme.error, size: 20),
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
              text: _loading ? t.tr('auth.verifying') : t.tr('auth.verify'),
              onPressed: _loading ? null : _verify,
              leading: _loading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : Icon(Icons.verified_user_rounded, size: 20, color: theme.colorScheme.onPrimary),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _resending
                  ? null
                  : () {
                      if (_email.text.trim().isEmpty) return;
                      _resend();
                    },
              child: Text(_resending ? t.tr('common.loading') : t.tr('auth.resendCode')),
            ),
          ],
        ),
      ),
    );
  }
}
