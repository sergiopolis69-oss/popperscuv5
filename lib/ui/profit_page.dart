// lib/ui/profit_page.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database.dart' as appdb;

class ProfitPage extends StatefulWidget {
  const ProfitPage({super.key});

  @override
  State<ProfitPage> createState() => _ProfitPageState();
}

enum _SortProductsBy { revenue, profit, margin, qty }

class _ProfitPageState extends State<ProfitPage> {
  final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  double _itemsSum = 0.0;
  double _discounts = 0.0;
  double _netSales = 0.0;
  double _cost = 0.0;
  double _profit = 0.0;
  double _marginPct = 0.0;
  double _totalShipping = 0.0;

  List<Map<String, dynamic>> _productRows = [];
  List<Map<String, dynamic>> _paymentByMethod = [];
  List<_DailyProfitPoint> _dailyPerformance = [];

  bool _loading = true;

  // --- NUEVO: UI para énfasis en utilidad por producto
  final TextEditingController _productQ = TextEditingController();
  _SortProductsBy _sortBy = _SortProductsBy.profit;
  bool _sortDesc = true;
  bool _topOnly = false; // top 30
  static const int _topN = 30;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _productQ.dispose();
    super.dispose();
  }

  Future<Database> _db() async {
    try {
      return await appdb.getDb();
    } catch (_) {
      return await appdb.DatabaseHelper.instance.db;
    }
  }

  String _fromTxt() => DateFormat('yyyy-MM-dd').format(_from);
  String _toTxt() => DateFormat('yyyy-MM-dd').format(_to);

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
        _loadSummaryShippingAndPayments(),
        _loadProductsProfit(),
        _loadDailyPerformance(),
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Resumen global: ventas, descuentos, envíos informativos, utilidad, métodos de pago
  Future<void> _loadSummaryShippingAndPayments() async {
    final db = await _db();

    final itemsRows = await db.rawQuery('''
      SELECT COALESCE(SUM(si.quantity * si.unit_price), 0) AS items_sum
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE s.date BETWEEN ? AND ?
    ''', [_fromTxt(), _toTxt()]);
    final itemsSum = (itemsRows.first['items_sum'] as num?)?.toDouble() ?? 0.0;

    final costRows = await db.rawQuery('''
      SELECT COALESCE(SUM(si.quantity * COALESCE(p.last_purchase_price, 0)), 0) AS cost_sum
      FROM sale_items si
      JOIN products p ON p.id = si.product_id
      JOIN sales s ON s.id = si.sale_id
      WHERE s.date BETWEEN ? AND ?
    ''', [_fromTxt(), _toTxt()]);
    final costSum = (costRows.first['cost_sum'] as num?)?.toDouble() ?? 0.0;

    final discRows = await db.rawQuery('''
      SELECT COALESCE(SUM(discount), 0) AS discounts
      FROM sales
      WHERE date BETWEEN ? AND ?
    ''', [_fromTxt(), _toTxt()]);
    final discounts = (discRows.first['discounts'] as num?)?.toDouble() ?? 0.0;

    final shipRows = await db.rawQuery('''
      SELECT COALESCE(SUM(shipping_cost), 0) AS shipping
      FROM sales
      WHERE date BETWEEN ? AND ?
    ''', [_fromTxt(), _toTxt()]);
    final shipping = (shipRows.first['shipping'] as num?)?.toDouble() ?? 0.0;

    final netSales = (itemsSum - discounts).clamp(0.0, double.infinity);
    final profit = netSales - costSum;
    final margin = netSales > 0 ? (profit / netSales) : 0.0;

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

  /// Utilidad por producto (mismo query/cálculo)
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

  /// Tendencia diaria (ventas netas y utilidad por día)
  Future<void> _loadDailyPerformance() async {
    final db = await _db();

    final revenueRows = await db.rawQuery('''
      SELECT DATE(s.date) AS day,
             COALESCE(SUM(si.quantity * si.unit_price), 0) AS revenue,
             COALESCE(SUM(si.quantity * COALESCE(p.last_purchase_price, 0)), 0) AS cost
      FROM sales s
      JOIN sale_items si ON si.sale_id = s.id
      JOIN products p ON p.id = si.product_id
      WHERE DATE(s.date) BETWEEN ? AND ?
      GROUP BY DATE(s.date)
      ORDER BY DATE(s.date)
    ''', [_fromTxt(), _toTxt()]);

    final discountsRows = await db.rawQuery('''
      SELECT DATE(date) AS day, COALESCE(SUM(discount), 0) AS discounts
      FROM sales
      WHERE DATE(date) BETWEEN ? AND ?
      GROUP BY DATE(date)
    ''', [_fromTxt(), _toTxt()]);

    final discountMap = {
      for (final row in discountsRows)
        _normalizeDbDay(row['day']): (row['discounts'] as num?)?.toDouble() ?? 0.0,
    };

    final revenueMap = {
      for (final row in revenueRows)
        _normalizeDbDay(row['day']): (
          (row['revenue'] as num?)?.toDouble() ?? 0.0,
          (row['cost'] as num?)?.toDouble() ?? 0.0,
        ),
    };

    final diff = _to.difference(_from).inDays;
    final points = <_DailyProfitPoint>[];

    for (int i = 0; i <= diff; i++) {
      final day = DateTime(_from.year, _from.month, _from.day).add(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(day);
      final record = revenueMap[key];
      final revenue = record != null ? record.$1 : 0.0;
      final cost = record != null ? record.$2 : 0.0;
      final discounts = discountMap[key] ?? 0.0;

      final net = (revenue - discounts).clamp(0.0, double.infinity);
      final profit = net - cost;

      points.add(_DailyProfitPoint(day: day, netSales: net, profit: profit));
    }

    setState(() => _dailyPerformance = points);
  }

  String _normalizeDbDay(dynamic value) {
    if (value == null) return '';
    if (value is DateTime) {
      return DateFormat('yyyy-MM-dd').format(DateTime(value.year, value.month, value.day));
    }
    final raw = value.toString().trim();
    if (raw.isEmpty) return '';
    DateTime? parsed;
    try {
      parsed = DateTime.tryParse(raw);
    } catch (_) {
      parsed = null;
    }
    parsed ??= DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (parsed != null) {
      return DateFormat('yyyy-MM-dd').format(DateTime(parsed.year, parsed.month, parsed.day));
    }
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }

  Future<void> _shareReport() async {
    final buffer = StringBuffer()
      ..writeln('Reporte de utilidad')
      ..writeln(
        'Periodo: ${DateFormat('dd/MM/yyyy').format(_from)} - ${DateFormat('dd/MM/yyyy').format(_to)}',
      )
      ..writeln('Ventas de artículos: ${_money.format(_itemsSum)}')
      ..writeln('Descuentos: ${_money.format(_discounts)}')
      ..writeln('Ventas netas: ${_money.format(_netSales)}')
      ..writeln('Costo estimado: ${_money.format(_cost)}')
      ..writeln('Utilidad: ${_money.format(_profit)}')
      ..writeln('Margen: ${(100 * _marginPct).toStringAsFixed(1)}%')
      ..writeln('Envíos (informativo): ${_money.format(_totalShipping)}')
      ..writeln('');

    if (_paymentByMethod.isNotEmpty) {
      buffer.writeln('Ventas netas por método de pago:');
      for (final m in _paymentByMethod) {
        final method = (m['method'] ?? '(sin método)').toString();
        final amount = (m['amount'] as num?)?.toDouble() ?? 0.0;
        final count = (m['sales_count'] as num?)?.toInt() ?? 0;
        buffer.writeln(' • $method: ${_money.format(amount)} en $count ventas');
      }
      buffer.writeln('');
    }

    if (_productRows.isNotEmpty) {
      buffer.writeln('Top productos por utilidad:');
      for (final product in _sortedFilteredProducts().take(5)) {
        buffer.writeln(
          ' • ${product['name']} (SKU ${product['sku']}): '
          '${_money.format((product['profit'] as num?)?.toDouble() ?? 0.0)} de utilidad',
        );
      }
    }

    await Share.share(buffer.toString(), subject: 'Reporte de utilidad');
  }

  List<Map<String, dynamic>> _sortedFilteredProducts() {
    final q = _productQ.text.trim().toLowerCase();
    Iterable<Map<String, dynamic>> rows = _productRows;

    if (q.isNotEmpty) {
      rows = rows.where((r) {
        final sku = (r['sku'] ?? '').toString().toLowerCase();
        final name = (r['name'] ?? '').toString().toLowerCase();
        return sku.contains(q) || name.contains(q);
      });
    }

    final list = rows.toList();

    int cmpNum(num a, num b) => _sortDesc ? b.compareTo(a) : a.compareTo(b);
    int cmpD(double a, double b) => _sortDesc ? b.compareTo(a) : a.compareTo(b);

    list.sort((a, b) {
      final aq = (a['qty'] as num?)?.toInt() ?? 0;
      final bq = (b['qty'] as num?)?.toInt() ?? 0;
      final ar = (a['revenue'] as num?)?.toDouble() ?? 0.0;
      final br = (b['revenue'] as num?)?.toDouble() ?? 0.0;
      final ap = (a['profit'] as num?)?.toDouble() ?? 0.0;
      final bp = (b['profit'] as num?)?.toDouble() ?? 0.0;
      final am = (a['margin'] as num?)?.toDouble() ?? 0.0;
      final bm = (b['margin'] as num?)?.toDouble() ?? 0.0;

      switch (_sortBy) {
        case _SortProductsBy.revenue:
          return cmpD(ar, br);
        case _SortProductsBy.profit:
          return cmpD(ap, bp);
        case _SortProductsBy.margin:
          return cmpD(am, bm);
        case _SortProductsBy.qty:
          return cmpNum(aq, bq);
      }
    });

    if (_topOnly && list.length > _topN) {
      return list.take(_topN).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final rangeText = '${DateFormat('dd/MM/yyyy').format(_from)} — ${DateFormat('dd/MM/yyyy').format(_to)}';

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
            child: Text('Periodo: $rangeText', style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _shareReport,
        icon: const Icon(Icons.ios_share),
        label: const Text('Generar reporte'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(12),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _buildSummaryCards(context),
                  const SizedBox(height: 16),
                  _buildPerformanceCard(context),
                  const SizedBox(height: 16),
                  _buildPaymentCard(context),
                  const SizedBox(height: 16),
                  _buildProductsCard(context),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCards(BuildContext context) {
    // Estilo igual a Dashboard: “tarjetas” simples
    final cards = <Widget>[
      _SummaryCard(
        title: 'Ventas de artículos',
        value: _money.format(_itemsSum),
        icon: Icons.shopping_cart_checkout,
        color: Colors.indigo,
      ),
      _SummaryCard(
        title: 'Descuentos',
        value: '- ${_money.format(_discounts)}',
        icon: Icons.percent,
        color: Colors.orange,
      ),
      _SummaryCard(
        title: 'Ventas netas',
        value: _money.format(_netSales),
        icon: Icons.trending_up,
        color: Colors.blue,
      ),
      _SummaryCard(
        title: 'Costo estimado',
        value: _money.format(_cost),
        icon: Icons.inventory,
        color: Colors.deepPurple,
      ),
      _SummaryCard(
        title: 'Utilidad',
        value: _money.format(_profit),
        icon: Icons.attach_money,
        color: Colors.green,
        subtitle: _netSales > 0 ? 'Margen ${(100 * _marginPct).toStringAsFixed(1)}%' : 'Margen 0%',
      ),
      _SummaryCard(
        title: 'Envíos (informativo)',
        value: _money.format(_totalShipping),
        icon: Icons.local_shipping,
        color: Colors.teal,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final maxWidth = constraints.maxWidth;
        double cardWidth;
        if (maxWidth >= 520) {
          cardWidth = (maxWidth - spacing) / 2;
        } else {
          cardWidth = maxWidth;
        }
        if (cardWidth <= 0) cardWidth = maxWidth;

        return Wrap(
          spacing: spacing,
          runSpacing: 12,
          children: cards.map((c) => SizedBox(width: cardWidth, child: c)).toList(),
        );
      },
    );
  }

  Widget _buildPerformanceCard(BuildContext context) {
    if (_dailyPerformance.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tendencia diaria', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('No hay datos suficientes para graficar el periodo seleccionado.'),
            ],
          ),
        ),
      );
    }

    final dayLabel = DateFormat('MM/dd');
    final theme = Theme.of(context);

    final netSpots = <FlSpot>[];
    final profitSpots = <FlSpot>[];
    for (int i = 0; i < _dailyPerformance.length; i++) {
      netSpots.add(FlSpot(i.toDouble(), _dailyPerformance[i].netSales));
      profitSpots.add(FlSpot(i.toDouble(), _dailyPerformance[i].profit));
    }

    final maxY = [...netSpots.map((e) => e.y), ...profitSpots.map((e) => e.y)]
        .fold<double>(0, (prev, value) => value > prev ? value : prev);
    final maxXValue = netSpots.isEmpty ? 0.0 : (netSpots.length - 1).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tendencia diaria', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: maxXValue,
                  minY: 0,
                  maxY: maxY == 0 ? 1 : maxY * 1.2,
                  gridData: const FlGridData(drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 52,
                        interval: maxY == 0 ? 1 : maxY / 4,
                        getTitlesWidget: (value, meta) => Text(
                          _money.format(value),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final index = value.round();
                          if (index < 0 || index >= _dailyPerformance.length) {
                            return const SizedBox.shrink();
                          }
                          return Text(dayLabel.format(_dailyPerformance[index].day),
                              style: const TextStyle(fontSize: 11));
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      tooltipMargin: 12,
                      tooltipRoundedRadius: 12,
                      getTooltipItems: (touches) => touches
                          .map(
                            (spot) => LineTooltipItem(
                              '${dayLabel.format(_dailyPerformance[spot.spotIndex].day)}\n'
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
                  lineBarsData: [
                    LineChartBarData(
                      spots: netSpots,
                      isCurved: true,
                      color: Colors.indigo,
                      barWidth: 4,
                      dotData: const FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: profitSpots,
                      isCurved: true,
                      color: Colors.green,
                      barWidth: 4,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 16,
              children: [
                _LegendEntry(color: Colors.indigo, label: 'Ventas netas'),
                _LegendEntry(color: Colors.green, label: 'Utilidad'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCard(BuildContext context) {
    if (_paymentByMethod.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Métodos de pago', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('No hay ventas registradas en este periodo.'),
            ],
          ),
        ),
      );
    }

    final total = _paymentByMethod.fold<double>(
      0.0,
      (sum, m) => sum + ((m['amount'] as num?)?.toDouble() ?? 0.0),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Métodos de pago', style: TextStyle(fontWeight: FontWeight.bold)),
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
                          for (int i = 0; i < _paymentByMethod.length; i++)
                            PieChartSectionData(
                              color: Colors.primaries[i % Colors.primaries.length].shade400,
                              value: (_paymentByMethod[i]['amount'] as num?)?.toDouble() ?? 0.0,
                              title: total == 0
                                  ? '0%'
                                  : '${(((_paymentByMethod[i]['amount'] as num?)?.toDouble() ?? 0.0) / total * 100).toStringAsFixed(1)}%',
                              radius: 70,
                              titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                        for (int i = 0; i < _paymentByMethod.length; i++)
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
                                Expanded(
                                  child: Text(
                                    (_paymentByMethod[i]['method'] ?? '(sin método)').toString(),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(_money.format((_paymentByMethod[i]['amount'] as num?)?.toDouble() ?? 0.0)),
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

  Widget _buildProductsCard(BuildContext context) {
    final headerStyle =
        Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold);

    final rows = _sortedFilteredProducts();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Utilidad por producto', style: headerStyle)),
                const SizedBox(width: 8),
                Text(
                  '${rows.length}${_topOnly ? ' (top $_topN)' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Buscador + orden
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _productQ,
                    decoration: InputDecoration(
                      labelText: 'Buscar producto (SKU o nombre)',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      suffixIcon: _productQ.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpiar',
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() => _productQ.clear()),
                            ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                DropdownButton<_SortProductsBy>(
                  value: _sortBy,
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _sortBy = v);
                  },
                  items: const [
                    DropdownMenuItem(value: _SortProductsBy.profit, child: Text('Orden: Utilidad')),
                    DropdownMenuItem(value: _SortProductsBy.revenue, child: Text('Orden: Ventas')),
                    DropdownMenuItem(value: _SortProductsBy.margin, child: Text('Orden: Margen')),
                    DropdownMenuItem(value: _SortProductsBy.qty, child: Text('Orden: Cantidad')),
                  ],
                ),
                IconButton(
                  tooltip: _sortDesc ? 'Descendente' : 'Ascendente',
                  onPressed: () => setState(() => _sortDesc = !_sortDesc),
                  icon: Icon(_sortDesc ? Icons.arrow_downward : Icons.arrow_upward),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: _topOnly,
                      onChanged: (v) => setState(() => _topOnly = v),
                    ),
                    Text('Sólo top $_topN'),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),
            if (rows.isEmpty)
              const Text('Sin datos de ventas en el periodo / filtro actual')
            else
              _ProductsTable(rows: rows, money: _money),
          ],
        ),
      ),
    );
  }
}

class _DailyProfitPoint {
  _DailyProfitPoint({required this.day, required this.netSales, required this.profit});
  final DateTime day;
  final double netSales;
  final double profit;
}

// --- Cards estilo DashboardPage
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
    return Container(
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
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.bold),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: theme.textTheme.bodySmall),
          ],
        ],
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
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

// --- Tabla (misma que tenías, pero con pequeñas mejoras visuales sin romper nada)
class _ProductsTable extends StatelessWidget {
  const _ProductsTable({required this.rows, required this.money});
  final List<Map<String, dynamic>> rows;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 44,
        dataRowMinHeight: 42,
        dataRowMaxHeight: 54,
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
          final marginColor = margin >= 0 ? Colors.green : Colors.red;
          final profit = (r['profit'] as num?)?.toDouble() ?? 0.0;
          final profitColor = profit >= 0 ? Colors.green : Colors.red;

          return DataRow(
            cells: [
              DataCell(Text((r['sku'] ?? '').toString())),
              DataCell(
                SizedBox(
                  width: 240,
                  child: Text((r['name'] ?? '').toString(), overflow: TextOverflow.ellipsis),
                ),
              ),
              DataCell(Text(((r['qty'] as num?)?.toInt() ?? 0).toString())),
              DataCell(Text(money.format((r['revenue'] as num?)?.toDouble() ?? 0.0))),
              DataCell(Text(money.format((r['cost'] as num?)?.toDouble() ?? 0.0))),
              DataCell(
                Text(
                  money.format(profit),
                  style: TextStyle(color: profitColor, fontWeight: FontWeight.w600),
                ),
              ),
              DataCell(
                Text(
                  '${(margin * 100).toStringAsFixed(1)}%',
                  style: TextStyle(color: marginColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}