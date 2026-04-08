import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/api_service.dart';

class SalesMapScreen extends StatefulWidget {
  const SalesMapScreen({super.key});

  @override
  State<SalesMapScreen> createState() => _SalesMapScreenState();
}

class _SalesMapScreenState extends State<SalesMapScreen> {
  List<dynamic> _accounts = [];
  bool _loading = true;

  static const _allStatuses = [
    'Active', 'Prospect', 'Lost', 'Dormant', 'Out of Business',
  ];

  final Set<String> _visibleStatuses = Set.from(_allStatuses);

  static Color _statusColor(String? status) {
    switch (status) {
      case 'Active':         return const Color(0xFF22c55e);
      case 'Prospect':       return const Color(0xFF3b82f6);
      case 'Lost':           return const Color(0xFFef4444);
      case 'Dormant':        return const Color(0xFFeab308);
      case 'Out of Business':return const Color(0xFF6b7280);
      default:               return const Color(0xFF9ca3af);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final data = await ApiService.getCrmAccounts();
    setState(() {
      _accounts = data;
      _loading = false;
    });
  }

  List<dynamic> get _filteredAccounts => _accounts
      .where((a) => _visibleStatuses.contains(a['status']))
      .toList();

  void _showAccountSheet(BuildContext context, Map<String, dynamic> account) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                  color: _statusColor(account['status']),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(account['name'] ?? '',
                    style: const TextStyle(fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 12),
            _SheetRow('Status', account['status']),
            _SheetRow('Address', account['address']),
            _SheetRow('City', account['city']),
            _SheetRow('Province', account['province']),
            _SheetRow('Sales Rep', account['sales_rep']),
            _SheetRow('Operating Company', account['op_company']),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_accounts.isEmpty)
              const Center(
                child: Text('No accounts loaded',
                    style: TextStyle(color: Colors.black54, fontSize: 16)),
              )
            else
              FlutterMap(
                options: const MapOptions(
                  initialCenter: LatLng(45.5, -80),
                  initialZoom: 5,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c'],
                    userAgentPackageName: 'com.compleat.mobile',
                  ),
                  MarkerLayer(
                    markers: _filteredAccounts.map((account) {
                      final lat = (account['lat'] as num?)?.toDouble() ?? 0;
                      final lng = (account['lng'] as num?)?.toDouble() ?? 0;
                      final color = _statusColor(account['status'] as String?);
                      return Marker(
                        point: LatLng(lat, lng),
                        width: 20,
                        height: 20,
                        child: GestureDetector(
                          onTap: () => _showAccountSheet(
                              context, Map<String, dynamic>.from(account)),
                          child: Container(
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26,
                                    blurRadius: 2, offset: Offset(0, 1)),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            // Back button + filter chips header
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                color: const Color(0xFF1a73e8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 8),
                      const Text('Sales Map',
                          style: TextStyle(color: Colors.white, fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      if (!_loading) ...[
                        const Spacer(),
                        Text('${_filteredAccounts.length} accounts',
                            style: const TextStyle(color: Colors.white70,
                                fontSize: 12)),
                        const SizedBox(width: 8),
                      ],
                    ]),
                    if (!_loading && _accounts.isNotEmpty)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _allStatuses.map((status) {
                            final active = _visibleStatuses.contains(status);
                            return Padding(
                              padding: const EdgeInsets.only(right: 6, bottom: 4),
                              child: FilterChip(
                                label: Text(status,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: active ? Colors.white : Colors.white70,
                                    )),
                                selected: active,
                                onSelected: (val) => setState(() {
                                  if (val) {
                                    _visibleStatuses.add(status);
                                  } else {
                                    _visibleStatuses.remove(status);
                                  }
                                }),
                                selectedColor: _statusColor(status),
                                checkmarkColor: Colors.white,
                                backgroundColor: Colors.white24,
                                side: BorderSide.none,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 0),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Legend bottom-left
            if (!_loading && _accounts.isNotEmpty)
              Positioned(
                bottom: 16, left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26,
                          blurRadius: 4, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: _allStatuses.map((status) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(
                              color: _statusColor(status),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(status,
                              style: const TextStyle(fontSize: 11,
                                  color: Colors.black87)),
                        ],
                      ),
                    )).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  final String label;
  final dynamic value;
  const _SheetRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text('$label:',
                style: const TextStyle(color: Colors.black54, fontSize: 13)),
          ),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: Colors.black87, fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
