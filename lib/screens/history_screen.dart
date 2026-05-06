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

  // Productions state
  List<Map> _productions = [];
  List<Map> _products = [];

  // Sales state
  List<Map> _sales = [];

  // Conversions state
  List<Map> _conversions = [];

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

    final rRes = await ApiService.get('/rolls/parents?limit=200');
    final pRes = await ApiService.get('/production/list?limit=50');
    final mRes = await ApiService.get('/masters/products');
    final sRes = await ApiService.get('/sales/list?limit=50');
    final cRes = await ApiService.get('/conversion/list?limit=50');

    if (rRes['rolls'] != null) {
      _allRolls = List<Map>.from(rRes['rolls']);
    }

    List<Map> newProductions = [];
    if (pRes['batches'] != null) {
      newProductions = List<Map>.from(pRes['batches']);
    }

    List<Map> newProducts = [];
    if (mRes['records'] != null) {
      newProducts = List<Map>.from(mRes['records']);
    }

    List<Map> newSales = [];
    if (sRes['sales'] != null) {
      newSales = List<Map>.from(sRes['sales']);
    }

    List<Map> newConversions = [];
    if (cRes['conversions'] != null) {
      newConversions = List<Map>.from(cRes['conversions']);
    }

    setState(() {
      _productions = newProductions;
      _products = newProducts;
      _sales = newSales;
      _conversions = newConversions;
      _groups = _computeGroups();
      _filteredGroups = _filterGroups(_groups);
      _loading = false;
    });
  }

  Map<String, dynamic> _productById(String? id) {
    if (id == null || id.isEmpty) return {};
    for (final p in _products) {
      if (p['product_id']?.toString() == id) return Map<String, dynamic>.from(p);
    }
    return {};
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
                    _tabButton('Sales', 2, Icons.point_of_sale),
                    _tabButton('Conversions', 3, Icons.swap_horiz),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: _selectedTab == 0
                      ? _buildReceivesTab()
                      : _selectedTab == 1
                          ? _buildProductionList()
                          : _selectedTab == 2
                              ? _buildSalesList()
                              : _buildConversionsList(),
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

  // ── Productions tab — Level 1 list ─────────────────────────────────────────

  Widget _buildProductionList() {
    if (_productions.isEmpty) {
      return const Center(
          child: Text('No productions found.',
              style: TextStyle(fontSize: 18, color: Colors.grey)));
    }

    final sorted = List<Map>.from(_productions);
    sorted.sort((a, b) {
      final ta = a['created_at']?.toString() ?? '';
      final tb = b['created_at']?.toString() ?? '';
      return tb.compareTo(ta);
    });

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: sorted.length,
      itemBuilder: (context, i) {
        final p = sorted[i];
        final ts = p['created_at'] != null
            ? DateTime.tryParse(p['created_at'].toString())
            : null;
        final dateLabel = ts != null
            ? '${ts.day}/${ts.month}/${ts.year} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}'
            : '—';
        final parents = (p['parent_roll_ids'] as List?)?.join(', ') ?? '—';
        final productId = p['product_id']?.toString() ?? '—';
        final qty = p['quantity']?.toString() ?? '—';
        final status = p['status']?.toString() ?? 'in_stock';
        final badgeColors = _statusBadgeColors(status);

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _ProductionDetailScreen(
                  roll: p,
                  product: _productById(p['product_id']?.toString()),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          productId,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace'),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: badgeColors.$1,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: badgeColors.$2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('× $qty',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Parent: $parents',
                      style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          fontFamily: 'monospace')),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(dateLabel,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.grey)),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Sales tab — Level 1 list ───────────────────────────────────────────────

  Widget _buildSalesList() {
    if (_sales.isEmpty) {
      return const Center(
          child: Text('No sales found.',
              style: TextStyle(fontSize: 18, color: Colors.grey)));
    }

    final sorted = List<Map>.from(_sales);
    sorted.sort((a, b) {
      final ta = a['sold_at']?.toString() ?? '';
      final tb = b['sold_at']?.toString() ?? '';
      return tb.compareTo(ta);
    });

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: sorted.length,
      itemBuilder: (context, i) {
        final s = sorted[i];
        final ts = s['sold_at'] != null
            ? DateTime.tryParse(s['sold_at'].toString())
            : null;
        final dateLabel = ts != null
            ? '${ts.day}/${ts.month}/${ts.year} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}'
            : '—';
        final items = (s['items'] as List?) ?? const [];
        final itemCount = items.length;
        int totalQty = 0;
        for (final it in items) {
          if (it is Map && it['quantity'] is num) {
            totalQty += (it['quantity'] as num).toInt();
          }
        }
        final company = s['company']?.toString() ?? '';
        final companyLabel = company == 'compleat'
            ? 'Com-Pleat'
            : company == 'servair'
                ? 'Servair'
                : company.toUpperCase();
        final customerName = s['customer_name']?.toString().isNotEmpty == true
            ? s['customer_name'].toString()
            : (s['customer_id']?.toString() ?? '—');
        final invoice = s['invoice_number']?.toString() ?? '—';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _SaleDetailScreen(sale: s),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          customerName,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'SOLD',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Invoice: $invoice',
                      style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                          fontFamily: 'monospace')),
                  const SizedBox(height: 4),
                  Text(
                      '$companyLabel · $itemCount line${itemCount == 1 ? '' : 's'}'
                      ' · $totalQty roll${totalQty == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 13, color: Colors.black54)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(dateLabel,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.grey)),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static (Color, Color) _statusBadgeColors(String status) {
    switch (status) {
      case 'in_stock':
        return (Colors.green.shade100, Colors.green.shade800);
      case 'sold':
        return (Colors.red.shade100, Colors.red.shade800);
      case 'converted':
        return (Colors.blue.shade100, Colors.blue.shade800);
      default:
        return (Colors.blue.shade100, Colors.blue.shade800);
    }
  }

  // ── Conversions tab — Level 1 list ─────────────────────────────────────────
  Widget _buildConversionsList() {
    if (_conversions.isEmpty) {
      return const Center(
          child: Text('No conversions found.',
              style: TextStyle(fontSize: 18, color: Colors.grey)));
    }

    final sorted = List<Map>.from(_conversions);
    sorted.sort((a, b) {
      final ta = a['converted_at']?.toString() ?? '';
      final tb = b['converted_at']?.toString() ?? '';
      return tb.compareTo(ta);
    });

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: sorted.length,
      itemBuilder: (context, i) {
        final c = sorted[i];
        final ts = c['converted_at'] != null
            ? DateTime.tryParse(c['converted_at'].toString())
            : null;
        final dateLabel = ts != null
            ? '${ts.day}/${ts.month}/${ts.year} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}'
            : '—';
        final newProduct = c['new_product_id']?.toString() ?? '—';
        final sourceProduct = c['source_product_id']?.toString() ?? '—';
        final sourceParents = (c['source_parent_roll_ids'] as List?)
                ?.map((e) => e.toString())
                .join(' + ') ??
            '—';
        final qty = c['quantity']?.toString() ?? '—';
        final statusAfter = c['source_status_after']?.toString() ?? '';
        final badgeColors = statusAfter == 'finished'
            ? (Colors.red.shade100, Colors.red.shade800)
            : (Colors.orange.shade100, Colors.orange.shade800);

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _ConversionDetailScreen(
                  conv: c,
                  newProduct: _productById(newProduct),
                  sourceProduct: _productById(sourceProduct),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          newProduct,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace'),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: badgeColors.$1,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'SOURCE ${statusAfter.toUpperCase()}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: badgeColors.$2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('× $qty new roll${qty == "1" ? "" : "s"}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('From: $sourceProduct',
                      style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          fontFamily: 'monospace')),
                  const SizedBox(height: 2),
                  Text('Parents: $sourceParents',
                      style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          fontFamily: 'monospace')),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(dateLabel,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.grey)),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ],
              ),
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

// ── Production Detail (Level 2) ─────────────────────────────────────────────

class _ProductionDetailScreen extends StatelessWidget {
  final Map roll;
  final Map<String, dynamic> product;
  const _ProductionDetailScreen({required this.roll, required this.product});

  @override
  Widget build(BuildContext context) {
    final ts = roll['created_at'] != null
        ? DateTime.tryParse(roll['created_at'].toString())
        : null;
    final createdAtStr = ts != null
        ? '${ts.day}/${ts.month}/${ts.year} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}'
        : roll['created_at']?.toString() ?? '—';

    final parentList = (roll['parent_roll_ids'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    final productId = roll['product_id']?.toString() ?? '';
    final displayRollId = productId.isEmpty
        ? '—'
        : '$productId-${parentList.join('-')}';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a73e8),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          roll['roll_id']?.toString() ?? 'Production Detail',
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
            _readField('Roll ID (system)', roll['roll_id']?.toString()),
            _readField('Display Roll ID', displayRollId),
            _readField('Product ID', productId),
            _readField('Product Name', product['product_name']?.toString()),
            _readField('Material Type',
                (roll['material_type'] ?? product['material_type'])?.toString()),
            _readField('Basis Weight',
                (roll['basis_weight'] ?? product['basis_weight'])?.toString()),
            _readField('Width (in)',
                (roll['width'] ?? product['width'])?.toString()),
            _readField('Length (ft)',
                (roll['length'] ?? product['length'])?.toString()),
            _readField('Quantity', roll['quantity']?.toString()),
            _readField(
                'Parent Roll(s)', parentList.isEmpty ? '—' : parentList.join('\n')),
            _readField('Status', roll['status']?.toString()),
            _readField('Notes', roll['notes']?.toString()),
            _readField('Produced By', roll['created_by']?.toString()),
            _readField('Date/Time', createdAtStr),
          ],
        ),
      ),
    );
  }

  Widget _readField(String label, String? value) {
    final v = (value == null || value.isEmpty) ? '—' : value;
    final lines = '\n'.allMatches(v).length + 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        initialValue: v,
        readOnly: true,
        maxLines: lines > 1 ? lines : 1,
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

// ── Sale Detail (Level 2) ───────────────────────────────────────────────────

class _SaleDetailScreen extends StatelessWidget {
  final Map sale;
  const _SaleDetailScreen({required this.sale});

  @override
  Widget build(BuildContext context) {
    final ts = sale['sold_at'] != null
        ? DateTime.tryParse(sale['sold_at'].toString())
        : null;
    final soldAtStr = ts != null
        ? '${ts.day}/${ts.month}/${ts.year} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}'
        : sale['sold_at']?.toString() ?? '—';

    final company = sale['company']?.toString() ?? '';
    final companyLabel = company == 'compleat'
        ? 'Com-Pleat'
        : company == 'servair'
            ? 'Servair'
            : company;

    final items = (sale['items'] as List?) ?? const [];
    int totalQty = 0;
    for (final it in items) {
      if (it is Map && it['quantity'] is num) {
        totalQty += (it['quantity'] as num).toInt();
      }
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a73e8),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          sale['invoice_number']?.toString() ?? 'Sale Detail',
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _readField('Company', companyLabel),
            _readField(
                'Customer',
                sale['customer_name']?.toString().isNotEmpty == true
                    ? sale['customer_name'].toString()
                    : sale['customer_id']?.toString()),
            _readField('Customer ID', sale['customer_id']?.toString()),
            _readField(
                'Invoice / Order #', sale['invoice_number']?.toString()),
            _readField('Total Rolls', '$totalQty'),
            _readField('Sold By', sale['sold_by']?.toString()),
            _readField('Sold At', soldAtStr),
            _readField('Notes', sale['notes']?.toString()),
            const SizedBox(height: 8),
            const Text('Items',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Text('—',
                  style: TextStyle(color: Colors.grey, fontSize: 14)),
            ...items.map((raw) {
              final it = raw is Map ? raw : const {};
              final pid = it['product_id']?.toString() ?? '—';
              final qty = it['quantity']?.toString() ?? '0';
              final parentList =
                  ((it['parent_roll_ids'] as List?) ?? const [])
                      .map((e) => e.toString())
                      .toList();
              final parents =
                  parentList.isEmpty ? '—' : parentList.join(' + ');
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(pid,
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                          ),
                          Text('×$qty',
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1a73e8))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                          'Parent${parentList.length == 1 ? '' : 's'}: $parents',
                          style: const TextStyle(
                              fontSize: 13,
                              fontFamily: 'monospace',
                              color: Colors.black87)),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _readField(String label, String? value) {
    final v = (value == null || value.isEmpty) ? '—' : value;
    final lines = '\n'.allMatches(v).length + 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        initialValue: v,
        readOnly: true,
        maxLines: lines > 1 ? lines : 1,
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

// ── Conversion Detail (Level 2) ─────────────────────────────────────────────

class _ConversionDetailScreen extends StatelessWidget {
  final Map conv;
  final Map<String, dynamic> newProduct;
  final Map<String, dynamic> sourceProduct;
  const _ConversionDetailScreen({
    required this.conv,
    required this.newProduct,
    required this.sourceProduct,
  });

  @override
  Widget build(BuildContext context) {
    final ts = conv['converted_at'] != null
        ? DateTime.tryParse(conv['converted_at'].toString())
        : null;
    final convertedAtStr = ts != null
        ? '${ts.day}/${ts.month}/${ts.year} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}'
        : conv['converted_at']?.toString() ?? '—';

    final sourceParents = (conv['source_parent_roll_ids'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a73e8),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          conv['new_product_id']?.toString() ?? 'Conversion Detail',
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('NEW ROLL',
                style: TextStyle(color: Colors.black54, fontSize: 12,
                    letterSpacing: 1.2, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _readField('New Roll ID', conv['new_roll_id']?.toString()),
            _readField('New Product ID', conv['new_product_id']?.toString()),
            _readField('New Product Name', newProduct['product_name']?.toString()),
            _readField('Material', newProduct['material_type']?.toString()),
            _readField('Basis Weight', newProduct['basis_weight']?.toString()),
            _readField('Width (in)', newProduct['width']?.toString()),
            _readField('Length', newProduct['length']?.toString()),
            _readField('Quantity', conv['quantity']?.toString()),
            const SizedBox(height: 8),
            const Text('SOURCE ROLL',
                style: TextStyle(color: Colors.black54, fontSize: 12,
                    letterSpacing: 1.2, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _readField('Source Roll ID', conv['source_roll_id']?.toString()),
            _readField('Source Product ID', conv['source_product_id']?.toString()),
            _readField('Source Product Name', sourceProduct['product_name']?.toString()),
            _readField('Source Material', sourceProduct['material_type']?.toString()),
            _readField('Source Basis Weight', sourceProduct['basis_weight']?.toString()),
            _readField('Source Width (in)', sourceProduct['width']?.toString()),
            _readField('Source Length', sourceProduct['length']?.toString()),
            _readField('Source Parent(s)',
                sourceParents.isEmpty ? '—' : sourceParents.join('\n')),
            _readField('Source Status After', conv['source_status_after']?.toString()),
            const SizedBox(height: 8),
            const Text('METADATA',
                style: TextStyle(color: Colors.black54, fontSize: 12,
                    letterSpacing: 1.2, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _readField('Notes', conv['notes']?.toString()),
            _readField('Converted By', conv['converted_by']?.toString()),
            _readField('Converted At', convertedAtStr),
            _readField('Conversion ID', conv['conversion_id']?.toString()),
          ],
        ),
      ),
    );
  }

  Widget _readField(String label, String? value) {
    final v = (value == null || value.isEmpty) ? '—' : value;
    final lines = '\n'.allMatches(v).length + 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        initialValue: v,
        readOnly: true,
        maxLines: lines > 1 ? lines : 1,
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
