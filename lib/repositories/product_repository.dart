import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

class ProductRepository {
  Future<Database> get _db async => DatabaseHelper.instance.db;

  Future<Map<String, dynamic>?> getBySku(String sku) async {
    final db = await _db;
    final r = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  Future<List<Map<String, dynamic>>> searchLite(String q, {int limit = 20}) async {
    final db = await _db;
    final like = '%$q%';
    return db.query(
      'products',
      columns: ['id', 'sku', 'name', 'default_sale_price', 'last_purchase_price', 'category', 'stock'],
      where: 'sku LIKE ? OR name LIKE ?',
      whereArgs: [like, like],
      limit: limit,
      orderBy: 'name COLLATE NOCASE',
    );
  }

  /// Inserta o actualiza por SKU. Exige SKU único/no vacío.
  Future<void> upsertBySku(Map<String, dynamic> data) async {
    final db = await _db;
    final sku = (data['sku'] ?? '').toString().trim();
    if (sku.isEmpty) throw 'SKU requerido';
    final updated = await db.update('products', data, where: 'sku = ?', whereArgs: [sku]);
    if (updated == 0) {
      await db.insert('products', data, conflictAlgorithm: ConflictAlgorithm.abort);
    }
  }
}