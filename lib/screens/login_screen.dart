import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/api_service.dart';
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
    final res = await ApiService.login(
      _usernameController.text.trim(),
      _passwordController.text.trim(),
    );
    if (res['token'] != null) {
      await ApiService.saveToken(res['token']);
      await ApiService.saveUserProfile(res['user'] ?? {});
      if (mounted) Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      setState(() { _error = res['detail'] ?? 'Login failed'; _loading = false; });
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
                          onSubmitted: (_) => _passwordFocusNode.requestFocus(),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          obscureText: true,
                          keyboardType: TextInputType.visiblePassword,
                          textInputAction: TextInputAction.done,
                          style: const TextStyle(fontSize: 18),
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock, size: 28),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                          ),
                          onSubmitted: (_) {
                            _signInFocusNode.requestFocus();
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
