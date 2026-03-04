import 'package:flutter/material.dart';
import '../services/api_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map> _logs = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    final res = await ApiService.get('/audit/recent?limit=50');
    if (res['logs'] != null) {
      setState(() => _logs = List<Map>.from(res['logs']));
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadHistory,
            child: _logs.isEmpty
              ? const Center(child: Text('No history yet.', style: TextStyle(fontSize: 18, color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    final action = log['action']?.toString() ?? '—';
                    final module = log['module']?.toString() ?? '—';
                    final recordId = log['record_id']?.toString() ?? '—';
                    final timestamp = log['timestamp'] != null
                      ? DateTime.tryParse(log['timestamp'].toString())
                      : null;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _actionColor(action),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(action, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(module, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(recordId, style: const TextStyle(fontSize: 14, color: Colors.grey, fontFamily: 'monospace')),
                                  if (timestamp != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${timestamp.day}/${timestamp.month}/${timestamp.year} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2,'0')}',
                                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
    );
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'CREATE': return Colors.green;
      case 'UPDATE': return Colors.blue;
      case 'DELETE': return Colors.red;
      case 'SALE': return Colors.purple;
      case 'CONVERSION': return Colors.orange;
      default: return Colors.grey;
    }
  }
}
