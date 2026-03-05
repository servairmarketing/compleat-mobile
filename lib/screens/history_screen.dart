import 'package:flutter/material.dart';
import '../services/api_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map> _receives = [];
  List<Map> _productions = [];
  bool _loading = false;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    final profile = await ApiService.getUserProfile();
    final username = profile?['username'] ?? profile?['name'] ?? '';

    final rRes = await ApiService.get('/rolls/parents?limit=50');
    final pRes = await ApiService.get('/production/list?limit=50');

    if (rRes['rolls'] != null) {
      final all = List<Map>.from(rRes['rolls']);
      setState(() => _receives = all
          .where((r) => r['received_by']?.toString() == username)
          .toList());
    }

    if (pRes['batches'] != null) {
      final all = List<Map>.from(pRes['batches']);
      setState(() => _productions = all
          .where((p) =>
              p['created_by']?.toString() == username ||
              p['produced_by']?.toString() == username)
          .toList());
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              // Tab selector
              Container(
                color: Colors.white,
                child: Row(
                  children: [
                    _tabButton('Receives', 0, Icons.download_rounded),
                    _tabButton('Productions', 1, Icons.precision_manufacturing),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: _selectedTab == 0
                      ? _buildReceiveList()
                      : _buildProductionList(),
                ),
              ),
            ],
          );
  }

  Widget _tabButton(String label, int index, IconData icon) {
    final selected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? const Color(0xFF1a73e8) : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20,
                  color: selected ? const Color(0xFF1a73e8) : Colors.grey),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: selected ? const Color(0xFF1a73e8) : Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiveList() {
    if (_receives.isEmpty) {
      return const Center(
          child: Text('No receives found.',
              style: TextStyle(fontSize: 18, color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _receives.length,
      itemBuilder: (context, i) {
        final r = _receives[i];
        final ts = r['received_at'] != null
            ? DateTime.tryParse(r['received_at'].toString())
            : null;
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(r['roll_id']?.toString() ?? '—',
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace')),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(r['status']?.toString() ?? '—',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[800])),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Vendor: ${r['vendor_id'] ?? '—'}',
                    style:
                        const TextStyle(fontSize: 14, color: Colors.black87)),
                Text('Product: ${r['product_code'] ?? r['product_id'] ?? '—'}',
                    style:
                        const TextStyle(fontSize: 14, color: Colors.black87)),
                if (ts != null) ...[
                  const SizedBox(height: 4),
                  Text(
                      '${ts.day}/${ts.month}/${ts.year} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}',
                      style:
                          const TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductionList() {
    if (_productions.isEmpty) {
      return const Center(
          child: Text('No productions found.',
              style: TextStyle(fontSize: 18, color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _productions.length,
      itemBuilder: (context, i) {
        final p = _productions[i];
        final ts = p['created_at'] != null
            ? DateTime.tryParse(p['created_at'].toString())
            : null;
        final parentIds = (p['parent_roll_ids'] as List?)?.join(' / ') ??
            p['parent_roll_id']?.toString() ??
            '—';
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text('Parent: $parentIds',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace')),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('PRODUCTION',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[800])),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (p['items'] != null)
                  ...(p['items'] as List).map((item) => Text(
                      '${item['product_id']} × ${item['quantity']}',
                      style: const TextStyle(fontSize: 14)))
                else
                  Text(
                      '${p['child_product_id'] ?? '—'} × ${p['quantity'] ?? '—'}',
                      style: const TextStyle(fontSize: 14)),
                if (ts != null) ...[
                  const SizedBox(height: 4),
                  Text(
                      '${ts.day}/${ts.month}/${ts.year} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}',
                      style:
                          const TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
