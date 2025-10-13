import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart' as appdb;

class ProfitPage extends StatefulWidget {
  const ProfitPage({super.key});

  @override
  State<ProfitPage> createState() => _ProfitPageState();
}

enum DetailMode { product, category }

class _ProfitPageState extends State<ProfitPage> {
  DateTimeRange? _range;
  bool _loading = false;

  // Totales
  double _salesTotal = 0.0;   // ventas sin envío (ya con descuento)
  double _profitTotal = 0.0;
  double _profitPercent = 0.0;

  // Detalle
  DetailMode _detailMode = DetailMode.product;
  late final NumberFormat _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

  List<_DetailRow> _byProduct = [];
  List<_DetailRow> _byCategory = [];

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
    final Database db = await appdb.DatabaseHelper.instance.db;

    final start = _range?.start ?? DateTime.now().subtract(const Duration(days: 30));
    final end = _range?.end ?? DateTime.now();

    // Traemos ventas del rango
    final sales = await db.rawQuery('''
      SELECT s.id, s.shipping_cost, s.discount
      FROM sales s
      WHERE date(s.date) BETWEEN ? AND ?
    ''', [start.toIso8601String(), end.toIso8601String()]);

    double totalVentas = 0.0;
    double totalUtilidad = 0.0;

    // Acumuladores detalle
    final Map<String, _Agg> aggByProduct = {};
    final Map<String, _Agg> aggByCategory = {};

    for (final sale in sales) {
      final int saleId = (sale['id'] as num).toInt();
      final double discount = (sale['discount'] as num?)?.toDouble() ?? 0.0;

      // Items de la venta con info de producto
      final items = await db.rawQuery('''
        SELECT
          si.quantity AS qty,
          si.unit_price AS price,
          p.last_purchase_price AS cost,
          p.sku AS sku,
          p.name AS name,
          IFNULL(p.category, '') AS category
        FROM sale_items si
        JOIN products p ON p.id = si.product_id
        WHERE si.sale_id = ?
      ''', [saleId]);

      if (items.isEmpty) continue;

      final double subtotal = items.fold<double>(
        0.0,
        (a, it) => a + ((it['price'] as num).toDouble() * (it['qty'] as num).toDouble()),
      );

      // Descuento proporcional por línea y cálculo de utilidad línea
      double utilidadVenta = 0.0;
      for (final it in items) {
        final int qty = (it['qty'] as num).toInt();
        final double precio = (it['price'] as num).toDouble();
        final double costo = (it['cost'] as num?)?.toDouble() ?? 0.0;
        final String sku = (it['sku'] ?? '').toString();
        final String name = (it['name'] ?? '').toString();
        final String category = (it['category'] ?? '').toString();

        final double bruto = precio * qty;
        final double share = subtotal > 0 ? bruto / subtotal : 0.0;
        final double descLinea = discount * share;
        final double netoLinea = bruto - descLinea;
        final double utilidadLinea = netoLinea - (costo * qty);

        utilidadVenta += utilidadLinea;

        // Acumular por producto (clave: "SKU · Nombre" para hacerlo claro)
        final prodKey = sku.isEmpty ? name : '$sku · $name';
        final ap = aggByProduct.putIfAbsent(prodKey, () => _Agg(label: prodKey));
        ap.qty += qty;
        ap.revenue += netoLinea; // venta neta (tras descuento proporcional)
        ap.cost += costo * qty;
        ap.profit += utilidadLinea;

        // Acumular por categoría (vacía se muestra como "Sin categoría")
        final catKey = category.isEmpty ? 'Sin categoría' : category;
        final ac = aggByCategory.putIfAbsent(catKey, () => _Agg(label: catKey));
        ac.qty += qty;
        ac.revenue += netoLinea;
        ac.cost += costo * qty;
        ac.profit += utilidadLinea;
      }

      totalVentas += subtotal - discount; // sin envío
      totalUtilidad += utilidadVenta;
    }

    final percent = totalVentas > 0 ? (totalUtilidad / totalVentas) * 100.0 : 0.0;

    // Empaquetar filas detalle (ordenado por utilidad desc)
    List<_DetailRow> toRows(Map<String, _Agg> src) {
      final rows = src.values
          .map((a) => _DetailRow(
                label: a.label,
                qty: a.qty,
                revenue: a.revenue,
                cost: a.cost,
                profit: a.profit,
                margin: a.revenue > 0 ? (a.profit / a.revenue) * 100.0 : 0.0,
              ))
          .toList();
      rows.sort((b, a) => a.profit.compareTo(b.profit));
      return rows;
    }

    setState(() {
      _salesTotal = totalVentas;
      _profitTotal = totalUtilidad;
      _profitPercent = percent;
      _byProduct = toRows(aggByProduct);
      _byCategory = toRows(aggByCategory);
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

                  // Selector de detalle
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Por producto'),
                        selected: _detailMode == DetailMode.product,
                        onSelected: (v) {
                          if (v) setState(() => _detailMode = DetailMode.product);
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Por categoría'),
                        selected: _detailMode == DetailMode.category,
                        onSelected: (v) {
                          if (v) setState(() => _detailMode = DetailMode.category);
                        },
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Ordenar por utilidad desc/asc',
                        icon: const Icon(Icons.swap_vert),
                        onPressed: _toggleSort,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  _detailTable(
                    _detailMode == DetailMode.product ? _byProduct : _byCategory,
                  ),

                  const SizedBox(height: 16),
                  Text(
                    'La utilidad se calcula por cada producto como:\n'
                    'precio de venta – costo último de compra – descuento proporcional.\n'
                    'El costo de envío no se incluye en este cálculo.',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
    );
  }

  // Cambia el orden de utilidad
  void _toggleSort() {
    setState(() {
      List<_DetailRow> list =
          _detailMode == DetailMode.product ? _byProduct : _byCategory;
      final bool isDesc = list.length < 2 ||
          (list.length >= 2 && list.first.profit >= list.last.profit);
      list.sort((a, b) => isDesc
          ? a.profit.compareTo(b.profit)
          : b.profit.compareTo(a.profit));
      if (_detailMode == DetailMode.product) {
        _byProduct = List.of(list);
      } else {
        _byCategory = List.of(list);
      }
    });
  }

  Widget _detailTable(List<_DetailRow> rows) {
    if (rows.isEmpty) {
      return const Card(
        elevation: 0,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No hay ventas en el periodo seleccionado.'),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Ítem')),
            DataColumn(label: Text('Cant.')),
            DataColumn(label: Text('Venta neta')),
            DataColumn(label: Text('Costo')),
            DataColumn(label: Text('Utilidad')),
            DataColumn(label: Text('Margen %')),
          ],
          rows: rows.map((r) {
            return DataRow(cells: [
              DataCell(Text(r.label)),
              DataCell(Text(r.qty.toString())),
              DataCell(Text(_money.format(r.revenue))),
              DataCell(Text(_money.format(r.cost))),
              DataCell(Text(_money.format(r.profit))),
              DataCell(Text('${r.margin.toStringAsFixed(2)} %')),
            ]);
          }).toList(),
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

// Accumulador interno
class _Agg {
  _Agg({required this.label});
  final String label;
  int qty = 0;
  double revenue = 0.0; // venta neta (con descuento proporcional)
  double cost = 0.0;
  double profit = 0.0;
}

// Fila para la DataTable
class _DetailRow {
  _DetailRow({
    required this.label,
    required this.qty,
    required this.revenue,
    required this.cost,
    required this.profit,
    required this.margin,
  });

  final String label;
  final int qty;
  final double revenue;
  final double cost;
  final double profit;
  final double margin;
}