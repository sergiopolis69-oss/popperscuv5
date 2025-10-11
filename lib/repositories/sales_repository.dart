import 'package:sqflite/sqflite.dart';
import '../data/db.dart';

class SalesRepository {
  Future<Database> get _db async => openAppDb();

  Future<List<Map<String, Object?>>> all() async {
    final db = await _db;
    return db.query('sales', orderBy: 'date DESC');
  }

  Future<List<Map<String, Object?>>> itemsBySaleId(Object id) async {
    final db = await _db;
    return db.query(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: [id],
      orderBy: 'rowid ASC',
    );
  }

  /// Inserta/actualiza venta (PK autoincrement o provisto en data['id'])
  Future<int> upsert(Map<String, Object?> data) async {
    final db = await _db;
    return await db.insert(
      'sales',
      {
        'id': data['id'], // puede ser null => autoincrement
        'date': data['date'], // ISO
        'customer_phone': data['customer_phone'],
        'payment_method': data['payment_method'],
        'place': data['place'],
        'shipping_cost': data['shipping_cost'] ?? 0,
        'discount': data['discount'] ?? 0,
        'total': data['total'] ?? 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertItem(Map<String, Object?> data) async {
    final db = await _db;
    await db.insert(
      'sale_items',
      {
        'sale_id': data['sale_id'],
        'product_sku': data['product_sku'],
        'product_name': data['product_name'] ?? '',
        'quantity': data['quantity'] ?? 0,
        'unit_price': data['unit_price'] ?? 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
