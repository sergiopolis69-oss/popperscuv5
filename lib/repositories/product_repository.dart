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

  /// Versión "lite" (alias) que usa menos columnas si quieres resultados rápidos.
  Future<List<Map<String, dynamic>>> searchLite(String query, {int limit = 30}) async {
    final db = await DatabaseHelper.instance.db;
    final like = '%${query.trim()}%';
    return db.query(
      'products',
      columns: ['id','name','sku','stock','default_sale_price'],
      where: 'name LIKE ? OR IFNULL(sku,"") LIKE ? OR IFNULL(category,"") LIKE ?',
      whereArgs: [like, like, like],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
    );
  }

  Future<Map<String, dynamic>?> findBySku(String sku) async {
    final db = await DatabaseHelper.instance.db;
    final rows = await db.query(
      'products',
      where: 'sku = ?',
      whereArgs: [sku.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final db = await DatabaseHelper.instance.db;
    final rows = await db.query('products', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first;
  }
}
