import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database.dart' as appdb;
import '../utils/purchase_advisor.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');
  final _dayLabel = DateFormat('MM/dd');

  DateTime _from = DateTime.now().subtract(const Duration(days: 29));
  DateTime _to = DateTime.now();

  bool _loading = true;
  double _netSales = 0;
  double _cost = 0;
  double _profit = 0;
  double _discounts = 0;
  double _shipping = 0;

  List<_DailyPoint> _daily = [];
  List<_CategorySlice> _categories = [];
  List<_TopProduct> _topProducts = [];
  List<PurchaseSuggestion> _suggestions = [];

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
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked == null) return;

    setState(() {
      _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    await _loadAll();
  }

  String _formatDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final db = await _db();
      final summary = await _loadSummary(db);
      final daily = await _loadDailyPerformance(db);
      final categories = await _loadCategoryBreakdown(db);
      final topProducts = await _loadTopProducts(db);
      final suggestions = await fetchPurchaseSuggestions(db, from: _from, to: _to);

      if (!mounted) return;
      setState(() {
        _netSales = summary.netSales;
        _cost = summary.cost;
        _profit = summary.profit;
        _discounts = summary.discounts;
        _shipping = summary.shipping;
        _daily = daily;
        _categories = categories;
        _topProducts = topProducts;
        _suggestions = suggestions;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<_Summary> _loadSummary(Database db) async {
    final itemsRows = await db.rawQuery('''
      SELECT COALESCE(SUM(si.quantity * si.unit_price), 0) AS items_sum
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE s.date BETWEEN ? AND ?
    ''', [_formatDate(_from), _formatDate(_to)]);
    final costRows = await db.rawQuery('''
      SELECT COALESCE(SUM(si.quantity * COALESCE(p.last_purchase_price, 0)), 0) AS cost_sum
      FROM sale_items si
      JOIN products p ON p.id = si.product_id
      JOIN sales s ON s.id = si.sale_id
      WHERE s.date BETWEEN ? AND ?
    ''', [_formatDate(_from), _formatDate(_to)]);
    final discRows = await db.rawQuery('''
      SELECT COALESCE(SUM(discount), 0) AS discounts
      FROM sales
      WHERE date BETWEEN ? AND ?
    ''', [_formatDate(_from), _formatDate(_to)]);
    final shipRows = await db.rawQuery('''
      SELECT COALESCE(SUM(shipping_cost), 0) AS shipping
      FROM sales
      WHERE date BETWEEN ? AND ?
    ''', [_formatDate(_from), _formatDate(_to)]);

    final itemsSum = (itemsRows.first['items_sum'] as num?)?.toDouble() ?? 0.0;
    final cost = (costRows.first['cost_sum'] as num?)?.toDouble() ?? 0.0;
    final discounts = (discRows.first['discounts'] as num?)?.toDouble() ?? 0.0;
    final shipping = (shipRows.first['shipping'] as num?)?.toDouble() ?? 0.0;
    final net = (itemsSum - discounts).clamp(0.0, double.infinity);
    final profit = net - cost;

    return _Summary(
      netSales: net,
      cost: cost,
      profit: profit,
      discounts: discounts,
      shipping: shipping,
    );
  }

  Future<List<_DailyPoint>> _loadDailyPerformance(Database db) async {
    final revenueRows = await db.rawQuery('''
      SELECT s.date AS day,
             COALESCE(SUM(si.quantity * si.unit_price), 0) AS revenue,
             COALESCE(SUM(si.quantity * COALESCE(p.last_purchase_price, 0)), 0) AS cost
      FROM sales s
      JOIN sale_items si ON si.sale_id = s.id
      JOIN products p ON p.id = si.product_id
      WHERE s.date BETWEEN ? AND ?
      GROUP BY s.date
      ORDER BY s.date
    ''', [_formatDate(_from), _formatDate(_to)]);
    final discountsRows = await db.rawQuery('''
      SELECT date AS day, COALESCE(SUM(discount), 0) AS discounts
      FROM sales
      WHERE date BETWEEN ? AND ?
      GROUP BY date
    ''', [_formatDate(_from), _formatDate(_to)]);

    final discountMap = {
      for (final row in discountsRows)
        (row['day'] ?? '').toString(): (row['discounts'] as num?)?.toDouble() ?? 0.0,
    };
    final revenueMap = {
      for (final row in revenueRows)
        (row['day'] ?? '').toString(): (
            (row['revenue'] as num?)?.toDouble() ?? 0.0,
            (row['cost'] as num?)?.toDouble() ?? 0.0)
    };

    final totalDays = _to.difference(_from).inDays;
    final points = <_DailyPoint>[];
    for (int i = 0; i <= totalDays; i++) {
      final day = DateTime(_from.year, _from.month, _from.day).add(Duration(days: i));
      final key = _formatDate(day);
      final revenuePair = revenueMap[key];
      final revenue = revenuePair != null ? revenuePair.$1 : 0.0;
      final cost = revenuePair != null ? revenuePair.$2 : 0.0;
      final discounts = discountMap[key] ?? 0.0;
      final net = (revenue - discounts).clamp(0.0, double.infinity);
      final profit = net - cost;
      points.add(_DailyPoint(day: day, netSales: net, profit: profit));
    }
    return points;
  }

  Future<List<_CategorySlice>> _loadCategoryBreakdown(Database db) async {
    final rows = await db.rawQuery('''
      SELECT COALESCE(NULLIF(TRIM(p.category), ''), '(Sin categoría)') AS category,
             COALESCE(SUM(si.quantity * si.unit_price), 0) AS revenue
      FROM sale_items si
      JOIN products p ON p.id = si.product_id
      JOIN sales s ON s.id = si.sale_id
      WHERE s.date BETWEEN ? AND ?
      GROUP BY category
      ORDER BY revenue DESC
    ''', [_formatDate(_from), _formatDate(_to)]);

    return rows
        .map((row) => _CategorySlice(
              category: (row['category'] ?? '(Sin categoría)').toString(),
              revenue: (row['revenue'] as num?)?.toDouble() ?? 0.0,
            ))
        .where((slice) => slice.revenue > 0)
        .toList();
  }

  Future<List<_TopProduct>> _loadTopProducts(Database db) async {
    final rows = await db.rawQuery('''
      SELECT p.name,
             p.sku,
             COALESCE(SUM(si.quantity), 0) AS qty,
             COALESCE(SUM(si.quantity * si.unit_price), 0) AS revenue,
             COALESCE(SUM(si.quantity * COALESCE(p.last_purchase_price, 0)), 0) AS cost
      FROM products p
      JOIN sale_items si ON si.product_id = p.id
      JOIN sales s ON s.id = si.sale_id
      WHERE s.date BETWEEN ? AND ?
      GROUP BY p.name, p.sku
      HAVING qty > 0
      ORDER BY revenue DESC
      LIMIT 5
    ''', [_formatDate(_from), _formatDate(_to)]);

    return rows
        .map((row) {
          final revenue = (row['revenue'] as num?)?.toDouble() ?? 0.0;
          final cost = (row['cost'] as num?)?.toDouble() ?? 0.0;
          final profit = revenue - cost;
          return _TopProduct(
            name: (row['name'] ?? '').toString(),
            sku: (row['sku'] ?? '').toString(),
            quantity: (row['qty'] as num?)?.toInt() ?? 0,
            revenue: revenue,
            profit: profit,
          );
        })
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final rangeText = '${DateFormat('dd/MM/yyyy').format(_from)} — ${DateFormat('dd/MM/yyyy').format(_to)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tablero'),
        actions: [
          IconButton(onPressed: _pickRange, tooltip: 'Elegir periodo', icon: const Icon(Icons.calendar_month)),
          IconButton(onPressed: _loadAll, tooltip: 'Actualizar', icon: const Icon(Icons.refresh)),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Periodo: $rangeText', style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(12),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _SummaryCard(
                        title: 'Ventas netas',
                        value: _money.format(_netSales),
                        icon: Icons.trending_up,
                        color: Colors.indigo,
                      ),
                      _SummaryCard(
                        title: 'Costo',
                        value: _money.format(_cost),
                        icon: Icons.inventory,
                        color: Colors.deepPurple,
                      ),
                      _SummaryCard(
                        title: 'Utilidad',
                        value: _money.format(_profit),
                        icon: Icons.attach_money,
                        color: Colors.green,
                        subtitle:
                            _netSales > 0 ? 'Margen ${(100 * (_profit / _netSales)).toStringAsFixed(1)}%' : 'Margen 0%',
                      ),
                      _SummaryCard(
                        title: 'Descuentos',
                        value: '- ${_money.format(_discounts)}',
                        icon: Icons.percent,
                        color: Colors.orange,
                      ),
                      _SummaryCard(
                        title: 'Envíos',
                        value: _money.format(_shipping),
                        icon: Icons.local_shipping,
                        color: Colors.teal,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildPerformanceCard(context),
                  const SizedBox(height: 16),
                  _buildCategoryCard(context),
                  const SizedBox(height: 16),
                  _buildTopProductsCard(context),
                  const SizedBox(height: 16),
                  _buildSuggestionsCard(context),
                ],
              ),
            ),
    );
  }

  Widget _buildPerformanceCard(BuildContext context) {
    if (_daily.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Tendencia de ventas y utilidad', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              Text('No hay datos en el periodo seleccionado.'),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final spotsNet = <FlSpot>[];
    final spotsProfit = <FlSpot>[];
    for (int i = 0; i < _daily.length; i++) {
      spotsNet.add(FlSpot(i.toDouble(), _daily[i].netSales));
      spotsProfit.add(FlSpot(i.toDouble(), _daily[i].profit));
    }

    final maxY = [
      ...spotsNet.map((e) => e.y),
      ...spotsProfit.map((e) => e.y),
    ].fold<double>(0, (previousValue, element) => element > previousValue ? element : previousValue);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tendencia de ventas y utilidad', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY == 0 ? 1 : maxY * 1.2,
                  gridData: const FlGridData(drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 52,
                        getTitlesWidget: (value, meta) => Text(_money.format(value), style: const TextStyle(fontSize: 10)),
                        interval: maxY == 0 ? 1 : maxY / 4,
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final index = value.round();
                          if (index < 0 || index >= _daily.length) {
                            return const SizedBox.shrink();
                          }
                          final day = _daily[index].day;
                          return Text(_dayLabel.format(day), style: const TextStyle(fontSize: 11));
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spotsNet,
                      isCurved: true,
                      color: Colors.indigo,
                      barWidth: 4,
                      dotData: const FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: spotsProfit,
                      isCurved: true,
                      color: Colors.green,
                      barWidth: 4,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      tooltipMargin: 12,
                      tooltipRoundedRadius: 12,
                      getTooltipItems: (touchedSpots) => touchedSpots
                          .map(
                            (spot) => LineTooltipItem(
                              '${_dayLabel.format(_daily[spot.spotIndex].day)}\n'
                              '${spot.bar.color == Colors.indigo ? 'Ventas netas' : 'Utilidad'}: '
                              '${_money.format(spot.y)}',
                              TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              children: const [
                _LegendEntry(color: Colors.indigo, label: 'Ventas netas'),
                _LegendEntry(color: Colors.green, label: 'Utilidad'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard(BuildContext context) {
    if (_categories.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Ingresos por categoría', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              Text('No hay ventas registradas para mostrar.'),
            ],
          ),
        ),
      );
    }

    final total = _categories.fold<double>(0, (sum, slice) => sum + slice.revenue);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ingresos por categoría', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: Row(
                children: [
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 4,
                        centerSpaceRadius: 40,
                        sections: [
                          for (int i = 0; i < _categories.length; i++)
                            PieChartSectionData(
                              color: Colors.primaries[i % Colors.primaries.length].shade400,
                              value: _categories[i].revenue,
                              title: '${((_categories[i].revenue / total) * 100).toStringAsFixed(1)}%',
                              radius: 70,
                              titleStyle: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = 0; i < _categories.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Colors.primaries[i % Colors.primaries.length].shade400,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_categories[i].category, overflow: TextOverflow.ellipsis)),
                                Text(_money.format(_categories[i].revenue)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopProductsCard(BuildContext context) {
    if (_topProducts.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Productos destacados', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              Text('Aún no hay productos con ventas en este periodo.'),
            ],
          ),
        ),
      );
    }

    final topRevenue = _topProducts.fold<double>(0, (value, element) => element.revenue > value ? element.revenue : value);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Productos destacados', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ..._topProducts.map((p) {
              final progress = topRevenue == 0 ? 0.0 : (p.revenue / topRevenue).clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                        Text(_money.format(p.revenue)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: progress, minHeight: 8, borderRadius: BorderRadius.circular(8)),
                    const SizedBox(height: 4),
                    Text('SKU ${p.sku} • ${p.quantity} vendidos • Utilidad ${_money.format(p.profit)}'),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsCard(BuildContext context) {
    final headerStyle = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold);
    final money = _money;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sugerencias de compra', style: headerStyle),
            const SizedBox(height: 12),
            if (_suggestions.isEmpty)
              const Text('¡Tu inventario está saludable! No se requieren compras adicionales en este periodo.')
            else
              ..._suggestions.take(5).map(
                (s) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Colors.amber.shade100,
                    child: const Icon(Icons.lightbulb, color: Colors.orange),
                  ),
                  title: Text(s.name),
                  subtitle: Text(
                    'SKU ${s.sku} • Stock ${s.stock} • Ventas recientes ${s.soldLastPeriod}',
                  ),
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Comprar ${s.suggestedQuantity}'),
                      Text(money.format(s.estimatedCost), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            if (_suggestions.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Hay ${_suggestions.length - 5} sugerencias adicionales en Inventario.'),
              ),
          ],
        ),
      ),
    );
  }
}

class _DailyPoint {
  _DailyPoint({required this.day, required this.netSales, required this.profit});

  final DateTime day;
  final double netSales;
  final double profit;
}

class _CategorySlice {
  _CategorySlice({required this.category, required this.revenue});

  final String category;
  final double revenue;
}

class _TopProduct {
  _TopProduct({
    required this.name,
    required this.sku,
    required this.quantity,
    required this.revenue,
    required this.profit,
  });

  final String name;
  final String sku;
  final int quantity;
  final double revenue;
  final double profit;
}

class _Summary {
  _Summary({
    required this.netSales,
    required this.cost,
    required this.profit,
    required this.discounts,
    required this.shipping,
  });

  final double netSales;
  final double cost;
  final double profit;
  final double discounts;
  final double shipping;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}
