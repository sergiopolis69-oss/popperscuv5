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
  final _qCtrl = TextEditingController();

  List<Map<String, dynamic>> _sales = [];
  final Map<int, List<Map<String, dynamic>>> _itemsBySale = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  Future<Database> _db() async {
    try {
      return await appdb.getDb();
    } catch (_) {
      return await appdb.DatabaseHelper.instance.db;
    }
  }

  Future<void> _load({String? q}) async {
    setState(() => _loading = true);
    try {
      final db = await _db();
      final hasQ = q != null && q.trim().isNotEmpty;
      final like = hasQ ? '%${q!.trim()}%' : null;

      final heads = await db.rawQuery('''
        SELECT 
          s.id,
          s.date,
          COALESCE(s.payment_method, '') AS payment_method,
          COALESCE(s.place, '') AS place,
          COALESCE(s.customer_phone, '') AS customer_phone,
          COALESCE(s.discount, 0) AS discount,
          COALESCE(s.shipping_cost, 0) AS shipping_cost,
          COALESCE(SUM(si.quantity), 0) AS total_qty,
          COALESCE(SUM(si.quantity * si.unit_price), 0) AS total_amount
        FROM sales s
        LEFT JOIN sale_items si ON si.sale_id = s.id
        LEFT JOIN products p     ON p.id = si.product_id
        ${hasQ ? '''
        WHERE 
          CAST(s.id AS TEXT) LIKE ? OR
          s.date LIKE ? OR
          s.customer_phone LIKE ? OR
          COALESCE(p.sku,'') LIKE ? OR
          COALESCE(p.name,'') LIKE ?
        ''' : ''}
        GROUP BY s.id
        ORDER BY s.date DESC, s.id DESC
      ''', hasQ ? [like, like, like, like, like] : []);

      _itemsBySale.clear();
      if (heads.isNotEmpty) {
        final ids = heads.map((e) => (e['id'] as num).toInt()).toList();
        final placeholders = List.filled(ids.length, '?').join(',');
        final rows = await db.rawQuery('''
          SELECT 
            si.sale_id,
            COALESCE(si.quantity, 0)    AS quantity,
            COALESCE(si.unit_price, 0)  AS unit_price,
            COALESCE(p.sku, '')         AS sku,
            COALESCE(p.name, '')        AS name,
            COALESCE(p.last_purchase_price, 0) AS unit_cost,
            p.id AS product_id
          FROM sale_items si
          JOIN products p ON p.id = si.product_id
          WHERE si.sale_id IN ($placeholders)
          ORDER BY si.sale_id DESC, p.name COLLATE NOCASE
        ''', ids);

        for (final r in rows) {
          final sid = (r['sale_id'] as num).toInt();
          (_itemsBySale[sid] ??= []).add(r);
        }
      }

      setState(() {
        _sales = heads;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmAndDeleteSale(int saleId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar venta'),
        content: const Text('Esto revierte el stock y elimina la venta. ¿Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final db = await _db();
      await db.transaction((txn) async {
        final items = await txn.rawQuery(
          'SELECT product_id, quantity FROM sale_items WHERE sale_id = ?',
          [saleId],
        );
        for (final it in items) {
          final pid = (it['product_id'] as num).toInt();
          final qty = (it['quantity'] as num).toInt();
          await txn.rawUpdate('UPDATE products SET stock = COALESCE(stock,0) + ? WHERE id = ?', [qty, pid]);
        }
        await txn.delete('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
        await txn.delete('sales', where: 'id = ?', whereArgs: [saleId]);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venta eliminada')));
      _load(q: _qCtrl.text.trim());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Búsqueda
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _qCtrl,
            decoration: InputDecoration(
              labelText: 'Buscar (folio, fecha, teléfono o producto)',
              hintText: 'Ej. 120, 2025-11, 5512345678, SKU123',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Buscar',
                icon: const Icon(Icons.manage_search),
                onPressed: () => _load(q: _qCtrl.text.trim()),
              ),
            ),
            onSubmitted: (v) => _load(q: v.trim()),
          ),
        ),
        const SizedBox(height: 4),

        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _sales.isEmpty
                  ? const Center(child: Text('Sin ventas'))
                  : ListView.builder(
                      itemCount: _sales.length,
                      itemBuilder: (_, i) {
                        final s = _sales[i];
                        final sid = (s['id'] as num).toInt();
                        final date = (s['date'] ?? '').toString();
                        final pay = (s['payment_method'] ?? '').toString();
                        final place = (s['place'] ?? '').toString();
                        final phone = (s['customer_phone'] ?? '').toString();
                        final totalQty = (s['total_qty'] as num?)?.toInt() ?? 0;
                        final totalAmt = (s['total_amount'] as num?)?.toDouble() ?? 0.0;
                        final discount = (s['discount'] as num?)?.toDouble() ?? 0.0;
                        final shipping = (s['shipping_cost'] as num?)?.toDouble() ?? 0.0;

                        final items = _itemsBySale[sid] ?? const <Map<String, dynamic>>[];

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                            childrenPadding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                            title: Text('Folio $sid • ${_fmtDate(date)}'),
                            subtitle: Text(
                              [
                                phone.isEmpty ? '(s/ tel)' : phone,
                                pay.isEmpty ? '(s/ pago)' : 'Pago: $pay',
                                place.isEmpty ? null : 'Lugar: $place',
                                '$totalQty pzas',
                                _money.format(totalAmt),
                                if (discount > 0) 'Desc: ${_money.format(discount)}',
                                if (shipping > 0) 'Envío: ${_money.format(shipping)}',
                              ].whereType<String>().join(' • '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              tooltip: 'Eliminar venta',
                              icon: const Icon(Icons.delete_forever),
                              onPressed: () => _confirmAndDeleteSale(sid),
                            ),
                            children: [
                              if (items.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text('Sin renglones'),
                                )
                              else
                                _SaleLinesTable(
                                  items: items,
                                  saleDiscount: discount,
                                  money: _money,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  String _fmtDate(String raw) {
    DateTime? dt = DateTime.tryParse(raw);
    dt ??= DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (dt == null) return raw;
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }
}

class _SaleLinesTable extends StatelessWidget {
  const _SaleLinesTable({
    required this.items,
    required this.saleDiscount,
    required this.money,
  });

  final List<Map<String, dynamic>> items;
  final double saleDiscount;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final lines = <_Line>[];
    double sumGross = 0.0;

    for (final r in items) {
      final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
      final unitPrice = (r['unit_price'] as num?)?.toDouble() ?? 0.0;
      final unitCost = (r['unit_cost'] as num?)?.toDouble() ?? 0.0;
      final gross = qty * unitPrice;
      sumGross += gross;

      lines.add(_Line(
        sku: (r['sku'] ?? '').toString(),
        name: (r['name'] ?? '').toString(),
        qty: qty,
        unitPrice: unitPrice,
        unitCost: unitCost,
        gross: gross,
      ));
    }

    for (final l in lines) {
      final share = sumGross > 0 ? (l.gross / sumGross) : 0.0;
      l.discountAlloc = saleDiscount * share;
      l.finalAmount = (l.gross - l.discountAlloc).clamp(0.0, double.infinity);
      l.cost = l.qty * l.unitCost;
      l.profit = l.finalAmount - l.cost;
    }

    final totalFinal = lines.fold<double>(0.0, (s, l) => s + l.finalAmount);
    final totalCost  = lines.fold<double>(0.0, (s, l) => s + l.cost);
    final totalProfit = totalFinal - totalCost;
    final margin = totalFinal > 0 ? (totalProfit / totalFinal) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            rows: lines.map((l) {
              return DataRow(
                cells: [
                  DataCell(Text(l.sku)),
                  DataCell(SizedBox(width: 220, child: Text(l.name, overflow: TextOverflow.ellipsis))),
                  DataCell(Text(_fmtQ(l.qty))),
                  DataCell(Text(money.format(l.unitPrice))),
                  DataCell(Text(money.format(l.gross))),
                  DataCell(Text(money.format(l.discountAlloc))),
                  DataCell(Text(money.format(l.finalAmount))),
                  DataCell(Text(money.format(l.cost))),
                  DataCell(
                    Text(
                      money.format(l.profit),
                      style: TextStyle(
                        color: l.profit >= 0 ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _TotalChip(label: 'Total final', value: money.format(totalFinal), color: Colors.indigo),
            const SizedBox(width: 8),
            _TotalChip(label: 'Costo', value: money.format(totalCost), color: Colors.deepPurple),
            const SizedBox(width: 8),
            _TotalChip(
              label: 'Utilidad',
              value: money.format(totalProfit),
              color: totalProfit >= 0 ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            _TotalChip(
              label: 'Margen',
              value: '${(margin * 100).toStringAsFixed(1)}%',
              color: margin >= 0 ? Colors.teal : Colors.red,
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (saleDiscount > 0)
          Text(
            'Nota: el descuento total (${money.format(saleDiscount)}) se prorrateó proporcionalmente al bruto de cada línea.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }

  String _fmtQ(double q) => (q == q.roundToDouble()) ? q.toInt().toString() : q.toStringAsFixed(2);
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
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _Line {
  _Line({
    required this.sku,
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.unitCost,
    required this.gross,
  });

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