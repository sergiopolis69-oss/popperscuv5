import 'package:flutter/material.dart';
import '../data/database.dart';

class SalesHistoryPage extends StatefulWidget {
  const SalesHistoryPage({super.key});
  @override
  State<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends State<SalesHistoryPage> {
  final _clientDisplayCtrl = TextEditingController();
  final _clientPhoneCtrl = TextEditingController(); // phone real
  List<Map<String, dynamic>> _clientOptions = [];

  List<Map<String, dynamic>> _sales = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(()=>_loading = true);
    final db = await DatabaseHelper.instance.db;
    final rows = await db.rawQuery('''
      SELECT s.*, c.name AS customer_name
      FROM sales s
      LEFT JOIN customers c ON c.phone = s.customer_phone
      ORDER BY datetime(s.date) DESC
    ''');
    setState(() {
      _sales = rows;
      _loading = false;
    });
  }

  Future<void> _searchClients(String q) async {
    final db = await DatabaseHelper.instance.db;
    final like = '%${q.trim()}%';
    final rows = await db.query('customers',
        where: 'name LIKE ? OR phone LIKE ?', whereArgs: [like, like], orderBy: 'name COLLATE NOCASE ASC', limit: 20);
    setState(()=> _clientOptions = rows);
  }

  Future<List<Map<String, dynamic>>> _itemsForSale(int saleId) async {
    final db = await DatabaseHelper.instance.db;
    return db.rawQuery('''
      SELECT si.*, p.name AS product_name
      FROM sale_items si
      LEFT JOIN products p ON p.id = si.product_id
      WHERE si.sale_id = ?
    ''', [saleId]);
  }

  Future<void> _applyFilter() async {
    final phone = _clientPhoneCtrl.text.trim();
    if (phone.isEmpty) { await _loadAll(); return; }
    setState(()=>_loading = true);
    final db = await DatabaseHelper.instance.db;
    final rows = await db.rawQuery('''
      SELECT s.*, c.name AS customer_name
      FROM sales s
      LEFT JOIN customers c ON c.phone = s.customer_phone
      WHERE s.customer_phone = ?
      ORDER BY datetime(s.date) DESC
    ''', [phone]);
    setState(() {
      _sales = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Filtrar por cliente'),
        const SizedBox(height: 4),
        RawAutocomplete<Map<String, dynamic>>(
          textEditingController: _clientDisplayCtrl,
          optionsBuilder: (t) async {
            final q = t.text.trim();
            if (q.isEmpty) return const Iterable.empty();
            await _searchClients(q);
            return _clientOptions;
          },
          displayStringForOption: (o)=> '${(o['name'] ?? '').toString()} (${(o['phone'] ?? '').toString()})',
          fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => TextField(
            controller: ctrl,
            decoration: InputDecoration(
              hintText: 'Nombre o teléfono…',
              suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: (){
                _clientDisplayCtrl.clear();
                _clientPhoneCtrl.clear();
                _applyFilter();
              }),
            ),
            onSubmitted: (_)=> _applyFilter(),
          ),
          optionsViewBuilder: (ctx, onSelect, opts) => Material(
            elevation: 4,
            child: ListView(
              shrinkWrap: true,
              children: opts.map((o)=> ListTile(
                title: Text(o['name'] ?? ''),
                subtitle: Text(o['phone'] ?? ''),
                onTap: (){
                  onSelect(o);
                  _clientPhoneCtrl.text = (o['phone'] ?? '').toString();
                  _applyFilter();
                },
              )).toList(),
            ),
          ),
          onSelected: (_){},
        ),
        const SizedBox(height: 12),

        if (_loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        if (!_loading) ..._sales.map((s) => _SaleTile(sale: s, itemsLoader: _itemsForSale)),
      ],
    );
  }
}

class _SaleTile extends StatefulWidget {
  final Map<String, dynamic> sale;
  final Future<List<Map<String, dynamic>>> Function(int saleId) itemsLoader;
  const _SaleTile({required this.sale, required this.itemsLoader});

  @override
  State<_SaleTile> createState() => _SaleTileState();
}

class _SaleTileState extends State<_SaleTile> {
  List<Map<String, dynamic>>? _items;

  Future<void> _loadItems() async {
    final rows = await widget.itemsLoader(widget.sale['id'] as int);
    setState(()=> _items = rows);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sale;
    final total = (s['shipping_cost'] as num?)?.toDouble() ?? 0.0;
    final discount = (s['discount'] as num?)?.toDouble() ?? 0.0;

    return Card(
      child: ExpansionTile(
        title: Text('${s['customer_name'] ?? s['customer_phone']} • ${s['payment_method'] ?? ''}'),
        subtitle: Text(s['date']?.toString() ?? ''),
        onExpansionChanged: (open){ if (open && _items == null) _loadItems(); },
        children: [
          if (_items == null) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
          if (_items != null) ...[
            const Divider(height: 1),
            ..._items!.map((it) => ListTile(
              dense: true,
              title: Text(it['product_name'] ?? 'Producto ${it['product_id']}'),
              subtitle: Text('x${it['quantity']} • \$${(it['unit_price'] as num).toStringAsFixed(2)}'),
            )),
          ],
          const Divider(height: 1),
          ListTile(
            dense: true,
            title: const Text('Envío / Descuento'),
            trailing: Text('+ \$${total.toStringAsFixed(2)}   •   - \$${discount.toStringAsFixed(2)}'),
          ),
        ],
      ),
    );
  }
}
