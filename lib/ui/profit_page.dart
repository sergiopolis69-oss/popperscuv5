// lib/ui/profit_page.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../db/database.dart';

class ProfitPage extends StatefulWidget {
  const ProfitPage({super.key});

  @override
  State<ProfitPage> createState() => _ProfitPageState();
}

enum Period { today, week, month, year, custom }

class _ProfitPageState extends State<ProfitPage> {
  final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');
  Period _period = Period.today;
  DateTimeRange? _customRange;

  double _ventasNetasSinEnvio = 0.0;
  double _totalEnvio = 0.0;
  double _totalDescuento = 0.0;
  double _utilidad = 0.0;
  final Map<String, double> _ventasPorMetodo = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTimeRange _rangeActual() {
    final now = DateTime.now();
    switch (_period) {
      case Period.today:
        final start = DateTime(now.year, now.month, now.day);
        return DateTimeRange(start: start, end: start.add(const Duration(days: 1)));
      case Period.week:
        final dow = now.weekday;
        final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: dow - 1));
        return DateTimeRange(start: start, end: start.add(const Duration(days: 7)));
      case Period.month:
        final start = DateTime(now.year, now.month, 1);
        final end = (now.month == 12)
            ? DateTime(now.year + 1, 1, 1)
            : DateTime(now.year, now.month + 1, 1);
        return DateTimeRange(start: start, end: end);
      case Period.year:
        final start = DateTime(now.year, 1, 1);
        final end = DateTime(now.year + 1, 1, 1);
        return DateTimeRange(start: start, end: end);
      case Period.custom:
        return _customRange ??
            DateTimeRange(
              start: DateTime(now.year, now.month, now.day),
              end: DateTime(now.year, now.month, now.day).add(const Duration(days: 1)),
            );
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _rangeActual(),
      locale: const Locale('es', 'MX'),
    );
    if (picked != null) {
      setState(() {
        _period = Period.custom;
        _customRange = picked;
      });
      await _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final r = _rangeActual();
    final startIso = r.start.toIso8601String();
    final endIso = r.end.toIso8601String();

    final Database db = await DatabaseHelper.instance.db;

    final rows = await db.rawQuery('''
      SELECT s.id AS sale_id,
             s.payment_method,
             s.shipping_cost,
             s.discount,
             s.date,
             si.quantity,
             si.unit_price,
             p.last_purchase_price
      FROM sales s
      JOIN sale_items si ON si.sale_id = s.id
      JOIN products p    ON p.id = si.product_id
      WHERE s.date >= ? AND s.date < ?
    ''', [startIso, endIso]);

    final Map<int, _SaleAcc> bySale = {};
    for (final m in rows) {
      final saleId = (m['sale_id'] as num).toInt();
      final qty = (m['quantity'] as num).toInt();
      final unitPrice = (m['unit_price'] as num).toDouble();
      final unitCost = (m['last_purchase_price'] as num?)?.toDouble() ?? 0.0;
      final shipping = (m['shipping_cost'] as num?)?.toDouble() ?? 0.0;
      final discount = (m['discount'] as num?)?.toDouble() ?? 0.0;
      final pay = (m['payment_method'] ?? '').toString();

      bySale.putIfAbsent(
        saleId,
        () => _SaleAcc(shipping: shipping, discount: discount, paymentMethod: pay),
      );
      bySale[saleId]!.items.add(_ItemAcc(
        qty: qty,
        unitPrice: unitPrice,
        unitCost: unitCost,
        subtotal: unitPrice * qty,
      ));
    }

    double ventasNetasSinEnvio = 0.0;
    double totalEnvio = 0.0;
    double totalDescuento = 0.0;
    double utilidad = 0.0;
    final Map<String, double> porMetodo = {};

    for (final s in bySale.values) {
      final subtotalVenta = s.items.fold<double>(0.0, (a, b) => a + b.subtotal);
      final ventaNetaSinEnvio = max(0, subtotalVenta - s.discount);
      ventasNetasSinEnvio += ventaNetaSinEnvio;
      totalEnvio += s.shipping;
      totalDescuento += s.discount;

      for (final it in s.items) {
        final propor = subtotalVenta > 0 ? (it.subtotal / subtotalVenta) : 0.0;
        final descItem = s.discount * propor;
        final ganancia = (it.unitPrice - it.unitCost) * it.qty - descItem;
        utilidad += ganancia;
      }

      porMetodo[s.paymentMethod] =
          (porMetodo[s.paymentMethod] ?? 0) + ventaNetaSinEnvio;
    }

    setState(() {
      _ventasNetasSinEnvio = ventasNetasSinEnvio;
      _totalEnvio = totalEnvio;
      _totalDescuento = totalDescuento;
      _utilidad = utilidad;
      _ventasPorMetodo
        ..clear()
        ..addAll(porMetodo);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _rangeActual();
    final pct = _ventasNetasSinEnvio > 0
        ? (_utilidad / _ventasNetasSinEnvio) * 100.0
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Utilidad'),
        actions: [
          PopupMenuButton<Period>(
            initialValue: _period,
            onSelected: (p) async {
              setState(() => _period = p);
              if (p != Period.custom) {
                await _load();
              } else {
                await _pickRange();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: Period.today, child: Text('Hoy')),
              PopupMenuItem(value: Period.week, child: Text('Semana')),
              PopupMenuItem(value: Period.month, child: Text('Mes')),
              PopupMenuItem(value: Period.year, child: Text('Año')),
              PopupMenuItem(value: Period.custom, child: Text('Personalizado…')),
            ],
          ),
          IconButton(onPressed: _pickRange, icon: const Icon(Icons.date_range)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Rango: ${DateFormat.yMMMd('es_MX').format(r.start)} — ${DateFormat.yMMMd('es_MX').format(r.end.subtract(const Duration(milliseconds: 1)))}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  _kv('Ventas netas (sin envío)', _money.format(_ventasNetasSinEnvio),
                      bold: true),
                  _kv('Descuento total', '- ${_money.format(_totalDescuento)}'),
                  _kv('Envío cobrado', _money.format(_totalEnvio)),
                  const Divider(height: 24),
                  _kv('Utilidad', _money.format(_utilidad),
                      big: true, bold: true),
                  _kv('% utilidad sobre ventas netas',
                      '${pct.toStringAsFixed(2)}%', big: true, bold: true),
                  const SizedBox(height: 16),
                  Text('Ventas por método de pago',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  ..._ventasPorMetodo.entries.map(
                    (e) => _kv(
                        '• ${e.key.isEmpty ? "(sin método)" : e.key}',
                        _money.format(e.value)),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Recalcular'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _kv(String k, String v, {bool bold = false, bool big = false}) {
    final base = big
        ? Theme.of(context).textTheme.titleLarge
        : Theme.of(context).textTheme.bodyLarge;
    final style =
        (bold ? base?.copyWith(fontWeight: FontWeight.w700) : base) ??
            const TextStyle();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(k, style: style)),
          Text(v, style: style),
        ],
      ),
    );
  }
}

class _ItemAcc {
  final int qty;
  final double unitPrice;
  final double unitCost;
  final double subtotal;
  _ItemAcc({
    required this.qty,
    required this.unitPrice,
    required this.unitCost,
    required this.subtotal,
  });
}

class _SaleAcc {
  final double shipping;
  final double discount;
  final String paymentMethod;
  final List<_ItemAcc> items = [];
  _SaleAcc({
    required this.shipping,
    required this.discount,
    required this.paymentMethod,
  });
}