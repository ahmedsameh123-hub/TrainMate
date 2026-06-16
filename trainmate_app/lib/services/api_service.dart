import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants.dart';
import 'token_storage.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiException($statusCode): $body';
}

class ApiService {
  ApiService._();

  static const Duration _requestTimeout = Duration(seconds: 12);
  static const Duration _fallbackProbeTimeout = Duration(seconds: 8);
  static String? _resolvedBaseUrl;

  static String _normalizeBase(String base) {
    return base.replaceAll(RegExp(r'/$'), '');
  }

  static Uri _uFromBase(String base, String path, [Map<String, String>? query]) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('${_normalizeBase(base)}$p').replace(queryParameters: query);
  }

  static Future<Map<String, String>> _headers({bool auth = false}) async {
    final h = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
    };
    if (auth) {
      final t = await TokenStorage.getToken();
      if (t != null && t.isNotEmpty) h['Authorization'] = 'Bearer $t';
    }
    return h;
  }

  static List<String> _candidateBases() {
    final configured = AppConstants.apiBaseUrlCandidates;
    final resolved = _resolvedBaseUrl;
    if (resolved == null || resolved.trim().isEmpty) return configured;
    return [resolved, ...configured.where((c) => c != resolved)];
  }

  static bool _hasExplicitBaseConfigured() {
    return AppConstants.devApiBaseUrlOverride.trim().isNotEmpty ||
        const String.fromEnvironment('API_BASE_URL').trim().isNotEmpty;
  }

  static Future<http.Response> _requestWithFallback({
    required String path,
    required Map<String, String> headers,
    required Future<http.Response> Function(Uri uri, Map<String, String> headers)
    perform,
    Duration? requestTimeout,
  }) async {
    Object? lastError;
    final candidates = _candidateBases();
    final explicitConfigured = _hasExplicitBaseConfigured();
    for (var i = 0; i < candidates.length; i++) {
      final base = candidates[i];
      try {
        final timeout = requestTimeout ??
            ((_resolvedBaseUrl != null && _resolvedBaseUrl == base) ||
                    (explicitConfigured && i == 0) ||
                    candidates.length == 1
                ? _requestTimeout
                : _fallbackProbeTimeout);
        final response = await perform(_uFromBase(base, path), headers).timeout(
          timeout,
        );
        _resolvedBaseUrl = base;
        return response;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError is TimeoutException) {
      throw ApiException(
        0,
        'Connection timed out while reaching backend. '
        'If you are on a real Android phone, run with --dart-define=API_BASE_URL=http://<YOUR_PC_LAN_IP>:8000',
      );
    }
    throw lastError ?? Exception('Unable to reach backend');
  }

  static Future<http.Response> get(String path, {bool auth = true}) async {
    final headers = await _headers(auth: auth);
    return _requestWithFallback(
      path: path,
      headers: headers,
      perform: (uri, h) => http.get(uri, headers: h),
    );
  }

  static Future<http.Response> post(
    String path, {
    Object? body,
    bool auth = false,
    Duration? requestTimeout,
  }) async {
    final headers = await _headers(auth: auth);
    return _requestWithFallback(
      path: path,
      headers: headers,
      requestTimeout: requestTimeout,
      perform: (uri, h) =>
          http.post(uri, headers: h, body: body == null ? null : jsonEncode(body)),
    );
  }

  static Future<http.Response> patch(
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    final headers = await _headers(auth: auth);
    return _requestWithFallback(
      path: path,
      headers: headers,
      perform: (uri, h) =>
          http.patch(uri, headers: h, body: body == null ? null : jsonEncode(body)),
    );
  }

  static Future<http.Response> delete(String path, {bool auth = true}) async {
    final headers = await _headers(auth: auth);
    return _requestWithFallback(
      path: path,
      headers: headers,
      perform: (uri, h) => http.delete(uri, headers: h),
    );
  }

  static String parseErrorBody(http.Response r) {
    try {
      final j = jsonDecode(r.body) as Map<String, dynamic>?;
      final d = j?['detail'];
      if (d is String) return d;
      if (d is List && d.isNotEmpty && d.first is Map) {
        final m = d.first as Map;
        return m['msg']?.toString() ?? r.body;
      }
    } catch (_) {}
    return r.body.isEmpty ? 'Request failed (${r.statusCode})' : r.body;
  }

  /// Raw `detail` when the API returns a JSON string (e.g. `EMAIL_NOT_VERIFIED`).
  static String? parseDetailString(http.Response r) {
    try {
      final j = jsonDecode(r.body) as Map<String, dynamic>?;
      final d = j?['detail'];
      if (d is String) return d;
    } catch (_) {}
    return null;
  }
}
