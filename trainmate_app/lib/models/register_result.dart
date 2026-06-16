import 'user_model.dart';

/// Result of [AuthService.register].
class RegisterResult {
  const RegisterResult({
    required this.user,
    this.verificationCode,
    this.accessToken,
  });

  final UserModel user;
  final String? verificationCode;
  final String? accessToken;
}
