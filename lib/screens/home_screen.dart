import 'package:flutter/material.dart';
import 'settings_screen.dart';
import '../services/api_service.dart';
import '../services/update_service.dart';
import 'login_screen.dart';
import 'receive_screen.dart';
import 'production_screen.dart';
import 'sales_screen.dart';
import 'conversion_screen.dart';
import 'stocktake_screen.dart';
import 'history_screen.dart';
import '../brand.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _userProfile;
  double _downloadProgress = 0;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _checkForUpdate() async {
    final update = await UpdateService.checkForUpdate();
    print('DEBUG update result: $update');
    if (!mounted) return;
    if (update == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are on the latest version.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    final version = update['version'];
    final url = update['url'];
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Update Available'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version $version is available.'),
              if (_downloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _downloadProgress),
                const SizedBox(height: 8),
                Text('${(_downloadProgress * 100).toStringAsFixed(0)}% downloaded'),
              ],
            ],
          ),
          actions: _downloading ? [] : [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () {
                setDialogState(() => _downloading = true);
                setState(() => _downloading = true);
                UpdateService.downloadAndInstall(
                  url, version,
                  (progress) {
                    setDialogState(() => _downloadProgress = progress);
                    setState(() => _downloadProgress = progress);
                  },
                  (filePath) {
                    Navigator.pop(ctx);
                    setState(() { _downloading = false; _downloadProgress = 0; });
                    UpdateService.installApk(filePath);
                  },
                  (error) {
                    Navigator.pop(ctx);
                    setState(() { _downloading = false; _downloadProgress = 0; });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Update failed: $error')),
                    );
                  },
                );
              },
              child: const Text('Update Now'),
            ),
          ],
        ),
      ),
    );
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
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: kBrandColor,
              child: Row(
                children: [
                  Image.asset('assets/images/ComPleat_Logo_Mark.png',
                      height: 36, fit: BoxFit.contain),
                  const SizedBox(width: 12),
                  const Text('Com-Pleat IMS',
                      style: TextStyle(color: Colors.white, fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (name.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(name, style: const TextStyle(color: Colors.white,
                            fontSize: 13, fontWeight: FontWeight.bold)),
                        Text(role, style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('logoutButton'),
                    icon: const Icon(Icons.logout, color: Colors.white70, size: 22),
                    onPressed: _logout,
                    tooltip: 'Logout',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            if (appEnvironment != 'prod')
              Container(
                key: const Key('environmentBanner'),
                width: double.infinity,
                color: Colors.amber[800],
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                child: Text(
                  '${appEnvironment.toUpperCase()} ENVIRONMENT',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const Text('WAREHOUSE OPERATIONS',
                        style: TextStyle(color: Colors.black54, fontSize: 12,
                            letterSpacing: 1.2, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 14),
                    if (modules.contains('receive') || isAdmin)
                      _MenuCard(
                          key: const Key('menuCard_receive'),
                          icon: Icons.download_rounded, label: 'Receive',
                          description: 'Receive incoming parent rolls',
                          color: kBrandColor,
                          onTap: () => _navigate(const ReceiveScreen())),
                    if (modules.contains('production') || isAdmin)
                      _MenuCard(
                          key: const Key('menuCard_production'),
                          icon: Icons.precision_manufacturing, label: 'Production',
                          description: 'Start a production run',
                          color: const Color(0xFF0f9d58),
                          onTap: () => _navigate(const ProductionScreen())),
                    if (role == 'sales' || isAdmin || modules.contains('sales'))
                      _MenuCard(
                          key: const Key('menuCard_sales'),
                          icon: Icons.point_of_sale, label: 'Sales',
                          description: 'Sell child rolls to customers',
                          color: const Color(0xFF2e7d32),
                          onTap: () => _navigate(const SalesScreen())),
                    if (isAdmin || role == 'warehouse' || modules.contains('conversion'))
                      _MenuCard(
                          key: const Key('menuCard_conversion'),
                          icon: Icons.swap_horiz, label: 'Conversion',
                          description: 'Convert child rolls to different products',
                          color: const Color(0xFFef6c00),
                          onTap: () => _navigate(const ConversionScreen())),
                    if (isAdmin || role == 'warehouse' || modules.contains('stocktake'))
                      _MenuCard(
                          key: const Key('menuCard_stocktake'),
                          icon: Icons.assignment_turned_in,
                          label: 'Stock Take',
                          description: 'Add existing inventory or annual stock take',
                          color: const Color(0xFF00897B),
                          onTap: () => _navigate(const StocktakeScreen())),
                    _MenuCard(
                        key: const Key('menuCard_history'),
                        icon: Icons.history_rounded, label: 'History',
                        description: 'View recent transactions',
                        color: const Color(0xFFf4b400),
                        onTap: () => _navigate(const HistoryScreen())),
                    _MenuCard(
                        key: const Key('menuCard_settings'),
                        icon: Icons.settings, label: 'Settings',
                        description: 'Printer, password & device settings',
                        color: const Color(0xFF607D8B),
                        onTap: () => _navigate(const SettingsScreen())),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _downloading ? null : _checkForUpdate,
                  icon: _downloading
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.system_update),
                  label: Text(_downloading ? 'Downloading...' : 'Check for Update'),
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
  const _MenuCard({super.key, required this.icon, required this.label,
      required this.description, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        elevation: 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.black87,
                        fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(description, style: const TextStyle(
                        color: Colors.black54, fontSize: 14)),
                  ],
                )),
                const Icon(Icons.chevron_right, color: Colors.black26, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
