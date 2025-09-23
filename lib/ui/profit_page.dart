
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../repositories/profit_repository.dart';
import '../repositories/sale_repository.dart';

class ProfitPage extends StatefulWidget {
  const ProfitPage({super.key});

  @override
  State<ProfitPage> createState() => _ProfitPageState();
}

class _ProfitPageState extends State<ProfitPage> {
  final _profitRepo = ProfitRepository();
  final _saleRepo = SaleRepository();
  String _from = '2025-01-01';
  String _to = '2030-01-01';
  String _customer = '';
  String _category = '';
  double? _avgPct;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: ListView(
        children: [
          Row(children: [
            Expanded(child: TextFormField(decoration: const InputDecoration(labelText: 'Desde'), initialValue: _from, onChanged: (v)=>_from=v)),
            const SizedBox(width: 8),
            Expanded(child: TextFormField(decoration: const InputDecoration(labelText: 'Hasta'), initialValue: _to, onChanged: (v)=>_to=v)),
          ]),
          TextField(decoration: const InputDecoration(labelText: 'Cliente (teléfono opcional)'), onChanged: (v)=> _customer=v),
          TextField(decoration: const InputDecoration(labelText: 'Categoría (opcional)'), onChanged: (v)=> _category=v),
          const SizedBox(height: 8),
          FilledButton(onPressed: () async {
            final pct = await _profitRepo.weightedProfitPercent(
              from: _from, to: _to,
              customerPhone: _customer.isEmpty ? null : _customer,
              category: _category.isEmpty ? null : _category,
            );
            setState(()=>_avgPct=pct);
          }, child: const Text('Calcular utilidad promedio')),
          const SizedBox(height: 8),
          if (_avgPct != null)
            Text('Utilidad promedio ponderada: ${_avgPct!.toStringAsFixed(2)} %',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(height: 24),
          const Text('Ventas por día (histograma sencillo)', style: TextStyle(fontWeight: FontWeight.bold)),
          FutureBuilder(
            future: _saleRepo.dailyHistogram(_from, _to),
            builder: (context, snap){
              if (!snap.hasData) return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
              final rows = snap.data!;
              final bars = <BarChartGroupData>[];
              for (int i=0;i<rows.length;i++){
                final total = (rows[i]['total'] as num).toDouble();
                bars.add(BarChartGroupData(x: i, barRods: [BarChartRodData(toY: total)]));
              }
              return SizedBox(height: 220, child: BarChart(BarChartData(
                barGroups: bars,
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, meta){
                    if (v.toInt() >= rows.length) return const SizedBox();
                    final label = (rows[v.toInt()]['day'] as String).substring(5);
                    return Transform.rotate(angle: -0.7, child: Text(label, style: const TextStyle(fontSize: 10)));
                  })),
                ),
                gridData: FlGridData(show: false),
                borderData: FlBorderData(show: false),
              )));
            },
          ),
          const SizedBox(height: 16),
          const Text('Utilidad % por día (histograma sencillo)', style: TextStyle(fontWeight: FontWeight.bold)),
          FutureBuilder(
            future: _profitRepo.dailyProfitPercent(_from, _to),
            builder: (context, snap){
              if (!snap.hasData) return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
              final rows = snap.data!;
              final bars = <BarChartGroupData>[];
              for (int i=0;i<rows.length;i++){
                final pct = (rows[i]['pct'] as num).toDouble();
                bars.add(BarChartGroupData(x: i, barRods: [BarChartRodData(toY: pct)]));
              }
              return SizedBox(height: 220, child: BarChart(BarChartData(
                barGroups: bars,
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, meta){
                    if (v.toInt() >= rows.length) return const SizedBox();
                    final label = (rows[v.toInt()]['day'] as String).substring(5);
                    return Transform.rotate(angle: -0.7, child: Text(label, style: const TextStyle(fontSize: 10)));
                  })),
                ),
                gridData: FlGridData(show: false),
                borderData: FlBorderData(show: false),
              )));
            },
          ),
        ],
      ),
    );
  }
}
