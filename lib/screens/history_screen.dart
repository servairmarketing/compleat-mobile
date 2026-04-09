import 'package:flutter/material.dart';
import '../services/api_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // Receives state
  List<Map> _allRolls = [];
  List<_PoGroup> _groups = [];
  List<_PoGroup> _filteredGroups = [];
  final _searchController = TextEditingController();
  DateTime? _selectedDate;

  // Productions state (unchanged)
  List<Map> _productions = [];

  bool _loading = false;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    final profile = await ApiService.getUserProfile();
    final username = profile?['username'] ?? profile?['name'] ?? '';
    final isAdmin = profile?['role'] == 'admin';

    final rRes = await ApiService.get('/rolls/parents?limit=200');
    final pRes = await ApiService.get('/production/list?limit=50');

    if (rRes['rolls'] != null) {
      final all = List<Map>.from(rRes['rolls']);
      _allRolls = isAdmin
          ? all
          : all.where((r) => r['received_by']?.toString() == username).toList();
    }

    List<Map> newProductions = [];
    if (pRes['batches'] != null) {
      final all = List<Map>.from(pRes['batches']);
      newProductions = all
          .where((p) =>
              p['created_by']?.toString() == username ||
              p['produced_by']?.toString() == username)
          .toList();
    }

    setState(() {
      _productions = newProductions;
      _groups = _computeGroups();
      _filteredGroups = _filterGroups(_groups);
      _loading = false;
    });
  }

  List<_PoGroup> _computeGroups() {
    final Map<String, List<Map>> grouped = {};
    for (final roll in _allRolls) {
      final po = roll['po_number']?.toString() ?? '';
      final rawDate = roll['received_at']?.toString() ?? '';
      final dt = DateTime.tryParse(rawDate);
      final dateStr = dt != null
          ? '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}'
          : '';
      final key = '$po\x00$dateStr';
      grouped.putIfAbsent(key, () => []).add(roll);
    }

    final list = grouped.entries.map((e) {
      final sep = e.key.indexOf('\x00');
      final po = sep >= 0 ? e.key.substring(0, sep) : e.key;
      final date = sep >= 0 ? e.key.substring(sep + 1) : '';
      return _PoGroup(poNumber: po, date: date, rolls: e.value);
    }).toList();

    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  List<_PoGroup> _filterGroups(List<_PoGroup> groups) {
    final query = _searchController.text.trim().toLowerCase();
    return groups.where((g) {
      final matchesSearch =
          query.isEmpty || g.poNumber.toLowerCase().contains(query);
      final matchesDate = _selectedDate == null ||
          g.date ==
              '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
      return matchesSearch && matchesDate;
    }).toList();
  }

  void _applyFilters() {
    setState(() => _filteredGroups = _filterGroups(_groups));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _filteredGroups = _filterGroups(_groups);
      });
    }
  }

  void _clearDate() {
    setState(() {
      _selectedDate = null;
      _filteredGroups = _filterGroups(_groups);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a73e8),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('History',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: _innerBuild(context),
    );
  }

  Widget _innerBuild(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
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
                      ? _buildReceivesTab()
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
                color:
                    selected ? const Color(0xFF1a73e8) : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 20,
                  color: selected ? const Color(0xFF1a73e8) : Colors.grey),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color:
                          selected ? const Color(0xFF1a73e8) : Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Level 1 ────────────────────────────────────────────────────────────────

  Widget _buildReceivesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search by PO number...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_selectedDate != null) ...[
                TextButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                IconButton(
                  onPressed: _clearDate,
                  icon: const Icon(Icons.close, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ] else
                IconButton(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today),
                  tooltip: 'Filter by date',
                ),
            ],
          ),
        ),
        Expanded(
          child: _filteredGroups.isEmpty
              ? const Center(
                  child: Text('No receives found.',
                      style: TextStyle(fontSize: 18, color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: _filteredGroups.length,
                  itemBuilder: (context, i) {
                    final g = _filteredGroups[i];
                    final dt = DateTime.tryParse(g.date);
                    final dateLabel = dt != null
                        ? '${dt.day}/${dt.month}/${dt.year}'
                        : g.date;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        title: Text(
                          g.poNumber.isEmpty ? '(no PO)' : g.poNumber,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Text(dateLabel,
                            style: const TextStyle(fontSize: 14)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue[100],
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${g.rolls.length} roll${g.rolls.length == 1 ? '' : 's'}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[800],
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _PoRollsScreen(group: g),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Productions tab (unchanged logic) ──────────────────────────────────────

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

// ── Data class ──────────────────────────────────────────────────────────────

class _PoGroup {
  final String poNumber;
  final String date;
  final List<Map> rolls;
  _PoGroup({required this.poNumber, required this.date, required this.rolls});
}

// ── Level 2 — Rolls in PO ───────────────────────────────────────────────────

class _PoRollsScreen extends StatelessWidget {
  final _PoGroup group;
  const _PoRollsScreen({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.tryParse(group.date);
    final dateLabel =
        dt != null ? '${dt.day}/${dt.month}/${dt.year}' : group.date;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a73e8),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          group.poNumber.isEmpty
              ? '(no PO) · $dateLabel'
              : '${group.poNumber} · $dateLabel',
          style:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: group.rolls.length,
        itemBuilder: (context, i) {
          final r = group.rolls[i];
          final subtitle = [
            r['material_type']?.toString(),
            r['basis_weight']?.toString(),
            r['width'] != null ? '${r['width']}"' : null,
          ].whereType<String>().join(' · ');
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: Text(
                r['roll_id']?.toString() ?? '—',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  fontFamily: 'monospace',
                ),
              ),
              subtitle: Text(subtitle, style: const TextStyle(fontSize: 14)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _RollDetailScreen(roll: r),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Level 3 — Roll Detail ───────────────────────────────────────────────────

class _RollDetailScreen extends StatelessWidget {
  final Map roll;
  const _RollDetailScreen({super.key, required this.roll});

  @override
  Widget build(BuildContext context) {
    final ts = roll['received_at'] != null
        ? DateTime.tryParse(roll['received_at'].toString())
        : null;
    final receivedAtStr = ts != null
        ? '${ts.day}/${ts.month}/${ts.year} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}'
        : roll['received_at']?.toString() ?? '—';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a73e8),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          roll['roll_id']?.toString() ?? 'Roll Detail',
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _readField('Roll ID', roll['roll_id']?.toString()),
            _readField('Vendor', roll['vendor_id']?.toString()),
            _readField('PO Number', roll['po_number']?.toString()),
            _readField('Material Type', roll['material_type']?.toString()),
            _readField('Basis Weight', roll['basis_weight']?.toString()),
            _readField('Width (in)', roll['width']?.toString()),
            _readField('Length (ft)', roll['length']?.toString()),
            _readField('Weight (lbs)', roll['weight']?.toString()),
            _readField('Notes', roll['notes']?.toString()),
            _readField('Received At', receivedAtStr),
            _readField('Received By', roll['received_by']?.toString()),
          ],
        ),
      ),
    );
  }

  Widget _readField(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        initialValue: value ?? '—',
        readOnly: true,
        style: const TextStyle(fontSize: 16, color: Colors.black87),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: Colors.grey[100],
          contentPadding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        ),
      ),
    );
  }
}
