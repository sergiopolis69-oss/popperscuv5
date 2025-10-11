import 'package:sqflite/sqflite.dart';
import '../data/database_provider.dart';

class PurchaseRepository {
  Future<Database> get _db async => DatabaseProvider.instance.database;

  Future<int> create({
    String? folio,
    required String dateIso,
    String? supplierId,
    required List<Map<String, Object?>> items, // {sku, name, qty, cost}
  }) async {
    final db = await _db;
    return await db.transaction<int>((txn) async {
      final id = await txn.insert('purchases', {
        'folio': folio,
        'date': dateIso,
        'supplier_id': supplierId,
      });

      for (final it in items) {
        final sku = it['sku'] as String;
        final name = it['name'] as String;
        final qty  = (it['qty'] as num).toDouble();
        final cost = (it['cost'] as num).toDouble();

        await txn.insert('purchase_items', {
          'purchase_id': id,
          'product_sku': sku,
          'product_name': name,
          'quantity': qty,
          'unit_cost': cost,
        });

        // aumentar stock y actualizar último costo/fecha
        await txn.rawUpdate('''
          UPDATE products
             SET stock = COALESCE(stock,0) + ?,
                 last_purchase_price = ?,
                 last_purchase_date = ?
           WHERE sku = ?
        ''', [qty, cost, dateIso, sku]);
      }
      return id;
    });
  }

  Future<List<Map<String, Object?>>> history({String? folioLike, String? dateFrom, String? dateTo}) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];
    if (folioLike != null && folioLike.trim().isNotEmpty) {
      where.add('folio LIKE ?'); args.add('%${folioLike.trim()}%');
    }
    if (dateFrom != null) { where.add('date >= ?'); args.add(dateFrom); }
    if (dateTo   != null) { where.add('date <= ?'); args.add(dateTo); }

    final sql = '''
      SELECT * FROM purchases
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY date DESC, id DESC
      LIMIT 500
    ''';
    return db.rawQuery(sql, args);
  }

  Future<List<Map<String, Object?>>> itemsOf(int purchaseId) async {
    final db = await _db;
    return db.query('purchase_items', where: 'purchase_id = ?', whereArgs: [purchaseId], orderBy: 'id ASC');
  }
}