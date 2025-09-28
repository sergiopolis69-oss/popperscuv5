import 'package:sqflite/sqflite.dart';
import '../data/database.dart';
import '../models/purchase.dart';

class PurchaseRepository {
  final _dbF = DatabaseHelper.instance;

  Future<int> createPurchase(Purchase p) async {
    final db = await _dbF.db;
    return await db.transaction<int>((txn) async {
      final id = await txn.insert('purchases', {
        'folio': p.folio,
        'supplier_id': p.supplierId,
        'date': p.date.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      for (final it in p.items) {
        await txn.insert('purchase_items', it.toMap(id));
        final prod = await txn.query('products', where: 'id=?', whereArgs: [it.productId], limit: 1);
        final curr = (prod.isNotEmpty ? (prod.first['stock'] as int? ?? 0) : 0);
        await txn.update(
          'products',
          {
            'stock': curr + it.quantity,
            'last_purchase_price': it.unitCost,
            'last_purchase_date': DateTime.now().toIso8601String(),
          },
          where: 'id=?',
          whereArgs: [it.productId],
        );
      }
      return id;
    });
  }
}
