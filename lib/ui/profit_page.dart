// lib/ui/profit_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database.dart' as appdb;

class ProfitPage extends StatefulWidget {
  const ProfitPage({super.key});

  @override
  State<ProfitPage> createState() => _ProfitPageState();
}

class _ProfitPageState extends State<ProfitPage> {
  final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

  // Rango de fechas (controlado por el botón de calendario)
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  // Resumen global (sin envíos)
  double _totalSales = 0.0; // SUM(si.qty * si.unit_price)
  double _totalCost = 0.0;  // SUM(si.qty * products.last_purchase_price)
  double _profit = 0.0;     // ventas - costo
  double _marginPct = 0.0;  // utilidad / ventas

  // Desglose por producto (misma lógica de siempre)
  List<Map<String, dynamic>> _productRows = [];

  // Integrado en la tarjeta de utilidad: ventas por método de pago en el rango
  List<Map<String, dynamic>> _paymentByMethod = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<Database> _db() async {
    try {
      return await appdb.getDb();
    } catch (_) {
      return await appdb.DatabaseHelper.instance.db;
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: DateTimeRange(
        start: DateTime(_from.year, _from.month, _from.day),
        end: DateTime(_to.year, _to.month, _to.day),
      ),
    );
    if (picked == null) return;

    setState(() {
      _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    await _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      await Future.wait([
        _loadSummaryAndPayments(), // resumen + métodos de pago en mismo rango
        _loadProductsProfit(),     // desglose por producto
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fromTxt() => DateFormat('yyyy-MM-dd').format(_from);
  String _toTxt() => DateFormat('yyyy-MM-dd').format(_to);

  /// Resumen (sin envíos) y desglose por método de pago en el rango.
  Future<void> _loadSummaryAndPayments() async {
    final db = await _db();
    // Totales globales sin envíos en el rango (filtrando por s.date)
    final sumRows = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(si.quantity * si.unit_price), 0) AS sales,
        COALESCE(SUM(si.quantity * COALESCE(p.last_purchase_price, 0)), 0) AS cost
      FROM sale_items si
      JOIN products p ON p.id = si.product_id
      JOIN sales s ON s.id = si.sale_id
      WHERE s.date BETWEEN ? AND ?
    ''', [_fromTxt(), _toTxt()]);

    final s = sumRows.isNotEmpty ? sumRows.first : <String, Object?>{};
    final sales = (s['sales'] as num?)?.toDouble() ?? 0.0;
    final cost = (s['cost'] as num?)?.toDouble() ?? 0.0;
    final profit = sales - cost;
    final pct = sales > 0 ? (profit / sales) : 0.0;

    // Desglose por método de pago (sin envíos, mismo rango)
    final payRows = await db.rawQuery('''
      SELECT 
        COALESCE(s.payment_method, '(sin método)') AS method,
        COALESCE(SUM(si.quantity * si.unit_price), 0) AS amount,
        COUNT(DISTINCT s.id) AS sales_count
      FROM sales s
      JOIN sale_items si ON si.sale_id = s.id
      WHERE s.date BETWEEN ? AND ?
      GROUP BY method
      ORDER BY amount DESC
    ''', [_fromTxt(), _toTxt()]);

    setState(() {
      _totalSales = sales;
      _totalCost = cost;
      _profit = profit;
      _marginPct = pct;
      _paymentByMethod = payRows;
    });
  }

  /// Desglose por producto (sin envíos) en el rango
  /// Mantiene la lógica: revenue vs cost con last_purchase_price
  Future<void> _loadProductsProfit() async {
    final db = await _db();
    final rows = await db.rawQuery('''
      SELECT 
        p.id,
        p.sku,
        p.name,
        COALESCE(SUM(si.quantity), 0) AS qty,
        COALESCE(SUM(si.quantity * si.unit_price), 0) AS revenue,
        COALESCE(SUM(si.quantity * COALESCE(p.last_purchase_price, 0)), 0) AS cost
      FROM products p
      LEFT JOIN sale_items si ON si.product_id = p.id
      LEFT JOIN sales s ON s.id = si.sale_id
      WHERE s.date BETWEEN ? AND ?
      GROUP BY p.id, p.sku, p.name
      HAVING qty > 0
      ORDER BY revenue DESC
    ''', [_fromTxt(), _toTxt()]);

    final list = rows.map((r) {
      final qty = (r['qty'] as num?)?.toInt() ?? 0;
      final revenue = (r['revenue'] as num?)?.toDouble() ?? 0.0;
      final cost = (r['cost'] as num?)?.toDouble() ?? 0.0;
      final profit = revenue - cost;
      final margin = revenue > 0 ? profit / revenue : 0.0;

      return {
        'id': r['id'],
        'sku': (r['sku'] ?? '').toString(),
        'name': (r['name'] ?? '').toString(),
        'qty': qty,
        'revenue': revenue,
        'cost': cost,
        'profit': profit,
        'margin': margin,
      };
    }).toList();

    setState(() => _productRows = list);
  }

  @override
  Widget build(BuildContext context) {
    final bold = const TextStyle(fontWeight: FontWeight.bold);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Utilidad'),
        actions: [
          IconButton(
            tooltip: 'Elegir periodo',
            onPressed: _pickRange,
            icon: const Icon(Icons.calendar_today),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Periodo: ${DateFormat('dd/MM/yyyy').format(_from)} — ${DateFormat('dd/MM/yyyy').format(_to)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // === TARJETA ÚNICA: Utilidad + Métodos de pago (en el mismo periodo) ===
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Resumen (sin envíos)', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _kv('Ventas', _money.format(_totalSales))),
                            Expanded(child: _kv('Costo', _money.format(_totalCost))),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: _kv('Utilidad', _money.format(_profit), bold: true)),
                            Expanded(child: _kv('Margen', '${(_marginPct * 100).toStringAsFixed(1)}%', bold: true)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 6),
                        const Text('Por método de pago (mismo periodo)', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        if (_paymentByMethod.isEmpty)
                          const Text('Sin ventas en el periodo')
                        else
                          ..._paymentByMethod.map((m) {
                            final method = (m['method'] ?? '(sin método)').toString();
                            final amount = (m['amount'] as num?)?.toDouble() ?? 0.0;
                            final cnt = (m['sales_count'] as num?)?.toInt() ?? 0;
                            final pct = _totalSales > 0 ? (amount / _totalSales) : 0.0;
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.payments),
                              title: Text(method, style: bold),
                              subtitle: Text('$cnt ventas • ${(_totalSales > 0 ? pct * 100 : 0).toStringAsFixed(1)}%'),
                              trailing: Text(_money.format(amount), style: bold),
                            );
                          }),
                      ],
                    ),
                  ),
                ),

                // === Desglose por producto (misma lógica; sin envíos) ===
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Utilidad por producto (sin envíos)', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        if (_productRows.isEmpty)
                          const Text('Sin datos de ventas en el periodo')
                        else
                          _ProductsTable(rows: _productRows, money: _money),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _kv(String k, String v, {bool bold = false}) {
    final st = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(k, style: st)),
          Text(v, style: st),
        ],
      ),
    );
  }
}

class _ProductsTable extends StatelessWidget {
  const _ProductsTable({
    required this.rows,
    required this.money,
  });

  final List<Map<String, dynamic>> rows;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('SKU')),
          DataColumn(label: Text('Producto')),
          DataColumn(label: Text('Cant.')),
          DataColumn(label: Text('Ventas')),
          DataColumn(label: Text('Costo')),
          DataColumn(label: Text('Utilidad')),
          DataColumn(label: Text('Margen')),
        ],
        rows: rows.map((r) {
          final margin = (r['margin'] as num?)?.toDouble() ?? 0.0;
          final color = margin >= 0 ? Colors.green : Colors.red;

          return DataRow(
            cells: [
              DataCell(Text((r['sku'] ?? '').toString())),
              DataCell(SizedBox(
                width: 220,
                child: Text(
                  (r['name'] ?? '').toString(),
                  overflow: TextOverflow.ellipsis,
                ),
              )),
              DataCell(Text(((r['qty'] as num?)?.toInt() ?? 0).toString())),
              DataCell(Text(money.format((r['revenue'] as num?)?.toDouble() ?? 0.0))),
              DataCell(Text(money.format((r['cost'] as num?)?.toDouble() ?? 0.0))),
              DataCell(Text(money.format((r['profit'] as num?)?.toDouble() ?? 0.0))),
              DataCell(Text('${(margin * 100).toStringAsFixed(1)}%', style: TextStyle(color: color))),
            ],
          );
        }).toList(),
      ),
    );
  }
}