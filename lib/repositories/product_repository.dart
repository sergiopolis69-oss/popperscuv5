import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

class ProductRepository {
  Future<Database> get _db async => DatabaseHelper.instance.db;

  Future<List<Map<String, dynamic>>> all({String? category}) async {
    final db = await _db;
    if (category == null || category.isEmpty) {
      return db.query('products', orderBy: 'name ASC');
    } else {
      return db.query('products', where: 'category = ?', whereArgs: [category], orderBy: 'name ASC');
    }
  }

  Future<Map<String, dynamic>?> findBySku(String sku) async {
    final db = await _db;
    final r = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  Future<List<Map<String, dynamic>>> searchLite(String q, {int limit = 20}) async {
    final db = await _db;
    final like = '%$q%';
    return db.query(
      'products',
      where: 'sku LIKE ? OR name LIKE ?',
      whereArgs: [like, like],
      orderBy: 'name ASC',
      limit: limit,
    );
  }

  Future<int> insert(Map<String, dynamic> data) async {
    final db = await _db;
    return db.insert('products', data, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<int> upsertBySku(String sku, Map<String, dynamic> data) async {
    final db = await _db;
    final exists = await findBySku(sku);
    if (exists == null) {
      return db.insert('products', data, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      return db.update('products', data, where: 'sku = ?', whereArgs: [sku], conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<int> updateBySku(String sku, Map<String, dynamic> data) async {
    final db = await _db;
    return db.update('products', data, where: 'sku = ?', whereArgs: [sku], conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> deleteBySku(String sku) async {
    final db = await _db;
    return db.delete('products', where: 'sku = ?', whereArgs: [sku]);
  }

  Future<List<String>> categories() async {
    final db = await _db;
    final rows = await db.rawQuery('SELECT DISTINCT COALESCE(category, "") AS category FROM products ORDER BY category');
    return rows.map((e) => (e['category'] as String?) ?? '').where((e) => e.isNotEmpty).toList();
  }
}