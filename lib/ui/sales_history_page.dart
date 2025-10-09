import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

class SalesHistoryPage extends StatefulWidget {
  const SalesHistoryPage({super.key});
  @override
  State<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends State<SalesHistoryPage> {
  final _clientQuery = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final db = await DatabaseHelper.instance.db;
    final rows = await db.rawQuery('''
      SELECT s.id, s.date, s.customer_phone, c.name AS customer_name,
             s.payment_method, s.place, s.shipping_cost, s.discount,
             IFNULL(SUM(si.quantity * si.unit_price),0) AS subtotal
      FROM sales s
      LEFT JOIN customers c ON c.phone = s.customer_phone
      LEFT JOIN sale_items si ON si.sale_id = s.id
      GROUP BY s.id
      ORDER BY s.date DESC
      LIMIT 1000
    ''');
    setState(()=>_rows = rows);
  }

  void _onFilterChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (q.trim().isEmpty) { _loadAll(); return; }
      final db = await DatabaseHelper.instance.db;
      final like = '%${q.trim()}%';
      final rows = await db.rawQuery('''
        SELECT s.id, s.date, s.customer_phone, c.name AS customer_name,
               s.payment_method, s.place, s.shipping_cost, s.discount,
               IFNULL(SUM(si.quantity * si.unit_price),0) AS subtotal
        FROM sales s
        LEFT JOIN customers c ON c.phone = s.customer_phone
        LEFT JOIN sale_items si ON si.sale_id = s.id
        WHERE c.name LIKE ? OR s.customer_phone LIKE ?
        GROUP BY s.id
        ORDER BY s.date DESC
        LIMIT 1000
      ''', [like, like]);
      setState(()=>_rows = rows);
    });
  }

  Future<List<Map<String,dynamic>>> _itemsOf(int saleId) async {
    final db = await DatabaseHelper.instance.db;
    return db.rawQuery('''
      SELECT si.quantity, si.unit_price, p.name
      FROM sale_items si JOIN products p ON p.id = si.product_id
      WHERE si.sale_id = ?
    ''', [saleId]);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TextField(
          controller: _clientQuery,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Filtrar por cliente (nombre o teléfono)',
          ),
          onChanged: _onFilterChanged,
        ),
        const SizedBox(height: 12),
        ..._rows.map((r){
          final subtotal = (r['subtotal'] as num).toDouble();
          final total = subtotal - (r['discount'] as num).toDouble() + (r['shipping_cost'] as num).toDouble();
          return ExpansionTile(
            title: Text('Venta #${r['id']}  •  \$${total.toStringAsFixed(2)}'),
            subtitle: Text('${r['customer_name'] ?? r['customer_phone']}  •  ${r['date']}'),
            children: [
              FutureBuilder(
                future: _itemsOf(r['id'] as int),
                builder: (ctx,snap){
                  if (!snap.hasData) return const Padding(padding: EdgeInsets.all(12), child: Text('Cargando items...'));
                  final items = snap.data as List<Map<String,dynamic>>;
                  if (items.isEmpty) return const Padding(padding: EdgeInsets.all(12), child: Text('Sin productos'));
                  return Column(children: items.map((it)=>ListTile(
                    dense: true,
                    title: Text(it['name'] ?? ''),
                    subtitle: Text('x${it['quantity']} • \$${(it['unit_price'] as num).toString()}'),
                  )).toList());
                },
              ),
            ],
          );
        }),
        if (_rows.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Sin ventas')),
      ],
    );
  }
}
