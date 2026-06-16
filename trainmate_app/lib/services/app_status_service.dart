import 'dart:convert';

import 'api_service.dart';

/// Backend [GET /api/health] — no auth.
class AppStatusService {
  AppStatusService._();
  static final AppStatusService instance = AppStatusService._();

  Future<BackendHealth?> fetchBackendHealth() async {
    try {
      final r = await ApiService.get('/api/health', auth: false);
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return BackendHealth(
        status: j['status'] as String? ?? 'unknown',
        apiVersion: j['api_version'] as String?,
        build: j['build'] as String?,
        groqConfigured: j['groq_configured'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  /// [GET /api/ml/status] — no auth. True when Keras/pkl files exist on the backend.
  Future<bool?> fetchMlServerAvailable() async {
    try {
      final r = await ApiService.get('/api/ml/status', auth: false);
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return j['available'] as bool?;
    } catch (_) {
      return null;
    }
  }
}

class BackendHealth {
  BackendHealth({
    required this.status,
    this.apiVersion,
    this.build,
    required this.groqConfigured,
  });

  final String status;
  final String? apiVersion;
  final String? build;
  final bool groqConfigured;
}
