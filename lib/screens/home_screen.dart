import 'package:flutter/material.dart';
import 'printer_settings_screen.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'receive_screen.dart';
import 'production_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _userProfile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await ApiService.getUserProfile();
    setState(() => _userProfile = profile);
  }

  Future<void> _logout() async {
    await ApiService.logout();
    if (mounted) Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  void _navigate(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final name = _userProfile?['name'] ?? '';
    final role = _userProfile?['role'] ?? '';
    final modules = List<String>.from(_userProfile?['modules'] ?? []);
    final isAdmin = role == 'admin';

    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFF1c2128),
              child: Row(
                children: [
                  Image.asset('assets/images/logo-compleat.jpg', height: 36, fit: BoxFit.contain),
                  const SizedBox(width: 8),
                  Container(width: 1, height: 28, color: Colors.white24),
                  const SizedBox(width: 8),
                  Image.asset('assets/images/logo-servair.jpg', height: 36, fit: BoxFit.contain),
                  const Spacer(),
                  if (name.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(name, style: const TextStyle(
                            color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        Text(role, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.white54, size: 22),
                    onPressed: _logout,
                    tooltip: 'Logout',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const Text('Warehouse Operations',
                        style: TextStyle(color: Colors.white54, fontSize: 13,
                            letterSpacing: 1.0, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 16),

                    // Menu cards grid
                    if (modules.contains('receive') || isAdmin)
                      _MenuCard(
                        icon: Icons.download_rounded,
                        label: 'Receive',
                        description: 'Receive incoming parent rolls',
                        color: const Color(0xFF1a73e8),
                        onTap: () => _navigate(const ReceiveScreen()),
                      ),
                    if (modules.contains('production') || isAdmin)
                      _MenuCard(
                        icon: Icons.precision_manufacturing,
                        label: 'Production',
                        description: 'Start a production run',
                        color: const Color(0xFF0f9d58),
                        onTap: () => _navigate(const ProductionScreen()),
                      ),
                    _MenuCard(
                      icon: Icons.history_rounded,
                      label: 'History',
                      description: 'View recent transactions',
                      color: const Color(0xFFf4b400),
                      onTap: () => _navigate(const HistoryScreen()),
                    ),
                    _MenuCard(
                      icon: Icons.print_rounded,
                      label: 'Printer Settings',
                      description: 'Configure label printer',
                      color: const Color(0xFFe53935),
                      onTap: () => _navigate(const PrinterSettingsScreen()),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: const Color(0xFF1c2128),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(
                          color: Colors.white, fontSize: 18,
                          fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(description, style: const TextStyle(
                          color: Colors.white54, fontSize: 14)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.white24, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
