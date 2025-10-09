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
        final weekday = now.weekday; // 1=Lunes
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

    // 1) Ventas dentro del rango
    final sales = await db.rawQuery('''
      SELECT id, shipping_cost, discount
      FROM sales
      WHERE date >= ? AND date < ?
    ''', [fromIso, toIso]);

    // 2) Items + costo actual del producto (aprox)
    final items = await db.rawQuery('''
      SELECT si.sale_id, si.quantity, si.unit_price, IFNULL(p.last_purchase_price, 0) AS cost
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN products p ON p.id = si.product_id
      WHERE s.date >= ? AND s.date < ?
    ''', [fromIso, toIso]);

    double subtotal = 0;
    double descTotal = 0;
    double envioTotal = 0;

    final discountsBySale = <int,double>{};
    for (final s in sales) {
      final id = (s['id'] as int);
      final d = (s['discount'] as num?)?.toDouble() ?? 0.0;
      final ship = (s['shipping_cost'] as num?)?.toDouble() ?? 0.0;
      discountsBySale[id] = d;
      descTotal += d;
      envioTotal += ship;
    }

    double utilidadBrutaItems = 0;
    // acumulamos por venta para distribuir descuento proporcional a monto de esa venta
    final totalsBySale = <int,double>{};
    for (final it in items) {
      final saleId = (it['sale_id'] as int);
      final qty = (it['quantity'] as num).toInt();
      final price = (it['unit_price'] as num).toDouble();
      subtotal += price * qty;
      totalsBySale.update(saleId, (v)=> v + price * qty, ifAbsent: ()=> price * qty);
    }
    // utilidad bruta por ítem (sin descuento)
    for (final it in items) {
      final saleId = (it['sale_id'] as int);
      final qty = (it['quantity'] as num).toInt();
      final price = (it['unit_price'] as num).toDouble();
      final cost = (it['cost'] as num).toDouble();
      final discSale = discountsBySale[saleId] ?? 0.0;
      final totalSale = totalsBySale[saleId] ?? 1.0;
      final discPart = totalSale <= 0 ? 0.0 : discSale * ((price * qty) / totalSale); // distribución proporcional
      utilidadBrutaItems += (price - cost) * qty - discPart;
    }

    setState(() {
      _totalVentas = subtotal - descTotal + envioTotal;
      _totalEnvio = envioTotal;
      _totalDesc  = descTotal;
      _utilidad   = utilidadBrutaItems; // envío excluido; descuentos ya restados
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
      ],
    );
  }
}
