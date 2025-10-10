import 'package:sqflite/sqflite.dart';
import '../data/db.dart';

class ProductRepository {
  Future<Database> get _db async => await openAppDb();

  Future<List<Map<String, Object?>>> all() async {
    final db = await _db;
    return db.query('products', orderBy: 'name ASC');
  }

  Future<Map<String, Object?>?> findBySku(String sku) async {
    final db = await _db;
    final r = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
    if (r.isEmpty) return null;
    return r.first;
  }

  Future<List<Map<String, Object?>>> searchLite(String q, {int limit = 20}) async {
    final db = await _db;
    final like = '%$q%';
    return db.query(
      'products',
      columns: ['sku', 'name', 'default_sale_price', 'last_purchase_price', 'category', 'stock'],
      where: 'sku LIKE ? OR name LIKE ? OR category LIKE ?',
      whereArgs: [like, like, like],
      orderBy: 'name ASC',
      limit: limit,
    );
  }

  Future<int> upsert(Map<String, Object?> data) async {
    final db = await _db;
    return db.insert('products', data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> deleteBySku(String sku) async {
    final db = await _db;
    return db.delete('products', where: 'sku = ?', whereArgs: [sku]);
  }

  Future<void> adjustStock(String sku, double delta) async {
    final db = await _db;
    await db.rawUpdate(
      'UPDATE products SET stock = COALESCE(stock,0) + ? WHERE sku = ?',
      [delta, sku],
    );
  }
}