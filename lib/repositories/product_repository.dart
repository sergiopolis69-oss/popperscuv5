import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

class ProductRepository {
  Future<Database> get _db async => DatabaseHelper.instance.db;

  Future<List<Map<String, dynamic>>> all({int limit = 200, int offset = 0}) async {
    final db = await _db;
    return db.query('products', orderBy: 'name COLLATE NOCASE ASC', limit: limit, offset: offset);
  }

  Future<int> insert(Map<String, Object?> data) async {
    final db = await _db;
    return db.insert('products', data);
  }

  Future<List<Map<String, dynamic>>> searchLite(String query, {int limit = 25}) async {
    final db = await _db;
    final q = '%${query.trim()}%';
    return db.query(
      'products',
      columns: [
        'id','sku','name','category','stock','last_purchase_price','default_sale_price',
      ],
      where: 'name LIKE ? OR category LIKE ? OR IFNULL(sku, "") LIKE ?',
      whereArgs: [q, q, q],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> searchByNameOrSku(String query, {int limit = 25}) =>
      searchLite(query, limit: limit);

  Future<Map<String, dynamic>?> findBySku(String sku) async {
    final db = await _db;
    final rows = await db.query('products', where: 'sku = ?', whereArgs: [sku.trim()], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final db = await _db;
    final rows = await db.query('products', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<int> upsert({
    int? id,
    String? sku,
    required String name,
    String? category,
    int stock = 0,
    double defaultSalePrice = 0.0,
    double initialCost = 0.0,
    double? lastPurchasePrice,
    DateTime? lastPurchaseDate,
  }) async {
    final db = await _db;
    final data = <String, Object?>{
      'sku': sku?.trim(),
      'name': name.trim(),
      'category': (category ?? '').trim(),
      'stock': stock,
      'default_sale_price': defaultSalePrice,
      'initial_cost': initialCost,
      if (lastPurchasePrice != null) 'last_purchase_price': lastPurchasePrice,
      if (lastPurchaseDate != null) 'last_purchase_date': lastPurchaseDate.toIso8601String(),
    };

    if (id == null) {
      return await db.insert('products', data);
    } else {
      await db.update('products', data, where: 'id = ?', whereArgs: [id]);
      return id;
    }
  }

  Future<void> applyPurchase({
    required int productId,
    required int quantity,
    required double unitCost,
    DateTime? date,
  }) async {
    final db = await _db;
    final now = (date ?? DateTime.now()).toIso8601String();
    await db.rawUpdate(
      'UPDATE products SET stock = stock + ?, last_purchase_price = ?, last_purchase_date = ? WHERE id = ?',
      [quantity, unitCost, now, productId],
    );
  }

  Future<void> applySale({required int productId, required int quantity}) async {
    final db = await _db;
    await db.rawUpdate('UPDATE products SET stock = stock - ? WHERE id = ?', [quantity, productId]);
  }

  Future<List<Map<String, dynamic>>> list({int limit = 200, int offset = 0}) => all(limit: limit, offset: offset);

  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  /// Lista de categorías (DISTINCT, sin vacíos), ordenadas alfabéticamente.
  Future<List<String>> categories() async {
    final db = await _db;
    final rows = await db.rawQuery("SELECT DISTINCT category FROM products WHERE IFNULL(category,'') <> '' ORDER BY category COLLATE NOCASE ASC");
    return rows.map((r) => (r['category'] as String?)?.trim() ?? '').where((s) => s.isNotEmpty).toList();
  }
}
