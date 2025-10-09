import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

class ProductRepository {
  Future<List<Map<String, dynamic>>> searchByNameOrSku(String query, {int limit = 30}) async {
    final db = await DatabaseHelper.instance.db;
    final like = '%${query.trim()}%';
    return db.query(
      'products',
      columns: ['id','name','sku','category','default_sale_price','last_purchase_price','stock'],
      where: 'name LIKE ? OR category LIKE ? OR IFNULL(sku,"") LIKE ?',
      whereArgs: [like, like, like],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
    );
  }

  Future<Map<String, dynamic>?> getBySku(String sku) async {
    final db = await DatabaseHelper.instance.db;
    final rows = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  // Compatibilidad con compras_page.dart
  Future<Map<String, dynamic>?> findBySku(String sku) => getBySku(sku);

  Future<List<Map<String, dynamic>>> searchLite(String query, {int limit = 30}) async {
    final db = await DatabaseHelper.instance.db;
    final like = '%${query.trim()}%';
    return db.query(
      'products',
      columns: ['id','name','sku'],
      where: 'name LIKE ? OR IFNULL(sku,"") LIKE ? OR IFNULL(category,"") LIKE ?',
      whereArgs: [like, like, like],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
    );
  }
}
