import 'package:flutter/material.dart';
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
  int _selectedIndex = 0;
  Map<String, dynamic>? _userProfile;
  List<_NavItem> _navItems = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await ApiService.getUserProfile();
    setState(() {
      _userProfile = profile;
      _navItems = _buildNavItems(profile);
    });
  }

  List<_NavItem> _buildNavItems(Map<String, dynamic>? profile) {
    final modules = List<String>.from(profile?['modules'] ?? []);
    final role = profile?['role']?.toString() ?? '';
    final items = <_NavItem>[];

    if (modules.contains('receive') || role == 'admin') {
      items.add(_NavItem(
        label: 'Receive',
        icon: Icons.download_rounded,
        screen: const ReceiveScreen(),
      ));
    }

    if (modules.contains('production') || role == 'admin') {
      items.add(_NavItem(
        label: 'Production',
        icon: Icons.precision_manufacturing,
        screen: const ProductionScreen(),
      ));
    }

    items.add(_NavItem(
      label: 'History',
      icon: Icons.history,
      screen: const HistoryScreen(),
    ));

    return items;
  }

  Future<void> _logout() async {
    await ApiService.logout();
    if (mounted) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_navItems.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a73e8),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Image.asset('assets/images/logo-compleat.jpg', height: 32, fit: BoxFit.contain),
            const SizedBox(width: 10),
            Image.asset('assets/images/logo-servair.jpg', height: 32, fit: BoxFit.contain),
          ],
        ),
        actions: [
          if (_userProfile != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_userProfile!['name'] ?? '',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    Text(_userProfile!['role'] ?? '',
                        style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  ],
                ),
              ),
            ),
          IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _logout,
              tooltip: 'Logout'),
        ],
      ),
      body: _navItems[_selectedIndex].screen,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        selectedItemColor: const Color(0xFF1a73e8),
        unselectedItemColor: Colors.grey,
        selectedFontSize: 14,
        unselectedFontSize: 12,
        iconSize: 32,
        items: _navItems
            .map((item) => BottomNavigationBarItem(
                  icon: Icon(item.icon),
                  label: item.label,
                ))
            .toList(),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final Widget screen;
  _NavItem({required this.label, required this.icon, required this.screen});
}
