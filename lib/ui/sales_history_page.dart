import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

class SalesHistoryPage extends StatefulWidget {
  const SalesHistoryPage({super.key});
  @override
  State<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends State<SalesHistoryPage> {
  final _phoneCtrl = TextEditingController();
  DateTimeRange? _range;
  String? _payment;
  String? _productQuery;

  List<Map<String, dynamic>> _sales = [];

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _range,
    );
    if (picked != null) setState(()=>_range = picked);
  }

  Future<void> _search() async {
    final db = await DatabaseHelper.instance.db;
    final where = <String>[];
    final args = <Object?>[];

    if (_phoneCtrl.text.trim().isNotEmpty) {
      where.add('s.customer_phone = ?');
      args.add(_phoneCtrl.text.trim());
    }
    if (_payment != null && _payment!.isNotEmpty) {
      where.add('s.payment_method = ?');
      args.add(_payment);
    }
    if (_range != null) {
      where.add('date(s.date) BETWEEN ? AND ?');
      args.add(_range!.start.toIso8601String().substring(0,10));
      args.add(_range!.end.toIso8601String().substring(0,10));
    }
    if (_productQuery != null && _productQuery!.trim().isNotEmpty) {
      // filtra ventas que contengan un producto cuyo nombre haga match
      where.add('EXISTS(SELECT 1 FROM sale_items si JOIN products p ON p.id=si.product_id WHERE si.sale_id=s.id AND p.name LIKE ?)');
      args.add('%${_productQuery!.trim()}%');
    }

    final sql = '''
      SELECT s.id, s.customer_phone, s.payment_method, s.place, s.shipping_cost, s.discount, s.date,
             (SELECT SUM(si.quantity*si.unit_price) FROM sale_items si WHERE si.sale_id = s.id) AS items_total
      FROM sales s
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY s.date DESC, s.id DESC
      LIMIT 500
    ''';

    final rows = await db.rawQuery(sql, args);
    setState(()=>_sales = rows);
  }

  Future<List<Map<String, dynamic>>> _loadItems(int saleId) async {
    final db = await DatabaseHelper.instance.db;
    final rows = await db.rawQuery('''
      SELECT si.product_id, si.quantity, si.unit_price, p.name
      FROM sale_items si
      LEFT JOIN products p ON p.id = si.product_id
      WHERE si.sale_id = ?
      ORDER BY si.rowid
    ''', [saleId]);
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Filtros'),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Cliente (teléfono / ID)', prefixIcon: Icon(Icons.person)))),
          const SizedBox(width: 8),
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<String>(
              value: _payment,
              items: const [
                DropdownMenuItem(value: '', child: Text('Pago (todos)')),
                DropdownMenuItem(value: 'efectivo', child: Text('Efectivo')),
                DropdownMenuItem(value: 'tarjeta', child: Text('Tarjeta')),
                DropdownMenuItem(value: 'transferencia', child: Text('Transferencia')),
              ],
              onChanged: (v)=> setState(()=> _payment = (v??'').isEmpty ? null : v),
              decoration: const InputDecoration(labelText: 'Forma de pago'),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: TextField(
            decoration: const InputDecoration(labelText: 'Producto contiene...', prefixIcon: Icon(Icons.search)),
            onChanged: (v)=> _productQuery = v,
          )),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: _pickRange, icon: const Icon(Icons.date_range), label: Text(_range == null ? 'Rango fechas' : '${_range!.start.toString().substring(0,10)} → ${_range!.end.toString().substring(0,10)}')),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: _search, icon: const Icon(Icons.search), label: const Text('Buscar')),
        ]),
        const SizedBox(height: 12),
        const Divider(),
        ..._sales.map((s){
          final saleId = s['id'] as int;
          final itemsTotal = (s['items_total'] as num?)?.toDouble() ?? 0.0;
          final discount = (s['discount'] as num?)?.toDouble() ?? 0.0;
          final shipping = (s['shipping_cost'] as num?)?.toDouble() ?? 0.0;
          final totalCobrar = (itemsTotal - discount + shipping).clamp(0.0, double.infinity);

          return ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Venta #$saleId  |  Cliente: ${s['customer_phone'] ?? '—'}'),
            subtitle: Text('${s['date']}  •  Pago: ${s['payment_method'] ?? '—'}  •  Total: \$${totalCobrar.toStringAsFixed(2)}'),
            children: [
              FutureBuilder(
                future: _loadItems(saleId),
                builder: (ctx, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    );
                  }
                  final items = snap.data as List<Map<String,dynamic>>? ?? [];
                  if (items.isEmpty) {
                    return const ListTile(title: Text('Sin productos'));
                  }
                  return Column(
                    children: items.map((it){
                      final name = it['name'] ?? 'Producto ${it['product_id']}';
                      final qty = (it['quantity'] as num?)?.toInt() ?? 0;
                      final up  = (it['unit_price'] as num?)?.toDouble() ?? 0.0;
                      return ListTile(
                        dense: true,
                        title: Text(name.toString()),
                        subtitle: Text('x$qty  •  \$${up.toStringAsFixed(2)}  •  Importe \$${(qty*up).toStringAsFixed(2)}'),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          );
        }),
        if (_sales.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Sin resultados todavía')),
      ],
    );
  }
}
