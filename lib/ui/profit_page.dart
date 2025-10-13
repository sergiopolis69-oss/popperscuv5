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
  DateTimeRange? _range;
  bool _loading = false;
  double _salesTotal = 0.0;
  double _profitTotal = 0.0;
  double _profitPercent = 0.0;
  final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range ??
          DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: now,
          ),
    );
    if (r != null) {
      setState(() => _range = r);
      await _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = await appdb.DatabaseHelper.instance.db;
    final start = _range?.start ?? DateTime.now().subtract(const Duration(days: 30));
    final end = _range?.end ?? DateTime.now();

    // Ventas dentro del rango
    final sales = await db.rawQuery('''
      SELECT s.id, s.shipping_cost, s.discount
      FROM sales s
      WHERE date(s.date) BETWEEN ? AND ?
    ''', [start.toIso8601String(), end.toIso8601String()]);

    double totalVentas = 0.0;
    double totalUtilidad = 0.0;

    for (final sale in sales) {
      final saleId = sale['id'] as int;
      final shipping = (sale['shipping_cost'] as num?)?.toDouble() ?? 0.0;
      final discount = (sale['discount'] as num?)?.toDouble() ?? 0.0;

      // Productos de la venta
      final items = await db.rawQuery('''
        SELECT si.quantity, si.unit_price, p.last_purchase_price
        FROM sale_items si
        JOIN products p ON p.id = si.product_id
        WHERE si.sale_id = ?
      ''', [saleId]);

      if (items.isEmpty) continue;

      final subtotal = items.fold<double>(
          0.0, (a, it) => a + ((it['unit_price'] as num) * (it['quantity'] as num)));

      // Descuento proporcional
      double utilidadVenta = 0.0;
      for (final it in items) {
        final precio = (it['unit_price'] as num).toDouble();
        final qty = (it['quantity'] as num).toInt();
        final costo = (it['last_purchase_price'] as num?)?.toDouble() ?? 0.0;
        final bruto = precio * qty;
        final share = subtotal > 0 ? bruto / subtotal : 0.0;
        final descuentoLinea = discount * share;
        final neto = bruto - descuentoLinea;
        utilidadVenta += (neto - costo * qty);
      }

      totalVentas += subtotal - discount; // sin envío
      totalUtilidad += utilidadVenta;
    }

    final percent = totalVentas > 0 ? (totalUtilidad / totalVentas) * 100.0 : 0.0;

    setState(() {
      _salesTotal = totalVentas;
      _profitTotal = totalUtilidad;
      _profitPercent = percent;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    final rangeLabel = _range == null
        ? 'Últimos 30 días'
        : '${df.format(_range!.start)} – ${df.format(_range!.end)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Utilidades'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _pickRange,
            tooltip: 'Elegir rango de fechas',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(rangeLabel,
                      style: const TextStyle(fontSize: 16, color: Colors.black54)),
                  const SizedBox(height: 12),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _row('Ventas (sin envío)', _money.format(_salesTotal)),
                          _row('Utilidad neta', _money.format(_profitTotal),
                              color: Colors.green.shade700, bold: true),
                          const Divider(height: 20),
                          _row('Margen de utilidad', 
                              '${_profitPercent.toStringAsFixed(2)} %',
                              color: Colors.indigo, bold: true, big: true),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'La utilidad se calcula por cada producto como: '
                    'precio de venta – costo último de compra – descuento proporcional. '
                    'El costo de envío no se incluye en este cálculo.',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _row(String k, String v,
      {bool bold = false, bool big = false, Color? color}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: big ? 20 : 16,
      color: color ?? Colors.black87,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(k, style: style), Text(v, style: style)],
      ),
    );
  }
}