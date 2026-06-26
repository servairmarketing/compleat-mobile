import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../services/api_service.dart';
import '../services/field_focus.dart';
import 'forced_password_change_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _signInFocusNode = FocusNode();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _usernameFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _signInFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _version = 'v${info.version}');
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    Map<String, dynamic> res;
    try {
      res = await ApiService.loginRaw(
        _usernameController.text.trim(),
        _passwordController.text.trim(),
      );
    } on SocketException {
      setState(() {
        _error = 'Cannot reach server. Please check your network connection and try again.';
        _loading = false;
      });
      return;
    } on http.ClientException {
      setState(() {
        _error = 'Cannot reach server. Please check your network connection and try again.';
        _loading = false;
      });
      return;
    } catch (_) {
      setState(() {
        _error = 'Login failed. Please try again.';
        _loading = false;
      });
      return;
    }
    if (res['token'] != null) {
      await ApiService.saveToken(res['token']);
      await ApiService.saveUserProfile(res['user'] ?? {});
      // Best-effort: cache effective permissions for UX gating (non-fatal —
      // mirrors web index.html; backend remains the real gate).
      final uid = (res['user'] ?? {})['uid'];
      if (uid is String && uid.isNotEmpty) {
        try { await ApiService.refreshPermissions(uid); } catch (_) {}
      }
      final mustChange = res['must_change_password'] == true;
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => mustChange
              ? const ForcedPasswordChangeScreen()
              : const HomeScreen(),
        ),
      );
    } else {
      setState(() {
        _error = res['detail'] is String && (res['detail'] as String).isNotEmpty
            ? res['detail']
            : 'Login failed. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a73e8),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/images/ComPleat_Logo_Mark.png',
                    height: 80, fit: BoxFit.contain),
                const SizedBox(height: 16),
                const Text('Com-Pleat IMS',
                    style: TextStyle(color: Colors.white, fontSize: 28,
                        fontWeight: FontWeight.bold)),
                const Text('Inventory Management System',
                    style: TextStyle(color: Colors.white70, fontSize: 15)),
                const SizedBox(height: 40),
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        TextField(
                          key: const Key('usernameField'),
                          controller: _usernameController,
                          focusNode: _usernameFocusNode,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(fontSize: 18),
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person, size: 28),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                          ),
                          // Bug #11 — consistent delayed auto-advance.
                          onSubmitted: (_) =>
                              FieldFocus.advance(context, target: _passwordFocusNode),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          key: const Key('passwordField'),
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          obscureText: _obscurePassword,
                          keyboardType: TextInputType.visiblePassword,
                          textInputAction: TextInputAction.done,
                          style: const TextStyle(fontSize: 18),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock, size: 28),
                            suffixIcon: IconButton(
                              key: const Key('passwordVisibilityToggle'),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                size: 26,
                              ),
                              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                          ),
                          onSubmitted: (_) {
                            FieldFocus.advance(context, target: _signInFocusNode);
                            _login();
                          },
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 16)),
                        ],
                        const SizedBox(height: 24),
                        Focus(
                          focusNode: _signInFocusNode,
                          child: SizedBox(
                            width: double.infinity, height: 56,
                            child: ElevatedButton(
                              key: const Key('signInButton'),
                              onPressed: _loading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1a73e8),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: _loading
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Text('Sign In', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _version,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
