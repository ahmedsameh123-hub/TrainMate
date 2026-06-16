class AppConstants {
  static const String appName = "TrainMate";

  /// Optional hard override for backend URL.
  /// Keep empty for automatic fallback behavior.
  static const String devApiBaseUrlOverride = '';

  /// Single compile-time base URL for display/diagnostics.
  static String get compileTimeApiBaseUrl {
    final o = devApiBaseUrlOverride.trim();
    if (o.isNotEmpty) return o;
    return const String.fromEnvironment(
      'API_BASE_URL',
      // Default to host LAN IP so one build works on real device + emulator.
      defaultValue: 'http://172.20.10.3:8000',
    );
  }

  /// Candidate backend URLs.
  /// Order matters: explicit configuration first, then local defaults.
  static List<String> get apiBaseUrlCandidates {
    final seen = <String>{};
    final out = <String>[];
    void add(String v) {
      final n = v.trim();
      if (n.isEmpty) return;
      if (seen.add(n)) out.add(n);
    }

    add(devApiBaseUrlOverride);
    add(const String.fromEnvironment('API_BASE_URL'));
    add('http://172.20.10.3:8000'); // PC LAN / hotspot IP (real phone)
    add('http://10.0.2.2:8000'); // Android emulator -> host machine
    add('http://192.168.1.6:8000'); // Previous home Wi-Fi fallback
    add('http://192.168.137.1:8000'); // Windows hotspot fallback
    add('http://127.0.0.1:8000'); // iOS simulator / desktop local
    add('http://localhost:8000');
    return out;
  }
}
