import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

class ProductRepository {
  final _dbF = DatabaseHelper.instance;

  Future<Map<String, dynamic>?> findBySku(String sku) async {
    final db = await _dbF.db;
    final r = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  Future<Map<String, dynamic>?> findById(int id) async {
    final db = await _dbF.db;
    final r = await db.query('products', where: 'id = ?', whereArgs: [id], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  Future<List<Map<String, dynamic>>> searchLite(String q, {int limit = 20}) async {
    final db = await _dbF.db;
    final r = await db.query(
      'products',
      columns: ['id','name','last_purchase_price','default_sale_price'],
      where: 'name LIKE ? OR category LIKE ? OR sku LIKE ?',
      whereArgs: ['%$q%','%$q%','%$q%'],
      orderBy: 'name ASC',
      limit: limit,
    );
    return r;
  }

  Future<int> insert(Map<String, dynamic> map) async {
    final db = await _dbF.db;
    return db.insert('products', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> all() async {
    final db = await _dbF.db;
    return db.query('products', orderBy: 'name ASC');
  }

  Future<void> delete(int id) async {
    final db = await _dbF.db;
    await db.delete('products', where: 'id=?', whereArgs: [id]);
  }
}