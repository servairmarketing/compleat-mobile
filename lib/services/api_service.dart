import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// API base URL is selected at compile time via --dart-define=API_BASE=<url>.
// Default = prod, so an unflagged release build (current CI behavior) keeps
// pointing at prod with no other change. The test workflow passes the test
// Cloud Run URL via --dart-define.
const String API_BASE = String.fromEnvironment(
  'API_BASE',
  defaultValue:
      'https://compleat-inventory-api-793462624071.northamerica-northeast2.run.app',
);

// Environment label used by the UI to render a banner on non-prod builds so
// testers always know which backend they're hitting. Set via --dart-define=APP_ENV=test.
const String appEnvironment = String.fromEnvironment(
  'APP_ENV',
  defaultValue: 'prod',
);

class ApiService {
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  static Future<void> saveUserProfile(Map<String, dynamic> profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_profile', jsonEncode(profile));
  }

  static Future<Map<String, dynamic>?> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('user_profile');
    if (str == null) return null;
    return jsonDecode(str);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_profile');
  }

  static Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> body) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$API_BASE$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        await logout();
        return {'success': false, 'detail': 'session_expired'};
      }
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'detail': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$API_BASE$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        await logout();
        return {'error': 'session_expired'};
      }
      return jsonDecode(response.body);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$API_BASE/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      ).timeout(const Duration(seconds: 15));
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'detail': e.toString()};
    }
  }
}
