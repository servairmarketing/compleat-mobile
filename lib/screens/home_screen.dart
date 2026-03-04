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
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  final List<Widget> _screens = [
    const ReceiveScreen(),
    const ProductionScreen(),
    const HistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a73e8),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            const Icon(Icons.inventory_2, size: 28),
            const SizedBox(width: 8),
            const Text('Com-Pleat IMS', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          if (_userProfile != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(child: Text(_userProfile!['name'] ?? '', style: const TextStyle(fontSize: 14))),
            ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout, tooltip: 'Logout'),
        ],
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        selectedItemColor: const Color(0xFF1a73e8),
        unselectedItemColor: Colors.grey,
        selectedFontSize: 14,
        unselectedFontSize: 12,
        iconSize: 32,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.download_rounded), label: 'Receive'),
          BottomNavigationBarItem(icon: Icon(Icons.precision_manufacturing), label: 'Production'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }
}
