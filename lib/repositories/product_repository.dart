import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

class ProductRepository {
  Future<Map<String, dynamic>?> getBySku(String sku) async {
    final db = await DatabaseHelper.instance.db;
    final rows = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<bool> existsSku(String sku) async {
    final db = await DatabaseHelper.instance.db;
    final r = await db.rawQuery('SELECT 1 FROM products WHERE sku = ? LIMIT 1', [sku]);
    return r.isNotEmpty;
  }

  /// Inserta o actualiza por SKU (upsert). Valida que SKU no sea vacío.
  Future<int> upsertBySku(Map<String, dynamic> p) async {
    final db = await DatabaseHelper.instance.db;
    final sku = (p['sku'] ?? '').toString().trim();
    if (sku.isEmpty) {
      throw ArgumentError('SKU vacío');
    }
    // normaliza valores
    final row = {
      'sku': sku,
      'name': (p['name'] ?? '').toString().trim(),
      'category': (p['category'] ?? '').toString().trim(),
      'default_sale_price': (p['default_sale_price'] as num?)?.toDouble() ?? 0.0,
      'last_purchase_price': (p['last_purchase_price'] as num?)?.toDouble() ?? 0.0,
      'last_purchase_date': p['last_purchase_date'],
      'stock': (p['stock'] as num?)?.toInt() ?? 0,
    };
    final existing = await getBySku(sku);
    if (existing == null) {
      return await db.insert('products', row, conflictAlgorithm: ConflictAlgorithm.abort);
    } else {
      await db.update('products', row, where: 'sku = ?', whereArgs: [sku]);
      return existing['id'] as int;
    }
  }

  Future<List<Map<String, dynamic>>> searchByNameOrSku(String q, {int limit = 30}) async {
    final db = await DatabaseHelper.instance.db;
    final like = '%${q.trim()}%';
    return db.query(
      'products',
      columns: ['id','sku','name','category','default_sale_price','last_purchase_price','stock'],
      where: 'name LIKE ? OR IFNULL(category,"") LIKE ? OR IFNULL(sku,"") LIKE ?',
      whereArgs: [like, like, like],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
    );
  }

  /// Lista lite para autocompletes
  Future<List<Map<String, dynamic>>> searchLite(String q, {int limit = 25}) async {
    final db = await DatabaseHelper.instance.db;
    final like = '%${q.trim()}%';
    return db.query(
      'products',
      columns: ['id','sku','name'],
      where: 'name LIKE ? OR IFNULL(sku,"") LIKE ? OR IFNULL(category,"") LIKE ?',
      whereArgs: [like, like, like],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
    );
  }
}