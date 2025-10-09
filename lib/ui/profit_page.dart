import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

enum ProfitRange { hoy, semana, mes, anio, personalizado }

class ProfitPage extends StatefulWidget {
  const ProfitPage({super.key});
  @override
  State<ProfitPage> createState() => _ProfitPageState();
}

class _ProfitPageState extends State<ProfitPage> {
  ProfitRange _range = ProfitRange.hoy;
  DateTimeRange? _custom;

  double _totalVentas = 0;
  double _totalEnvio = 0;
  double _totalDesc = 0;
  double _utilidad = 0;
  List<Map<String,dynamic>> _porMetodo = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime from, DateTime to) _calcRange() {
    final now = DateTime.now();
    switch (_range) {
      case ProfitRange.hoy:
        final from = DateTime(now.year, now.month, now.day);
        final to = from.add(const Duration(days: 1));
        return (from, to);
      case ProfitRange.semana:
        final weekday = now.weekday;
        final from = DateTime(now.year, now.month, now.day).subtract(Duration(days: weekday - 1));
        final to = from.add(const Duration(days: 7));
        return (from, to);
      case ProfitRange.mes:
        final from = DateTime(now.year, now.month, 1);
        final to = DateTime(now.year, now.month + 1, 1);
        return (from, to);
      case ProfitRange.anio:
        final from = DateTime(now.year, 1, 1);
        final to = DateTime(now.year + 1, 1, 1);
        return (from, to);
      case ProfitRange.personalizado:
        if (_custom != null) return (_custom!.start, _custom!.end);
        final from = DateTime(now.year, now.month, now.day);
        final to = from.add(const Duration(days: 1));
        return (from, to);
    }
  }

  Future<void> _load() async {
    final (from, to) = _calcRange();
    final fromIso = from.toIso8601String();
    final toIso = to.toIso8601String();
    final db = await DatabaseHelper.instance.db;

    // Ventas en rango
    final sales = await db.rawQuery('''
      SELECT id, payment_method, shipping_cost, discount
      FROM sales
      WHERE date >= ? AND date < ?
    ''', [fromIso, toIso]);

    // Items de venta con costo actual (último costo de compra)
    final items = await db.rawQuery('''
      SELECT si.sale_id, si.quantity, si.unit_price, IFNULL(p.last_purchase_price, 0) AS cost
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN products p ON p.id = si.product_id
      WHERE s.date >= ? AND s.date < ?
    ''', [fromIso, toIso]);

    // Totales
    double subtotalVentas = 0;   // Σ precio_venta * qty
    double descTotal = 0;        // Σ descuentos
    double envioTotal = 0;       // Σ envío (solo informativo, NO para utilidad)
    double costoTotal = 0;       // Σ último costo compra * qty

    for (final s in sales) {
      descTotal += (s['discount'] as num?)?.toDouble() ?? 0.0;
      envioTotal += (s['shipping_cost'] as num?)?.toDouble() ?? 0.0;
    }
    for (final it in items) {
      final qty = (it['quantity'] as num).toInt();
      final pv  = (it['unit_price'] as num).toDouble();
      final cst = (it['cost'] as num).toDouble();
      subtotalVentas += pv * qty;
      costoTotal     += cst * qty;
    }

    final utilidad = subtotalVentas - descTotal - costoTotal; // envío excluido
    // Desglose por método de pago (total cobrado): (Σ pv*qty) - descuentos + envío, agrupado por método
    final porMetodo = await db.rawQuery('''
      SELECT s.payment_method,
             IFNULL(SUM(si.quantity * si.unit_price), 0) AS subtotal,
             IFNULL(SUM(CASE WHEN si.rowid IS NOT NULL THEN 0 END), 0) AS dummy, -- truco para forzar group by correcto en sqflite
             SUM(DISTINCT s.discount) AS descuentos_totales,
             SUM(DISTINCT s.shipping_cost) AS envios_totales
      FROM sales s
      LEFT JOIN sale_items si ON si.sale_id = s.id
      WHERE s.date >= ? AND s.date < ?
      GROUP BY s.payment_method
      ORDER BY s.payment_method
    ''', [fromIso, toIso]);

    // Calcula total por método: subtotal - descuentos + envío
    final metodoLista = porMetodo.map((m) {
      final sub = (m['subtotal'] as num?)?.toDouble() ?? 0.0;
      final dsc = (m['descuentos_totales'] as num?)?.toDouble() ?? 0.0;
      final env = (m['envios_totales'] as num?)?.toDouble() ?? 0.0;
      return {
        'payment_method': m['payment_method'] ?? '—',
        'total': sub - dsc + env,
        'subtotal': sub,
        'descuento': dsc,
        'envio': env,
      };
    }).toList();

    setState(() {
      _totalVentas = subtotalVentas - descTotal + envioTotal;
      _totalEnvio  = envioTotal;
      _totalDesc   = descTotal;
      _utilidad    = utilidad;
      _porMetodo   = metodoLista;
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initial = DateTimeRange(
      start: DateTime(now.year, now.month, now.day),
      end: DateTime(now.year, now.month, now.day).add(const Duration(days: 1)),
    );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _custom ?? initial,
    );
    if (picked != null) {
      setState(() {
        _range = ProfitRange.personalizado;
        _custom = picked;
      });
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final (from, to) = _calcRange();
    String labelRango;
    switch (_range) {
      case ProfitRange.hoy: labelRango = 'Hoy'; break;
      case ProfitRange.semana: labelRango = 'Semana'; break;
      case ProfitRange.mes: labelRango = 'Mes'; break;
      case ProfitRange.anio: labelRango = 'Año'; break;
      case ProfitRange.personalizado: labelRango = 'Personalizado'; break;
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 8, runSpacing: 8,
          children: [
            ChoiceChip(label: const Text('Hoy'), selected: _range==ProfitRange.hoy, onSelected: (_){ setState(()=>_range=ProfitRange.hoy); _load(); }),
            ChoiceChip(label: const Text('Semana'), selected: _range==ProfitRange.semana, onSelected: (_){ setState(()=>_range=ProfitRange.semana); _load(); }),
            ChoiceChip(label: const Text('Mes'), selected: _range==ProfitRange.mes, onSelected: (_){ setState(()=>_range=ProfitRange.mes); _load(); }),
            ChoiceChip(label: const Text('Año'), selected: _range==ProfitRange.anio, onSelected: (_){ setState(()=>_range=ProfitRange.anio); _load(); }),
            OutlinedButton.icon(onPressed: _pickCustomRange, icon: const Icon(Icons.date_range), label: const Text('Personalizado')),
          ],
        ),
        const SizedBox(height: 8),
        Text('Rango: ${from.toIso8601String()}  →  ${to.toIso8601String()}  ($labelRango)'),

        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              const ListTile(title: Text('Resumen')),
              ListTile(title: const Text('Total ventas'), trailing: Text('\$${_totalVentas.toStringAsFixed(2)}')),
              ListTile(title: const Text('Total envío cobrado'), trailing: Text('\$${_totalEnvio.toStringAsFixed(2)}')),
              ListTile(title: const Text('Total descuento'), trailing: Text('- \$${_totalDesc.toStringAsFixed(2)}')),
              const Divider(height: 1),
              ListTile(
                title: const Text('Utilidad'),
                trailing: Text('\$${_utilidad.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              const ListTile(title: Text('Ventas por método de pago')),
              ..._porMetodo.map((m) => ListTile(
                title: Text(m['payment_method'].toString()),
                subtitle: Text('Subtotal: \$${(m['subtotal'] as num).toStringAsFixed(2)}  •  Desc: \$${(m['descuento'] as num).toStringAsFixed(2)}  •  Env: \$${(m['envio'] as num).toStringAsFixed(2)}'),
                trailing: Text('\$${(m['total'] as num).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              )),
              if (_porMetodo.isEmpty)
                const Padding(padding: EdgeInsets.all(12), child: Text('Sin ventas en el rango seleccionado')),
            ],
          ),
        ),
      ],
    );
  }
}
