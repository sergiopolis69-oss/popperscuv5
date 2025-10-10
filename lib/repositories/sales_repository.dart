import 'package:sqflite/sqflite.dart';
import '../data/db.dart';

class SalesRepository {
  Future<Database> get _db async => openAppDb();

  Future<int> createSale(Map<String, Object?> sale, List<Map<String, Object?>> items) async {
    final db = await _db;
    return db.transaction<int>((txn) async {
      final saleId = await txn.insert('sales', sale);
      for (final it in items) {
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_sku': it['product_sku'],
          'product_name': it['product_name'],
          'quantity': it['quantity'],
          'unit_price': it['unit_price'],
        });
        // Descuenta stock
        await txn.rawUpdate(
          'UPDATE products SET stock = stock - ? WHERE sku = ?',
          [it['quantity'], it['product_sku']]
        );
      }
      return saleId;
    });
  }

  Future<List<Map<String,Object?>>> salesInRange(String fromIso, String toIso) async {
    final db = await _db;
    return db.query('sales',
        where: 'date BETWEEN ? AND ?',
        whereArgs: [fromIso, toIso],
        orderBy: 'date DESC');
  }

  Future<List<Map<String,Object?>>> saleItems(int saleId) async {
    final db = await _db;
    return db.query('sale_items', where: 'sale_id=?', whereArgs: [saleId]);
  }
}