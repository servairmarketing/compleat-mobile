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
    await prefs.remove('effective_permissions');
  }

  // ── Permissions (UX gating only — the backend is the real gate) ──
  // Mirrors the web's effectivePermissions cache: a flat { "entity:action":
  // bool } map fetched best-effort at login. Admins bypass. If the map didn't
  // load (e.g. the effective-permissions endpoint needs users:view, which a
  // warehouse user lacks), hasPermission returns false for non-admins — the
  // same known frontend-enforcement gap as web (backlog #17). NEVER rely on
  // this for security; it only decides whether to SHOW an affordance.
  static Future<void> savePermissions(Map<String, dynamic> perms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('effective_permissions', jsonEncode(perms));
  }

  static Future<Map<String, dynamic>> getPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('effective_permissions');
    if (str == null) return {};
    try {
      final d = jsonDecode(str);
      return d is Map<String, dynamic> ? d : {};
    } catch (_) {
      return {};
    }
  }

  // Best-effort: fetch + cache the logged-in user's effective permissions.
  // Non-fatal — login proceeds even if this fails (returns false).
  static Future<bool> refreshPermissions(String uid) async {
    final res = await get('/users/$uid/effective-permissions');
    if (res['permissions'] is Map) {
      await savePermissions(Map<String, dynamic>.from(res['permissions']));
      return true;
    }
    return false;
  }

  static Future<bool> hasPermission(String entity, String action) async {
    final profile = await getUserProfile();
    if (profile != null && profile['role'] == 'admin') return true;
    final perms = await getPermissions();
    return perms['$entity:$action'] == true;
  }

  // Bug #31 — a 5xx from Cloud Run can return an HTML / plain-text error page
  // instead of JSON. jsonDecode then throws "FormatException: Unexpected
  // character (at character 1)", which used to surface raw in the UI. Decode
  // defensively and return a clean, user-facing message instead.
  static const String serverErrorMessage =
      'Server error. Please try again or contact admin.';

  static Map<String, dynamic> _decodeBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      // Valid JSON but not an object (array / string / number) — not something
      // a caller can act on; treat it as a server error.
      return {'success': false, 'detail': serverErrorMessage};
    } on FormatException {
      return {'success': false, 'detail': serverErrorMessage};
    }
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
      return _decodeBody(response.body);
    } catch (e) {
      return {'success': false, 'detail': e.toString()};
    }
  }

  // Like post(), but does NOT swallow network exceptions — callers can catch
  // SocketException / ClientException to render a clean message instead of a
  // raw exception string. Still handles the 401 auto-logout case.
  static Future<Map<String, dynamic>> postRaw(String endpoint, Map<String, dynamic> body) async {
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
    return _decodeBody(response.body);
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
      // get() keeps its {'error': ...} failure shape; a non-JSON body falls
      // through to the catch below (callers of get() check ['error']).
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
      return _decodeBody(response.body);
    } catch (e) {
      return {'success': false, 'detail': e.toString()};
    }
  }

  // Like login(), but does NOT swallow network exceptions — callers can catch
  // SocketException / ClientException to render a clean message instead of a
  // raw exception string.
  static Future<Map<String, dynamic>> loginRaw(String username, String password) async {
    final response = await http.post(
      Uri.parse('$API_BASE/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    ).timeout(const Duration(seconds: 15));
    return _decodeBody(response.body);
  }
}
