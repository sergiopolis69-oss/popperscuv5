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

  double _totalVentas = 0; // (Σ pv*qty) - Σ descuentos + Σ envío  (solo informativo)
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
        final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
        return (start, start.add(const Duration(days: 7)));
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
        return (from, from.add(const Duration(days: 1)));
    }
  }

  Future<void> _load() async {
    final (from, to) = _calcRange();
    final fromIso = from.toIso8601String();
    final toIso = to.toIso8601String();
    final db = await DatabaseHelper.instance.db;

    // Ventas en rango (para descuentos y envío)
    final sales = await db.rawQuery('''
      SELECT id, payment_method, 
             CAST(IFNULL(discount,0) AS REAL)    AS discount,
             CAST(IFNULL(shipping_cost,0) AS REAL) AS shipping_cost
      FROM sales
      WHERE date >= ? AND date < ?
    ''', [fromIso, toIso]);

    // Items con costo (forzado a REAL)
    final items = await db.rawQuery('''
      SELECT si.sale_id,
             CAST(si.quantity AS INTEGER)           AS quantity,
             CAST(si.unit_price AS REAL)            AS unit_price,
             CAST(IFNULL(p.last_purchase_price,0) AS REAL) AS cost
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN products p ON p.id = si.product_id
      WHERE s.date >= ? AND s.date < ?
    ''', [fromIso, toIso]);

    double subtotalVentas = 0; // Σ pv*qty
    double costoTotal     = 0; // Σ cost*qty
    for (final it in items) {
      final q   = (it['quantity'] as num).toInt();
      final pv  = (it['unit_price'] as num).toDouble();
      final cst = (it['cost'] as num).toDouble();
      subtotalVentas += pv * q;
      costoTotal     += cst * q;
    }

    double descTotal = 0;
    double envioTotal = 0;
    for (final s in sales) {
      descTotal  += (s['discount'] as num).toDouble();
      envioTotal += (s['shipping_cost'] as num).toDouble();
    }

    final utilidad = subtotalVentas - descTotal - costoTotal; // envío excluido

    // ---- Desglose por método de pago (sin duplicaciones) ----
    // 1) Subtotal por venta (Σ pv*qty por sale_id)
    final subtotalesPorVenta = await db.rawQuery('''
      SELECT si.sale_id, SUM(CAST(si.quantity AS REAL) * CAST(si.unit_price AS REAL)) AS sub
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE s.date >= ? AND s.date < ?
      GROUP BY si.sale_id
    ''', [fromIso, toIso]);

    // Map rápido sale_id -> subtotal items
    final Map<int,double> subPorVenta = {
      for (final r in subtotalesPorVenta)
        (r['sale_id'] as int): ((r['sub'] as num?)?.toDouble() ?? 0.0)
    };

    // 2) Agrupar por método sumando: subtotal_items, descuentos, envío
    final Map<String, Map<String,double>> byMethod = {};
    for (final s in sales) {
      final id = s['id'] as int;
      final method = (s['payment_method'] ?? '—').toString();
      byMethod.putIfAbsent(method, ()=> {'subtotal':0,'descuento':0,'envio':0,'total':0});
      final m = byMethod[method]!;
      final sub = subPorVenta[id] ?? 0.0;
      final dsc = (s['discount'] as num).toDouble();
      final env = (s['shipping_cost'] as num).toDouble();
      m['subtotal']  = (m['subtotal'] ?? 0) + sub;
      m['descuento'] = (m['descuento'] ?? 0) + dsc;
      m['envio']     = (m['envio'] ?? 0) + env;
      m['total']     = (m['total'] ?? 0) + (sub - dsc + env);
    }

    final metodoLista = byMethod.entries.map((e) => {
      'payment_method': e.key,
      'subtotal': e.value['subtotal'] ?? 0,
      'descuento': e.value['descuento'] ?? 0,
      'envio': e.value['envio'] ?? 0,
      'total': e.value['total'] ?? 0,
    }).toList();

    setState(() {
      _totalVentas = subtotalVentas - descTotal + envioTotal; // solo informativo
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
        Text('Rango: ${from.toIso8601String()}  →  ${to.toIso8601String()}'),

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