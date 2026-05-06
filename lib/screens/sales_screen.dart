import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dropdown_search/dropdown_search.dart';
import '../services/api_service.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  // Company
  String? _company; // 'compleat' | 'servair'

  // Customer
  Map<String, dynamic>? _selectedCustomer;
  final Map<String, List<Map<String, dynamic>>> _customerCache = {};
  bool _loadingCustomers = false;
  final _customerKey = GlobalKey<DropdownSearchState<Map<String, dynamic>>>();

  // Invoice
  final _invoiceController = TextEditingController();
  final _invoiceFocus = FocusNode();

  // Two-parent toggle
  bool _twoParent = false;

  // Scan
  final _scanController = TextEditingController();
  final _scanFocus = FocusNode();
  String? _pendingFirstScan; // raw text of first scan when in two-parent mode

  // Scanned items: keyed by "<product_id>|<sortedParentJoined>"
  final List<_SaleLine> _lines = [];

  // Notes
  final _notesController = TextEditingController();
  final _notesFocus = FocusNode();

  bool _submitting = false;
  bool _checkingStock = false;
  String? _message;
  bool _messageSuccess = false;

  final _scrollController = ScrollController();

  @override
  void dispose() {
    _invoiceController.dispose();
    _invoiceFocus.dispose();
    _scanController.dispose();
    _scanFocus.dispose();
    _notesController.dispose();
    _notesFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showMessage(String msg, bool success) {
    setState(() { _message = msg; _messageSuccess = success; });
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _message = null);
    });
  }

  Future<void> _loadCustomers(String company) async {
    if (_customerCache.containsKey(company)) return;
    setState(() => _loadingCustomers = true);
    final res = await ApiService.get('/masters/customers?company=$company');
    final list = <Map<String, dynamic>>[];
    if (res['records'] is List) {
      for (final r in (res['records'] as List)) {
        if (r is Map) list.add(Map<String, dynamic>.from(r));
      }
    }
    list.sort((a, b) => (a['display_name'] ?? '').toString()
        .toLowerCase()
        .compareTo((b['display_name'] ?? '').toString().toLowerCase()));
    _customerCache[company] = list;
    if (mounted) setState(() => _loadingCustomers = false);
  }

  Future<void> _onCompanyChanged(String company) async {
    if (_company == company) return;
    setState(() {
      _company = company;
      _selectedCustomer = null;
      _lines.clear();
      _pendingFirstScan = null;
      _scanController.clear();
    });
    await _loadCustomers(company);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _customerKey.currentState?.openDropDownSearch();
    });
  }

  // Composite parser: split on the LAST hyphen.
  ({String productId, String parentId})? _parseComposite(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final idx = s.lastIndexOf('-');
    if (idx <= 0 || idx >= s.length - 1) return null;
    final pid = s.substring(0, idx).trim();
    final parent = s.substring(idx + 1).trim();
    if (pid.isEmpty || parent.isEmpty) return null;
    return (productId: pid, parentId: parent);
  }

  void _resetScan({bool focus = true}) {
    _scanController.clear();
    _pendingFirstScan = null;
    if (focus && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scanFocus.requestFocus();
      });
    }
  }

  Future<void> _handleScan(String raw) async {
    if (_company == null) {
      _resetScan();
      _showMessage('Select a company first.', false);
      return;
    }
    if (_selectedCustomer == null) {
      _resetScan();
      _showMessage('Select a customer first.', false);
      return;
    }
    if (_invoiceController.text.trim().isEmpty) {
      _resetScan();
      _showMessage('Enter an invoice number first.', false);
      return;
    }
    if (raw.trim().isEmpty) return;

    if (_twoParent) {
      // Two-parent mode: collect both labels then process together.
      if (_pendingFirstScan == null) {
        final p = _parseComposite(raw);
        if (p == null) {
          _resetScan();
          _showMessage('Invalid barcode. Expected ProductID-ParentID.', false);
          return;
        }
        setState(() => _pendingFirstScan = raw.trim());
        _scanController.clear();
        HapticFeedback.lightImpact();
        if (mounted) _scanFocus.requestFocus();
        return;
      }
      final p1 = _parseComposite(_pendingFirstScan!);
      final p2 = _parseComposite(raw);
      if (p1 == null || p2 == null) {
        _resetScan();
        _showMessage('Invalid barcode. Expected ProductID-ParentID.', false);
        return;
      }
      if (p1.productId != p2.productId) {
        _resetScan();
        _showMessage('Both labels must be from the same product roll.', false);
        return;
      }
      if (p1.parentId == p2.parentId) {
        _resetScan();
        _showMessage('Both labels share the same parent roll. Scan two different parents.', false);
        return;
      }
      await _addOrIncrement(p1.productId, [p1.parentId, p2.parentId]);
      return;
    }

    // Single-parent mode
    final p = _parseComposite(raw);
    if (p == null) {
      _resetScan();
      _showMessage('Invalid barcode. Expected ProductID-ParentID.', false);
      return;
    }
    await _addOrIncrement(p.productId, [p.parentId]);
  }

  Future<void> _addOrIncrement(String productId, List<String> parentIds) async {
    setState(() => _checkingStock = true);
    final qs = parentIds.join(',');
    final res = await ApiService.get(
      '/sales/stock_check?product_id=${Uri.encodeQueryComponent(productId)}'
      '&parent_roll_ids=${Uri.encodeQueryComponent(qs)}',
    );
    setState(() => _checkingStock = false);

    final available = (res['available'] is num) ? (res['available'] as num).toInt() : 0;
    if (res['error'] != null || available <= 0) {
      _resetScan();
      _showMessage('Out of stock or roll already sold.', false);
      return;
    }

    final sortedParents = List<String>.from(parentIds)..sort();
    final key = '$productId|${sortedParents.join('+')}';

    setState(() {
      final idx = _lines.indexWhere((l) => l.key == key);
      if (idx >= 0) {
        _lines[idx].quantity += 1;
      } else {
        _lines.insert(0, _SaleLine(
          key: key,
          productId: productId,
          parentRollIds: sortedParents,
          quantity: 1,
        ));
      }
      _pendingFirstScan = null;
    });
    _scanController.clear();
    HapticFeedback.lightImpact();
    if (mounted) _scanFocus.requestFocus();
  }

  void _removeLine(String key) {
    setState(() => _lines.removeWhere((l) => l.key == key));
  }

  Future<void> _submit() async {
    if (_company == null) { _showMessage('Select a company.', false); return; }
    if (_selectedCustomer == null) {
      _showMessage('Select a customer.', false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _customerKey.currentState?.openDropDownSearch();
      });
      return;
    }
    if (_invoiceController.text.trim().isEmpty) {
      _showMessage('Enter an invoice number.', false);
      _invoiceFocus.requestFocus();
      return;
    }
    if (_lines.isEmpty) {
      _showMessage('Scan at least one roll.', false);
      _scanFocus.requestFocus();
      return;
    }

    setState(() => _submitting = true);
    final payload = {
      'company': _company,
      'customer_id': _selectedCustomer!['doc_id'] ??
          _selectedCustomer!['customer_id'],
      'customer_name': _selectedCustomer!['display_name'] ?? '',
      'invoice_number': _invoiceController.text.trim(),
      'items': _lines.map((l) => {
        'product_id': l.productId,
        'parent_roll_ids': l.parentRollIds,
        'quantity': l.quantity,
      }).toList(),
      'notes': _notesController.text.trim(),
    };
    final res = await ApiService.post('/sales/submit', payload);
    setState(() => _submitting = false);

    if (res['success'] == true) {
      _showMessage('Sale submitted!', true);
      _resetForm();
    } else {
      _showMessage(res['detail']?.toString() ?? 'Error submitting sale.', false);
    }
  }

  void _resetForm() {
    setState(() {
      _company = null;
      _selectedCustomer = null;
      _invoiceController.clear();
      _twoParent = false;
      _scanController.clear();
      _pendingFirstScan = null;
      _lines.clear();
      _notesController.clear();
    });
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    FocusScope.of(context).unfocus();
  }

  int get _totalQty => _lines.fold(0, (s, l) => s + l.quantity);

  @override
  Widget build(BuildContext context) {
    final customers = _company == null
        ? const <Map<String, dynamic>>[]
        : (_customerCache[_company!] ?? const []);

    String scanLabel;
    if (_twoParent) {
      scanLabel = _pendingFirstScan == null
          ? 'Scan label 1 of 2'
          : 'Scan label 2 of 2';
    } else {
      scanLabel = 'Scan composite barcode';
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a73e8),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Sales',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          if (_message != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              color: _messageSuccess ? Colors.green[100] : Colors.red[100],
              child: Text(_message!,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _messageSuccess
                          ? Colors.green[800]
                          : Colors.red[800])),
            ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Company ──────────────────────────────
                  const Text('Company *',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _companyButton('compleat', 'Com-Pleat'),
                    const SizedBox(width: 8),
                    _companyButton('servair', 'Servair'),
                  ]),
                  const SizedBox(height: 16),

                  // ── Customer ─────────────────────────────
                  if (_loadingCustomers)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Row(children: [
                        SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text('Loading customers...'),
                      ]),
                    ),
                  AbsorbPointer(
                    absorbing: _company == null || _loadingCustomers,
                    child: Opacity(
                      opacity: _company == null ? 0.5 : 1.0,
                      child: DropdownSearch<Map<String, dynamic>>(
                        key: _customerKey,
                        items: customers,
                        selectedItem: _selectedCustomer,
                        itemAsString: (c) => (c['display_name'] ?? '').toString(),
                        compareFn: (a, b) =>
                            (a['doc_id'] ?? a['customer_id']) ==
                            (b['doc_id'] ?? b['customer_id']),
                        dropdownDecoratorProps: const DropDownDecoratorProps(
                          dropdownSearchDecoration: InputDecoration(
                            labelText: 'Customer *',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                vertical: 18, horizontal: 14),
                          ),
                        ),
                        popupProps: PopupProps.menu(
                          showSearchBox: true,
                          fit: FlexFit.loose,
                          searchFieldProps: const TextFieldProps(
                            decoration: InputDecoration(
                              hintText: 'Type to search...',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 12),
                            ),
                            autofocus: true,
                          ),
                          constraints: const BoxConstraints(maxHeight: 420),
                          itemBuilder: (context, item, isSelected) => Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 16),
                            child: Text(
                              (item['display_name'] ?? '').toString(),
                              style: TextStyle(
                                  fontSize: 16,
                                  color: isSelected
                                      ? const Color(0xFF1a73e8)
                                      : Colors.black,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal),
                            ),
                          ),
                          // Lazy filter: search-as-you-type runs against
                          // all 4,939 entries via filterFn; popup uses a
                          // ListView so scrolling stays smooth.
                        ),
                        filterFn: (item, query) {
                          if (query.isEmpty) return true;
                          final s = (item['display_name'] ?? '')
                              .toString()
                              .toLowerCase();
                          return s.contains(query.toLowerCase());
                        },
                        onChanged: (val) {
                          setState(() => _selectedCustomer = val);
                          if (val != null) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _invoiceFocus.requestFocus();
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Invoice ──────────────────────────────
                  TextField(
                    controller: _invoiceController,
                    focusNode: _invoiceFocus,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(fontSize: 18),
                    decoration: const InputDecoration(
                      labelText: 'Invoice / Order Number *',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          vertical: 18, horizontal: 14),
                    ),
                    onSubmitted: (_) => _scanFocus.requestFocus(),
                  ),
                  const SizedBox(height: 12),

                  // ── Two-parent toggle ────────────────────
                  Card(
                    color: Colors.blue[50],
                    child: SwitchListTile(
                      title: const Text('Two parent rolls',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      subtitle: const Text(
                          'Enable when a child roll has two parent labels'),
                      value: _twoParent,
                      onChanged: (v) {
                        setState(() {
                          _twoParent = v;
                          _pendingFirstScan = null;
                          _scanController.clear();
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Scan ─────────────────────────────────
                  TextField(
                    controller: _scanController,
                    focusNode: _scanFocus,
                    autofocus: false,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(fontSize: 18),
                    decoration: InputDecoration(
                      labelText: scanLabel,
                      hintText: 'Scan here...',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 18, horizontal: 14),
                      prefixIcon: _checkingStock
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : const Icon(Icons.qr_code_scanner, size: 28),
                    ),
                    onSubmitted: (v) async {
                      await _handleScan(v);
                    },
                    onChanged: (v) {
                      if (v.endsWith('\n')) _handleScan(v);
                    },
                  ),
                  const SizedBox(height: 12),

                  // ── Total + scanned items list ───────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFe8f0fe),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFF1a73e8), width: 2),
                    ),
                    child: Row(children: [
                      Text('$_totalQty',
                          style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1a73e8))),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          '${_lines.length} line${_lines.length == 1 ? '' : 's'}'
                          ' · $_totalQty roll${_totalQty == 1 ? '' : 's'}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  if (_lines.isNotEmpty)
                    ListView.builder(
                      shrinkWrap: true,
                      reverse: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _lines.length,
                      itemBuilder: (context, i) {
                        final l = _lines[_lines.length - 1 - i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: Dismissible(
                            key: Key(l.key),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              color: Colors.red,
                              child: const Icon(Icons.delete,
                                  color: Colors.white),
                            ),
                            onDismissed: (_) => _removeLine(l.key),
                            child: ListTile(
                              title: Text(l.productId,
                                  style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  'Parent${l.parentRollIds.length == 1 ? '' : 's'}: '
                                  '${l.parentRollIds.join(' + ')}',
                                  style: const TextStyle(
                                      fontFamily: 'monospace', fontSize: 13)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('×${l.quantity}',
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF1a73e8))),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.close,
                                        color: Colors.red),
                                    onPressed: () => _removeLine(l.key),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 12),

                  // ── Notes ────────────────────────────────
                  TextField(
                    controller: _notesController,
                    focusNode: _notesFocus,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    maxLines: 3,
                    minLines: 1,
                    style: const TextStyle(fontSize: 16),
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          vertical: 14, horizontal: 14),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Submit ───────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.point_of_sale, size: 24),
                      label: Text(
                          _submitting ? 'Submitting...' : 'Submit Sale',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _resetForm,
                      child: const Text('Clear', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _companyButton(String code, String label) {
    final selected = _company == code;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onCompanyChanged(code),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF1a73e8).withOpacity(0.12)
                : Colors.white,
            border: Border.all(
                color:
                    selected ? const Color(0xFF1a73e8) : Colors.grey[300]!,
                width: selected ? 2 : 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: selected
                      ? const Color(0xFF1a73e8)
                      : Colors.grey[700])),
        ),
      ),
    );
  }
}

class _SaleLine {
  final String key;
  final String productId;
  final List<String> parentRollIds;
  int quantity;
  _SaleLine({
    required this.key,
    required this.productId,
    required this.parentRollIds,
    required this.quantity,
  });
}
