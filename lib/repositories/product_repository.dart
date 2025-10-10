import 'package:sqflite/sqflite.dart';
import '../data/db.dart';

class ProductRepository {
  Future<Database> get _db async => openAppDb();

  Future<List<Map<String, Object?>>> searchLite(String q, {int limit = 20}) async {
    final db = await _db;
    final qq = '%${q.trim()}%';
    return db.query(
      'products',
      columns: ['sku','name','category','default_sale_price','stock'],
      where: 'sku LIKE ? OR name LIKE ? OR category LIKE ?',
      whereArgs: [qq, qq, qq],
      orderBy: 'name',
      limit: limit,
    );
  }

  Future<Map<String, Object?>?> findBySku(String sku) async {
    final db = await _db;
    final rows = await db.query('products', where: 'sku=?', whereArgs: [sku], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsert(Map<String, Object?> data) async {
    final db = await _db;
    await db.insert('products', data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> all({String? category}) async {
    final db = await _db;
    if (category == null || category.isEmpty) {
      return db.query('products', orderBy: 'name');
    }
    return db.query('products', where: 'category=?', whereArgs: [category], orderBy: 'name');
  }

  Future<void> deleteBySku(String sku) async {
    final db = await _db;
    await db.delete('products', where: 'sku=?', whereArgs: [sku]);
  }

  Future<void> addStock(String sku, num qty, {num? lastCost, String? lastDate}) async {
    final db = await _db;
    await db.transaction((txn) async {
      final r = await txn.query('products', where: 'sku=?', whereArgs: [sku], limit: 1);
      if (r.isEmpty) return;
      final cur = (r.first['stock'] as num? ?? 0).toDouble();
      await txn.update('products', {
        'stock': cur + qty,
        if (lastCost != null) 'last_purchase_price': lastCost,
        if (lastDate != null) 'last_purchase_date': lastDate,
      }, where: 'sku=?', whereArgs: [sku]);
    });
  }

  Future<void> removeStock(String sku, num qty) async {
    final db = await _db;
    await db.transaction((txn) async {
      final r = await txn.query('products', where: 'sku=?', whereArgs: [sku], limit: 1);
      if (r.isEmpty) return;
      final cur = (r.first['stock'] as num? ?? 0).toDouble();
      await txn.update('products', {'stock': cur - qty}, where: 'sku=?', whereArgs: [sku]);
    });
  }
}