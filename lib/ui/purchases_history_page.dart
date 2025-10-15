import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:popperscuv5/data/database.dart' as appdb;

class PurchasesHistoryPage extends StatefulWidget {
  const PurchasesHistoryPage({super.key});

  @override
  State<PurchasesHistoryPage> createState() => _PurchasesHistoryPageState();
}

class _PurchasesHistoryPageState extends State<PurchasesHistoryPage> {
  List<Map<String, dynamic>> _purchases = [];
  final _qCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? q}) async {
    final db = await appdb.getDb();

    final where = (q == null || q.isEmpty)
        ? ''
        : "WHERE p.folio LIKE ? OR p.date LIKE ? OR COALESCE(s.name,'') LIKE ?";
    final args = (q == null || q.isEmpty) ? [] : ['%$q%', '%$q%', '%$q%'];

    final heads = await db.rawQuery('''
      SELECT p.id, p.folio, p.date,
             COALESCE(s.name,'(sin proveedor)') AS supplier_name
      FROM purchases p
      LEFT JOIN suppliers s ON s.id = p.supplier_id
      $where
      ORDER BY p.date DESC, p.id DESC
    ''', args);

    final items = await db.rawQuery('''
      SELECT pi.purchase_id, pr.sku, pr.name, pi.quantity, pi.unit_cost
      FROM purchase_items pi
      JOIN products pr ON pr.id = pi.product_id
      ORDER BY pi.purchase_id DESC, pr.name COLLATE NOCASE
    ''');

    final byPurchase = <int, List<Map<String, dynamic>>>{};
    for (final it in items) {
      final pid = it['purchase_id'] as int;
      byPurchase.putIfAbsent(pid, () => []).add(it);
    }

    final merged = heads.map((h) {
      final id = h['id'] as int;
      final its = byPurchase[id] ?? const [];
      final totalQty = its.fold<int>(0, (a, b) => a + (b['quantity'] as int));
      final total = its.fold<double>(0, (a, b) =>
          a + (b['quantity'] as int) * (b['unit_cost'] as num).toDouble());
      return {
        ...h,
        'items': its,
        'total_qty': totalQty,
        'total_amount': total,
      };
    }).toList();

    if (mounted) setState(() => _purchases = merged);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _qCtrl,
            decoration: InputDecoration(
              labelText: 'Buscar compra (folio/fecha/proveedor)',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => _load(q: _qCtrl.text.trim()),
              ),
            ),
            onSubmitted: (v) => _load(q: v.trim()),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _purchases.length,
            itemBuilder: (ctx, i) {
              final p = _purchases[i];
              final items =
                  (p['items'] as List).cast<Map<String, dynamic>>();
              return Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: ExpansionTile(
                  title: Text(
                      'Folio ${p['folio'] ?? '(sin folio)'} • ${p['date']}'),
                  subtitle: Text(
                      '${p['supplier_name']} • ${p['total_qty']} pzas • \$${(p['total_amount'] as num).toStringAsFixed(2)}'),
                  children: items
                      .map((it) => ListTile(
                            dense: true,
                            title: Text('${it['sku'] ?? ''}  ${it['name']}'),
                            trailing: Text(
                                '${it['quantity']} × \$${(it['unit_cost'] as num).toStringAsFixed(2)}'),
                          ))
                      .toList(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}