import 'dart:convert';

import '../models/register_result.dart';
import '../models/user_model.dart';
import 'api_service.dart';
import 'chatbot_sessions_store.dart';
import 'token_storage.dart';
import 'user_service.dart';
import 'workout_service.dart';

class AuthService {
  static bool isUnauthorizedError(Object error) {
    return error is ApiException &&
        (error.statusCode == 401 || error.statusCode == 403);
  }

  Future<void> invalidateSession() async {
    await TokenStorage.clear();
    await UserService.clearCachedMe();
    await WorkoutService.clearCachedWorkouts();
    await ChatbotSessionsStore.instance.resetForLogout();
  }

  Future<RegisterResult> register({
    required String email,
    required String password,
    String? name,
  }) async {
    final r = await ApiService.post(
      '/api/auth/register',
      body: {
        'email': email,
        'password': password,
        if (name != null && name.isNotEmpty) 'name': name,
      },
      auth: false,
    );
    if (r.statusCode == 201) {
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      final token = m['access_token'] as String?;
      if (token != null && token.isNotEmpty) {
        await TokenStorage.saveToken(token);
      }
      return RegisterResult(
        user: UserModel(
          id: m['id'] as int,
          email: m['email'] as String,
          name: m['name'] as String?,
        ),
        verificationCode: m['verification_code'] as String?,
        accessToken: token,
      );
    }
    throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
  }

  Future<void> login(String email, String password) async {
    final r = await ApiService.post(
      '/api/auth/login',
      body: {'email': email, 'password': password},
      auth: false,
    );
    if (r.statusCode == 200) {
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      final token = m['access_token'] as String;
      await TokenStorage.saveToken(token);
      return;
    }
    throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
  }

  Future<void> logout() async {
    await invalidateSession();
  }

  /// Confirms email with a one-time code; saves token if the API returns one.
  Future<void> verifyEmail({
    required String email,
    required String code,
  }) async {
    final r = await ApiService.post(
      '/api/auth/verify-email',
      body: {'email': email, 'code': code},
      auth: false,
    );
    if (r.statusCode == 200 || r.statusCode == 204) {
      if (r.body.isNotEmpty) {
        try {
          final m = jsonDecode(r.body) as Map<String, dynamic>;
          final token = m['access_token'] as String?;
          if (token != null && token.isNotEmpty) {
            await TokenStorage.saveToken(token);
          }
        } catch (_) {}
      }
      return;
    }
    throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
  }

  /// Returns an optional code when the server exposes it in the JSON body.
  Future<String?> resendVerification(String email) async {
    final r = await ApiService.post(
      '/api/auth/resend-verification',
      body: {'email': email},
      auth: false,
    );
    if (r.statusCode == 200 || r.statusCode == 202 || r.statusCode == 204) {
      if (r.body.isEmpty) return null;
      try {
        final m = jsonDecode(r.body) as Map<String, dynamic>;
        return m['verification_code'] as String?;
      } catch (_) {
        return null;
      }
    }
    throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
  }

  /// Asks the server to email a reset **code** (or link — server decides).
  /// Backend: `POST /api/auth/forgot-password` body: `{ "email": "..." }`
  /// Returns an optional reset code when the server exposes it in the JSON body.
  Future<String?> requestPasswordReset(String email) async {
    final r = await ApiService.post(
      '/api/auth/forgot-password',
      body: {'email': email},
      auth: false,
    );
    if (r.statusCode == 200 || r.statusCode == 202 || r.statusCode == 204) {
      if (r.body.isEmpty) return null;
      try {
        final m = jsonDecode(r.body) as Map<String, dynamic>;
        return m['password_reset_code'] as String?;
      } catch (_) {
        return null;
      }
    }
    throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
  }

  /// Completes reset using the code from email.
  /// Backend: `POST /api/auth/reset-password` body:
  /// `{ "email", "code", "new_password" }`
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final r = await ApiService.post(
      '/api/auth/reset-password',
      body: {
        'email': email,
        'code': code,
        'new_password': newPassword,
      },
      auth: false,
    );
    if (r.statusCode == 200 || r.statusCode == 204) {
      return;
    }
    throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
  }

  /// Returns true if token exists and /me succeeds.
  Future<bool> validateSession() async {
    final t = await TokenStorage.getToken();
    if (t == null || t.isEmpty) return false;
    try {
      final r = await ApiService.get('/api/users/me').timeout(
        const Duration(seconds: 6),
      );
      if (r.statusCode == 200) return true;
      if (r.statusCode == 401 || r.statusCode == 403) {
        await invalidateSession();
        return false;
      }
      // For non-auth failures (timeouts/proxy/backend issues), keep session.
      return true;
    } catch (_) {
      // Keep saved session on transient network/backend failures.
      // User can still be auto-logged once connectivity is back.
      return true;
    }
  }
}
