import 'package:sqflite/sqflite.dart';
import '../data/database_provider.dart';

class ProductRepository {
  Future<Database> get _db async => DatabaseProvider.instance.database;

  Future<List<Map<String, Object?>>> all() async {
    final db = await _db;
    return db.query('products', orderBy: 'name ASC');
    }

  Future<Map<String, Object?>?> findBySku(String sku) async {
    final db = await _db;
    final r = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  Future<List<Map<String, Object?>>> searchLite(String q) async {
    final db = await _db;
    final like = '%${q.trim()}%';
    return db.query('products',
        columns: ['sku','name','category','default_sale_price','stock'],
        where: 'sku LIKE ? OR name LIKE ?',
        whereArgs: [like, like],
        limit: 20,
        orderBy: 'name ASC');
  }

  Future<int> insert(Map<String, Object?> data) async {
    final db = await _db;
    return db.insert('products', data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateBySku(String sku, Map<String, Object?> data) async {
    final db = await _db;
    return db.update('products', data, where: 'sku = ?', whereArgs: [sku]);
  }

  Future<int> deleteBySku(String sku) async {
    final db = await _db;
    return db.delete('products', where: 'sku = ?', whereArgs: [sku]);
  }

  Future<void> adjustStock(String sku, double delta) async {
    final db = await _db;
    await db.rawUpdate('UPDATE products SET stock = COALESCE(stock,0) + ? WHERE sku = ?', [delta, sku]);
  }
}