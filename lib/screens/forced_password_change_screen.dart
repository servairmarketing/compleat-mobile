import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import 'home_screen.dart';
import 'validation_dialog.dart';
import '../brand.dart';

class ForcedPasswordChangeScreen extends StatefulWidget {
  const ForcedPasswordChangeScreen({super.key});

  @override
  State<ForcedPasswordChangeScreen> createState() => _ForcedPasswordChangeScreenState();
}

class _ForcedPasswordChangeScreenState extends State<ForcedPasswordChangeScreen> {
  final _oldCtl = TextEditingController();
  final _newCtl = TextEditingController();
  final _confirmCtl = TextEditingController();
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _oldCtl.dispose();
    _newCtl.dispose();
    _confirmCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final oldPw = _oldCtl.text;
    final newPw = _newCtl.text;
    final confirmPw = _confirmCtl.text;
    final issues = <String>[];
    if (oldPw.isEmpty) issues.add('Current (temporary) password is required');
    if (newPw.isEmpty) {
      issues.add('New password is required');
    } else if (newPw.length < 8) {
      issues.add('New password must be at least 8 characters');
    }
    if (confirmPw.isEmpty) {
      issues.add('Confirm password is required');
    } else if (newPw.isNotEmpty && newPw != confirmPw) {
      issues.add('New password and confirm password do not match');
    }
    if (issues.isNotEmpty) {
      await showValidationDialog(context, issues);
      return;
    }
    setState(() => _loading = true);
    Map<String, dynamic> res;
    try {
      res = await ApiService.postRaw('/auth/change_password', {
        'old_password': oldPw,
        'new_password': newPw,
      });
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
        _error = 'Password change failed. Please try again.';
        _loading = false;
      });
      return;
    }
    if (res['success'] == true) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } else {
      setState(() {
        _error = (res['detail'] is String && (res['detail'] as String).isNotEmpty)
            ? res['detail']
            : 'Password change failed. Please try again.';
        _loading = false;
      });
    }
  }

  Widget _pwField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: TextInputType.visiblePassword,
      style: const TextStyle(fontSize: 17),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline, size: 24),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 24),
          tooltip: obscure ? 'Show password' : 'Hide password',
          onPressed: onToggle,
        ),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: kBrandColor,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Icon(Icons.lock, color: Colors.white, size: 56),
                const SizedBox(height: 12),
                const Text(
                  'Your password must be changed\nbefore continuing.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Choose a new password (at least 8 characters).',
                          style: TextStyle(color: Colors.black54, fontSize: 14),
                        ),
                        const SizedBox(height: 18),
                        _pwField(
                          controller: _oldCtl,
                          label: 'Current (temporary) password',
                          obscure: _obscureOld,
                          onToggle: () => setState(() => _obscureOld = !_obscureOld),
                        ),
                        const SizedBox(height: 14),
                        _pwField(
                          controller: _newCtl,
                          label: 'New password',
                          obscure: _obscureNew,
                          onToggle: () => setState(() => _obscureNew = !_obscureNew),
                        ),
                        const SizedBox(height: 14),
                        _pwField(
                          controller: _confirmCtl,
                          label: 'Confirm new password',
                          obscure: _obscureConfirm,
                          onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDECEA),
                              borderRadius: BorderRadius.circular(6),
                              border: const Border(left: BorderSide(color: Color(0xFFE53935), width: 4)),
                            ),
                            child: Text(_error!, style: const TextStyle(color: Color(0xFFC62828), fontSize: 14)),
                          ),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kBrandColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: _loading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text('Change Password',
                                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
