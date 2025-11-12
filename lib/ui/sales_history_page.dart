// lib/ui/sales_history_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database.dart' as appdb;

class SalesHistoryPage extends StatefulWidget {
  const SalesHistoryPage({Key? key}) : super(key: key);

  @override
  State<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends State<SalesHistoryPage> {
  final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  bool _loading = true;

  late Future<Database> _db;
  List<_SaleHeader> _sales = [];

  @override
  void initState() {
    super.initState();
    _db = _safeDb();
    _load();
  }

  Future<Database> _safeDb() async {
    try {
      return await appdb.getDb();
    } catch (_) {
      return await appdb.DatabaseHelper.instance.db;
    }
  }

  // Texto ISO fecha (solo día) para inicio inclusivo
  String _fromTxtDay() => DateFormat('yyyy-MM-dd').format(
        DateTime(_from.year, _from.month, _from.day),
      );

  // Texto ISO día siguiente (exclusivo) -> evita perder ventas con hora
  String _toTxtNextDay() {
    final next = DateTime(_to.year, _to.month, _to.day).add(const Duration(days: 1));
    return DateFormat('yyyy-MM-dd').format(next);
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
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final db = await _db;
      // Rango semiabierto: [from, toNextDay)
      final headers = await db.rawQuery('''
        SELECT
          s.id,
          s.date,
          s.customer_id,
          COALESCE(c.name, '') AS customer_name,
          COALESCE(c.phone, '') AS customer_phone,
          COALESCE(s.payment_method, '') AS payment_method,
          COALESCE(s.discount, 0) AS discount,
          COALESCE(s.shipping_cost, 0) AS shipping_cost
        FROM sales s
        LEFT JOIN customers c ON c.id = s.customer_id
        WHERE s.date >= ? AND s.date < ?
        ORDER BY s.date DESC, s.id DESC
      ''', [_fromTxtDay(), _toTxtNextDay()]);

      _sales = headers.map((h) {
        return _SaleHeader(
          id: (h['id'] as num).toInt(),
          date: (h['date'] ?? '').toString(),
          customerName: (h['customer_name'] ?? '').toString(),
          customerPhone: (h['customer_phone'] ?? '').toString(),
          paymentMethod: (h['payment_method'] ?? '').toString(),
          discount: (h['discount'] as num?)?.toDouble() ?? 0.0,
          shipping: (h['shipping_cost'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<_SaleBreakdown> _loadSaleDetail(int saleId, double saleDiscount) async {
    final db = await _db;
    // Detalle de líneas con último costo guardado
    final rows = await db.rawQuery('''
      SELECT
        si.product_id,
        COALESCE(p.sku,'')        AS sku,
        COALESCE(p.name,'')       AS product_name,
        COALESCE(p.last_purchase_price, 0) AS unit_cost,
        COALESCE(si.quantity, 0)  AS qty,
        COALESCE(si.unit_price, 0) AS unit_price
      FROM sale_items si
      JOIN products p ON p.id = si.product_id
      WHERE si.sale_id = ?
      ORDER BY p.name COLLATE NOCASE
    ''', [saleId]);

    final lines = <_SaleLine>[];
    double sumGross = 0.0;

    for (final r in rows) {
      final qty = (r['qty'] as num?)?.toDouble() ?? 0.0;
      final unitPrice = (r['unit_price'] as num?)?.toDouble() ?? 0.0;
      final unitCost = (r['unit_cost'] as num?)?.toDouble() ?? 0.0;
      final gross = qty * unitPrice;
      sumGross += gross;

      lines.add(_SaleLine(
        productId: (r['product_id'] as num).toInt(),
        sku: (r['sku'] ?? '').toString(),
        name: (r['product_name'] ?? '').toString(),
        qty: qty,
        unitPrice: unitPrice,
        unitCost: unitCost,
        gross: gross,
      ));
    }

    // Prorrateo del descuento total de la venta por importe bruto
    for (final l in lines) {
      final share = sumGross > 0 ? (l.gross / sumGross) : 0.0;
      final discAlloc = saleDiscount * share;
      final finalLine = (l.gross - discAlloc).clamp(0.0, double.infinity);
      final costLine = l.qty * l.unitCost;
      final profitLine = finalLine - costLine;

      l.discountAlloc = discAlloc;
      l.finalAmount = finalLine;
      l.cost = costLine;
      l.profit = profitLine;
    }

    final totalFinal = lines.fold<double>(0.0, (s, l) => s + l.finalAmount);
    final totalCost = lines.fold<double>(0.0, (s, l) => s + l.cost);
    final totalProfit = totalFinal - totalCost;
    final margin = totalFinal > 0 ? (totalProfit / totalFinal) : 0.0;

    return _SaleBreakdown(
      lines: lines,
      totalFinal: totalFinal,
      totalCost: totalCost,
      totalProfit: totalProfit,
      margin: margin,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rangeText =
        '${DateFormat('dd/MM/yyyy').format(_from)} — ${DateFormat('dd/MM/yyyy').format(_to)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de ventas'),
        actions: [
          IconButton(
            tooltip: 'Elegir periodo',
            onPressed: _pickRange,
            icon: const Icon(Icons.calendar_today),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Periodo: $rangeText',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sales.isEmpty
              ? const Center(child: Text('No hay ventas en el periodo.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemBuilder: (_, i) => _SaleTile(
                    header: _sales[i],
                    money: _money,
                    loadDetail: () => _loadSaleDetail(_sales[i].id, _sales[i].discount),
                  ),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemCount: _sales.length,
                ),
    );
  }
}

class _SaleTile extends StatefulWidget {
  const _SaleTile({
    required this.header,
    required this.money,
    required this.loadDetail,
  });

  final _SaleHeader header;
  final NumberFormat money;
  final Future<_SaleBreakdown> Function() loadDetail;

  @override
  State<_SaleTile> createState() => _SaleTileState();
}

class _SaleTileState extends State<_SaleTile> {
  _SaleBreakdown? _detail;
  bool _loading = false;

  Future<void> _ensureDetail() async {
    if (_detail != null || _loading) return;
    setState(() => _loading = true);
    try {
      _detail = await widget.loadDetail();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.header;
    final theme = Theme.of(context);

    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(
          'Venta #${h.id} • ${h.paymentMethod.isEmpty ? '(sin método)' : h.paymentMethod}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_fmtDate(h.date)} • ${h.customerName.isEmpty ? 'Cliente sin nombre' : h.customerName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
        onExpansionChanged: (open) {
          if (open) _ensureDetail();
        },
        childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_detail == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Sin detalles', style: theme.textTheme.bodyMedium),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tabla de líneas
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('SKU')),
                      DataColumn(label: Text('Producto')),
                      DataColumn(label: Text('Cant.')),
                      DataColumn(label: Text('PU')),
                      DataColumn(label: Text('Bruto')),
                      DataColumn(label: Text('Desc. asignado')),
                      DataColumn(label: Text('Final')),
                      DataColumn(label: Text('Costo')),
                      DataColumn(label: Text('Utilidad')),
                    ],
                    rows: _detail!.lines.map((l) {
                      return DataRow(
                        cells: [
                          DataCell(Text(l.sku)),
                          DataCell(SizedBox(
                            width: 220,
                            child: Text(l.name, overflow: TextOverflow.ellipsis),
                          )),
                          DataCell(Text(_fmtQ(l.qty))),
                          DataCell(Text(widget.money.format(l.unitPrice))),
                          DataCell(Text(widget.money.format(l.gross))),
                          DataCell(Text(widget.money.format(l.discountAlloc))),
                          DataCell(Text(widget.money.format(l.finalAmount))),
                          DataCell(Text(widget.money.format(l.cost))),
                          DataCell(Text(
                            widget.money.format(l.profit),
                            style: TextStyle(
                              color: l.profit >= 0 ? Colors.green : Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          )),
                        ],
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 10),
                // Totales y margen
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _TotalChip(
                      label: 'Total final',
                      value: widget.money.format(_detail!.totalFinal),
                      color: Colors.indigo,
                    ),
                    const SizedBox(width: 8),
                    _TotalChip(
                      label: 'Costo',
                      value: widget.money.format(_detail!.totalCost),
                      color: Colors.deepPurple,
                    ),
                    const SizedBox(width: 8),
                    _TotalChip(
                      label: 'Utilidad',
                      value: widget.money.format(_detail!.totalProfit),
                      color: _detail!.totalProfit >= 0 ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    _TotalChip(
                      label: 'Margen',
                      value: '${(_detail!.margin * 100).toStringAsFixed(1)}%',
                      color: _detail!.margin >= 0 ? Colors.teal : Colors.red,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Nota: el descuento total (${widget.money.format(h.discount)}) se prorrateó por importe bruto de cada línea.',
                  style: theme.textTheme.bodySmall,
                ),
                if (h.shipping > 0)
                  Text('Envío (informativo): ${widget.money.format(h.shipping)}',
                      style: theme.textTheme.bodySmall),
              ],
            ),
        ],
      ),
    );
  }

  String _fmtDate(String raw) {
    DateTime? dt = DateTime.tryParse(raw);
    dt ??= DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (dt == null) return raw;
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }

  String _fmtQ(double q) {
    if (q == q.roundToDouble()) return q.toInt().toString();
    return q.toStringAsFixed(2);
  }
}

class _TotalChip extends StatelessWidget {
  const _TotalChip({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          Text(value,
              style: theme.textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}

class _SaleHeader {
  _SaleHeader({
    required this.id,
    required this.date,
    required this.customerName,
    required this.customerPhone,
    required this.paymentMethod,
    required this.discount,
    required this.shipping,
  });

  final int id;
  final String date;
  final String customerName;
  final String customerPhone;
  final String paymentMethod;
  final double discount;
  final double shipping;
}

class _SaleLine {
  _SaleLine({
    required this.productId,
    required this.sku,
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.unitCost,
    required this.gross,
  });

  final int productId;
  final String sku;
  final String name;
  final double qty;
  final double unitPrice;
  final double unitCost;

  final double gross; // qty * unitPrice
  double discountAlloc = 0.0;
  double finalAmount = 0.0;
  double cost = 0.0;
  double profit = 0.0;
}

class _SaleBreakdown {
  _SaleBreakdown({
    required this.lines,
    required this.totalFinal,
    required this.totalCost,
    required this.totalProfit,
    required this.margin,
  });

  final List<_SaleLine> lines;
  final double totalFinal;
  final double totalCost;
  final double totalProfit;
  final double margin;
}