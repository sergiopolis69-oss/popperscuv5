import 'package:sqflite/sqflite.dart';
import '../data/db.dart';

class ProductRepository {
  Future<Database> get _db async => openAppDb();

  Future<List<Map<String, Object?>>> all() async {
    final db = await _db;
    return db.query('products', orderBy: 'name COLLATE NOCASE');
  }

  /// Búsqueda ligera por nombre, sku o categoría.
  Future<List<Map<String, Object?>>> searchLite(String q, {int limit = 25}) async {
    final db = await _db;
    final like = '%$q%';
    return db.query(
      'products',
      columns: [
        'sku','name','category',
        'default_sale_price','last_purchase_price','last_purchase_date','stock'
      ],
      where: 'name LIKE ? OR sku LIKE ? OR category LIKE ?',
      whereArgs: [like, like, like],
      orderBy: 'name COLLATE NOCASE',
      limit: limit,
    );
  }

  Future<Map<String, Object?>?> findBySku(String sku) async {
    final db = await _db;
    final r = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  /// Inserta/actualiza (PK = sku).
  Future<void> upsert(Map<String, Object?> data) async {
    final db = await _db;
    await db.insert(
      'products',
      {
        'sku': data['sku'],
        'name': data['name'] ?? '',
        'category': data['category'] ?? '',
        'default_sale_price': data['default_sale_price'] ?? 0,
        'last_purchase_price': data['last_purchase_price'] ?? 0,
        'last_purchase_date': data['last_purchase_date'],
        'stock': data['stock'] ?? 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> increaseStock(String sku, num qty) async {
    final db = await _db;
    await db.rawUpdate(
      'UPDATE products SET stock = COALESCE(stock,0) + ? WHERE sku = ?',
      [qty, sku],
    );
  }

  Future<void> decreaseStock(String sku, num qty) async {
    final db = await _db;
    await db.rawUpdate(
      'UPDATE products SET stock = MAX(0, COALESCE(stock,0) - ?) WHERE sku = ?',
      [qty, sku],
    );
  }

  Future<void> updateLastPurchase(String sku, num price, String isoDate) async {
    final db = await _db;
    await db.update(
      'products',
      {'last_purchase_price': price, 'last_purchase_date': isoDate},
      where: 'sku = ?',
      whereArgs: [sku],
    );
  }
}
