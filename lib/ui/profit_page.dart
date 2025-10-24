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

  // Rango de fechas
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  // Resumen global (SIN envíos)
  double _itemsSum = 0.0;       // SUM(si.qty * si.unit_price)
  double _discounts = 0.0;      // SUM(s.discount)
  double _netSales = 0.0;       // itemsSum - discounts
  double _cost = 0.0;           // SUM(si.qty * products.last_purchase_price)
  double _profit = 0.0;         // netSales - cost
  double _marginPct = 0.0;      // profit / netSales

  // Solo informativo (NO entra en utilidad)
  double _totalShipping = 0.0;  // SUM(s.shipping_cost)

  // Desglose por producto (sin envíos, sin asignar descuentos por producto)
  List<Map<String, dynamic>> _productRows = [];

  // Desglose por método de pago (sin envíos) con descuentos restados por método
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
        _loadSummaryShippingAndPayments(), // resumen + envíos + métodos de pago (con descuentos)
        _loadProductsProfit(),             // desglose por producto (sin envíos, sin asignar descuentos)
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fromTxt() => DateFormat('yyyy-MM-dd').format(_from);
  String _toTxt() => DateFormat('yyyy-MM-dd').format(_to);

  /// Resumen (SIN envíos) y pagos por método (restando descuentos)
  Future<void> _loadSummaryShippingAndPayments() async {
    final db = await _db();

    // Suma de artículos (ventas brutas de items, sin envíos)
    final itemsRows = await db.rawQuery('''
      SELECT COALESCE(SUM(si.quantity * si.unit_price), 0) AS items_sum
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE s.date BETWEEN ? AND ?
    ''', [_fromTxt(), _toTxt()]);
    final itemsSum = (itemsRows.first['items_sum'] as num?)?.toDouble() ?? 0.0;

    // Costos (según last_purchase_price), calculado sobre los mismos items
    final costRows = await db.rawQuery('''
      SELECT COALESCE(SUM(si.quantity * COALESCE(p.last_purchase_price, 0)), 0) AS cost_sum
      FROM sale_items si
      JOIN products p ON p.id = si.product_id
      JOIN sales s ON s.id = si.sale_id
      WHERE s.date BETWEEN ? AND ?
    ''', [_fromTxt(), _toTxt()]);
    final costSum = (costRows.first['cost_sum'] as num?)?.toDouble() ?? 0.0;

    // Descuentos totales del periodo
    final discRows = await db.rawQuery('''
      SELECT COALESCE(SUM(discount), 0) AS discounts
      FROM sales
      WHERE date BETWEEN ? AND ?
    ''', [_fromTxt(), _toTxt()]);
    final discounts = (discRows.first['discounts'] as num?)?.toDouble() ?? 0.0;

    // Envíos informativos (no entran en utilidad)
    final shipRows = await db.rawQuery('''
      SELECT COALESCE(SUM(shipping_cost), 0) AS shipping
      FROM sales
      WHERE date BETWEEN ? AND ?
    ''', [_fromTxt(), _toTxt()]);
    final shipping = (shipRows.first['shipping'] as num?)?.toDouble() ?? 0.0;

    // Ventas netas = artículos - descuentos (sin envíos)
    final netSales = (itemsSum - discounts).clamp(0.0, double.infinity);
    final profit = netSales - costSum;
    final margin = netSales > 0 ? (profit / netSales) : 0.0;

    // Desglose por método = artículos por método - descuentos por método (sin envíos)
    final payRows = await db.rawQuery('''
      WITH items AS (
        SELECT 
          COALESCE(s.payment_method, '(sin método)') AS method,
          COALESCE(SUM(si.quantity * si.unit_price), 0) AS items_amount,
          COUNT(DISTINCT s.id) AS sales_count
        FROM sales s
        JOIN sale_items si ON si.sale_id = s.id
        WHERE s.date BETWEEN ? AND ?
        GROUP BY method
      ),
      disc AS (
        SELECT
          COALESCE(payment_method, '(sin método)') AS method,
          COALESCE(SUM(discount), 0) AS discounts
        FROM sales
        WHERE date BETWEEN ? AND ?
        GROUP BY method
      )
      SELECT 
        i.method,
        i.items_amount,
        COALESCE(d.discounts, 0) AS discounts,
        i.sales_count
      FROM items i
      LEFT JOIN disc d USING (method)
      ORDER BY (i.items_amount - COALESCE(d.discounts, 0)) DESC
    ''', [_fromTxt(), _toTxt(), _fromTxt(), _toTxt()]);

    // Mapear para UI: amount = items_amount - discounts (no negativo)
    final byMethod = payRows.map((m) {
      final itemsAmount = (m['items_amount'] as num?)?.toDouble() ?? 0.0;
      final disc = (m['discounts'] as num?)?.toDouble() ?? 0.0;
      final amount = (itemsAmount - disc);
      return {
        'method': (m['method'] ?? '(sin método)').toString(),
        'amount': amount < 0 ? 0.0 : amount,
        'sales_count': (m['sales_count'] as num?)?.toInt() ?? 0,
        'raw_items': itemsAmount,
        'raw_discounts': disc,
      };
    }).toList();

    setState(() {
      _itemsSum = itemsSum;
      _discounts = discounts;
      _netSales = netSales;
      _cost = costSum;
      _profit = profit;
      _marginPct = margin;
      _totalShipping = shipping;
      _paymentByMethod = byMethod;
    });
  }

  /// Desglose por producto (sin envíos; NOTA: no prorrateamos descuentos por producto)
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
                // === TARJETA: Resumen (sin envíos) + Envíos informativos + Métodos de pago ===
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Resumen (sin envíos)', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _kv('Ventas de artículos', _money.format(_itemsSum)),
                        _kv('Descuentos (restados)', '- ${_money.format(_discounts)}'),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: _kv('Ventas netas', _money.format(_netSales), bold: true)),
                            Expanded(child: _kv('Costo', _money.format(_cost))),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: _kv('Utilidad', _money.format(_profit), bold: true)),
                            Expanded(child: _kv('Margen', '${(_marginPct * 100).toStringAsFixed(1)}%', bold: true)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _kv('Envíos (informativo)', _money.format(_totalShipping)),
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 6),
                        const Text('Por método de pago (sin envíos, neto de descuentos)', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        if (_paymentByMethod.isEmpty)
                          const Text('Sin ventas en el periodo')
                        else
                          ..._paymentByMethod.map((m) {
                            final method = (m['method'] ?? '(sin método)').toString();
                            final amount = (m['amount'] as num?)?.toDouble() ?? 0.0;
                            final cnt = (m['sales_count'] as num?)?.toInt() ?? 0;
                            final pct = _netSales > 0 ? (amount / _netSales) : 0.0;
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.payments),
                              title: Text(method, style: bold),
                              subtitle: Text('$cnt ventas • ${(pct * 100).toStringAsFixed(1)}%'),
                              trailing: Text(_money.format(amount), style: bold),
                            );
                          }),
                      ],
                    ),
                  ),
                ),

                // === Desglose por producto (sin envíos) ===
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