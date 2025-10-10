import 'package:sqflite/sqflite.dart';
import '../data/db.dart';

class PurchasesRepository {
  Future<Database> get _db async => openAppDb();

  Future<int> createPurchase(Map<String,Object?> header, List<Map<String,Object?>> items) async {
    final db = await _db;
    return db.transaction<int>((txn) async {
      final id = await txn.insert('purchases', header);
      for (final it in items) {
        await txn.insert('purchase_items', {
          'purchase_id': id,
          'product_sku': it['product_sku'],
          'product_name': it['product_name'],
          'quantity': it['quantity'],
          'unit_cost': it['unit_cost'],
        });
        // Suma stock y actualiza último costo/fecha
        await txn.rawUpdate(
          'UPDATE products SET stock = stock + ?, last_purchase_price = ?, last_purchase_date = ? WHERE sku = ?',
          [it['quantity'], it['unit_cost'], header['date'], it['product_sku']]
        );
      }
      return id;
    });
  }

  Future<List<Map<String,Object?>>> purchasesInRange(String fromIso, String toIso) async {
    final db = await _db;
    return db.query('purchases',
        where: 'date BETWEEN ? AND ?',
        whereArgs: [fromIso, toIso],
        orderBy: 'date DESC');
  }

  Future<List<Map<String,Object?>>> purchaseItems(int id) async {
    final db = await _db;
    return db.query('purchase_items', where: 'purchase_id=?', whereArgs: [id]);
  }
}