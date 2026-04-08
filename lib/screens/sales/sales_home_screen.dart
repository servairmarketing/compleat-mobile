import 'package:flutter/material.dart';
import 'sales_map_screen.dart';

class SalesHomeScreen extends StatelessWidget {
  const SalesHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFF1a73e8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
                  const Text('Sales & CRM',
                      style: TextStyle(color: Colors.white, fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const Text('TOOLS',
                        style: TextStyle(color: Colors.black54, fontSize: 12,
                            letterSpacing: 1.2, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 14),
                    _MenuCard(
                      icon: Icons.map_rounded,
                      label: 'Sales Map',
                      description: 'View customer accounts on a map',
                      color: const Color(0xFF7c3aed),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SalesMapScreen())),
                    ),
                    _MenuCard(
                      icon: Icons.business_rounded,
                      label: 'Accounts',
                      description: 'Manage customer accounts',
                      color: const Color(0xFF0f9d58),
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coming soon')),
                      ),
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
  const _MenuCard({required this.icon, required this.label,
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
