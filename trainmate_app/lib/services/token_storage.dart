import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  static const _key = 'trainmate_access_token';

  static Future<void> saveToken(String token) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, token);
  }

  static Future<String?> getToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_key);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}
