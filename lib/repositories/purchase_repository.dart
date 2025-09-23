
import '../data/database.dart';
import '../models/purchase.dart';

class PurchaseRepository {
  Future<int> createPurchase(Purchase p, List<PurchaseItem> items) async {
    final db = await AppDatabase().db();
    return await db.transaction<int>((txn) async {
      final pid = await txn.insert('purchases', p.toMap());
      for (final it in items) {
        await txn.insert('purchase_items', {
          ...it.toMap(),
          'purchaseId': pid,
        });
        // actualizar último costo/fecha y sumar stock
        await txn.rawUpdate('UPDATE products SET lastPurchasePrice=?, lastPurchaseDate=?, stock = stock + ? WHERE id=?',
          [it.unitCost, p.date, it.quantity, it.productId]);
      }
      return pid;
    });
  }

  Future<List<Map<String, Object?>>> recentPurchases() async {
    final db = await AppDatabase().db();
    final res = await db.rawQuery('''
      SELECT p.id, p.date, p.supplier, SUM(pi.quantity*pi.unitCost) as total
      FROM purchases p
      JOIN purchase_items pi ON pi.purchaseId=p.id
      GROUP BY p.id
      ORDER BY p.date DESC
      LIMIT 50;
    ''');
    return res;
  }
}
