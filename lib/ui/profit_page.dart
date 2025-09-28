import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';
import 'package:intl/intl.dart';

class ProfitPage extends StatefulWidget {
  const ProfitPage({super.key});
  @override
  State<ProfitPage> createState() => _ProfitPageState();
}

class _ProfitPageState extends State<ProfitPage> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to   = DateTime.now();
  double _avgProfitPct = 0.0;

  Future<void> _calc() async {
    final db = await DatabaseHelper.instance.db;
    final sales = await db.query('sales', where: 'date >= ? AND date <= ?', whereArgs: [_from.toIso8601String(), _to.toIso8601String()]);
    if (sales.isEmpty) { setState(()=>_avgProfitPct=0); return; }

    double totalRevenue = 0.0;
    double totalCost = 0.0;

    for (final s in sales) {
      final sid = s['id'] as int;
      final discount = (s['discount'] as num?)?.toDouble() ?? 0.0;
      final items = await db.query('sale_items', where: 'sale_id=?', whereArgs: [sid]);

      final gross = items.fold<double>(0.0, (a, it) => a + ((it['quantity'] as int) * (it['unit_price'] as num).toDouble()));
      if (gross <= 0) continue;

      for (final it in items) {
        final q = it['quantity'] as int;
        final pu = (it['unit_price'] as num).toDouble();
        final itemGross = q * pu;
        final itemDiscount = discount * (itemGross / gross);
        final revenue = itemGross - itemDiscount;
        final prodId = it['product_id'] as int;
        final prod = await db.query('products', where: 'id=?', whereArgs: [prodId], limit: 1);
        final lastCost = (prod.isNotEmpty ? (prod.first['last_purchase_price'] as num?)?.toDouble() ?? 0.0 : 0.0);
        final cost = q * lastCost;
        totalRevenue += revenue; // envío excluido
        totalCost += cost;
      }
    }
    final profit = totalRevenue - totalCost;
    final pct = totalRevenue > 0 ? (profit / totalRevenue) * 100.0 : 0.0;
    setState(()=>_avgProfitPct = pct);
  }

  @override
  void initState() {
    super.initState();
    _calc();
  }

  Future<void> _pickFrom() async {
    final d = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDate: _from);
    if (d!=null) { setState(()=>_from = d); _calc(); }
  }
  Future<void> _pickTo() async {
    final d = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDate: _to);
    if (d!=null) { setState(()=>_to = d); _calc(); }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _pickFrom, icon: const Icon(Icons.calendar_today), label: Text('Desde: ${DateFormat('yyyy-MM-dd').format(_from)}'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: _pickTo, icon: const Icon(Icons.calendar_today_outlined), label: Text('Hasta: ${DateFormat('yyyy-MM-dd').format(_to)}'))),
          ]),
          const SizedBox(height: 12),
          Card(child: ListTile(
            title: const Text('Utilidad promedio ponderada'),
            subtitle: Text('${_avgProfitPct.toStringAsFixed(2)} %'),
          )),
        ],
      ),
    );
  }
}
