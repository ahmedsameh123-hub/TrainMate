import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_text.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth_shell.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_textfield.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _newPass = TextEditingController();
  final _confirmPass = TextEditingController();
  final _auth = AuthService();

  bool _loadingSend = false;
  bool _loadingConfirm = false;
  bool _codeSent = false;
  String? _error;
  String? _devResetCode;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _newPass.dispose();
    _confirmPass.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final t = AppText.of(context);
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = t.tr('auth.emailRequired'));
      return;
    }
    setState(() {
      _loadingSend = true;
      _error = null;
    });
    try {
      final resetCode = await _auth.requestPasswordReset(email);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        if (resetCode != null && resetCode.trim().isNotEmpty) {
          _devResetCode = resetCode.trim();
          _code.text = resetCode.trim();
        } else {
          _devResetCode = null;
          _code.clear();
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resetCode != null && resetCode.isNotEmpty
                ? t.tr('auth.codeShownInApp')
                : t.tr('auth.resetLinkSent'),
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loadingSend = false);
    }
  }

  Future<void> _confirmReset() async {
    final t = AppText.of(context);
    final email = _email.text.trim();
    final code = _code.text.trim();
    final p1 = _newPass.text;
    final p2 = _confirmPass.text;
    if (email.isEmpty) {
      setState(() => _error = t.tr('auth.emailRequired'));
      return;
    }
    if (code.isEmpty) {
      setState(() => _error = t.tr('auth.codeRequired'));
      return;
    }
    if (p1.length < 6) {
      setState(() => _error = t.tr('auth.passwordHint'));
      return;
    }
    if (p1 != p2) {
      setState(() => _error = t.tr('auth.passwordsDoNotMatch'));
      return;
    }
    setState(() {
      _loadingConfirm = true;
      _error = null;
    });
    try {
      await _auth.confirmPasswordReset(
        email: email,
        code: code,
        newPassword: p1,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.tr('auth.passwordResetSuccess'))),
      );
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loadingConfirm = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: AuthShell(
        heroTitle: t.tr('auth.resetPasswordTitle'),
        heroSubtitle: _codeSent
            ? t.tr('auth.resetPasswordStep2Hint')
            : t.tr('auth.resetPasswordHint'),
        child: SingleChildScrollView(
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
                  t.tr('auth.resetPasswordTitle'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
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
            if (!_codeSent) ...[
              const SizedBox(height: 24),
              CustomButton(
                text: _loadingSend
                    ? t.tr('common.loading')
                    : t.tr('auth.sendResetLink'),
                onPressed: _loadingSend ? null : _sendCode,
                leading: _loadingSend
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : Icon(
                        Icons.mark_email_unread_rounded,
                        size: 20,
                        color: theme.colorScheme.onPrimary,
                      ),
              ),
            ],
            if (_codeSent) ...[
              const SizedBox(height: 8),
              if (_devResetCode != null && _devResetCode!.isNotEmpty) ...[
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
                        _devResetCode!,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ] else
                Text(
                  t.tr('auth.checkSpamFolder'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: _code,
                hint: '000000',
                label: t.tr('auth.resetCodeLabel'),
                prefixIcon: Icons.pin_rounded,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
              ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: _newPass,
                hint: t.tr('auth.passwordHint'),
                label: t.tr('settings.newPassword'),
                obscure: true,
                prefixIcon: Icons.lock_outline_rounded,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: _confirmPass,
                hint: t.tr('auth.passwordHint'),
                label: t.tr('auth.confirmNewPassword'),
                obscure: true,
                prefixIcon: Icons.lock_outline_rounded,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 24),
              CustomButton(
                text: _loadingConfirm
                    ? t.tr('common.saving')
                    : t.tr('auth.setNewPassword'),
                onPressed: _loadingConfirm ? null : _confirmReset,
                leading: _loadingConfirm
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : Icon(
                        Icons.check_circle_rounded,
                        size: 20,
                        color: theme.colorScheme.onPrimary,
                      ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _loadingSend ? null : _sendCode,
                child: Text(
                  _loadingSend
                      ? t.tr('common.loading')
                      : t.tr('auth.resendResetEmail'),
                ),
              ),
            ],
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
            ],
          ),
        ),
      ),
    );
  }
}
