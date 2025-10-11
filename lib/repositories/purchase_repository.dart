import 'package:sqflite/sqflite.dart';
import '../data/db.dart';
import 'product_repository.dart';

class PurchaseRepository {
  Future<Database> get _db async => openAppDb();
  final _prodRepo = ProductRepository();

  Future<List<Map<String, Object?>>> all() async {
    final db = await _db;
    return db.query('purchases', orderBy: 'date DESC');
  }

  Future<List<Map<String, Object?>>> itemsByPurchaseId(dynamic id) async {
    final db = await _db;
    return db.query(
      'purchase_items',
      where: 'purchase_id = ?',
      whereArgs: [id],
      orderBy: 'rowid ASC',
    );
  }

  Future<int> upsert(Map<String, Object?> data) async {
    final db = await _db;
    return await db.insert(
      'purchases',
      {
        'id': data['id'],
        'folio': data['folio'],
        'date': data['date'],
        'supplier_id': data['supplier_id'],
        'total': data['total'] ?? 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertItem(Map<String, Object?> data) async {
    final db = await _db;
    await db.insert(
      'purchase_items',
      {
        'purchase_id': data['purchase_id'],
        'product_sku': data['product_sku'],
        'product_name': data['product_name'] ?? '',
        'quantity': data['quantity'] ?? 0,
        'unit_cost': data['unit_cost'] ?? 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Efecto de inventario y último costo
    final sku = data['product_sku'] as String;
    final qty = (data['quantity'] as num?) ?? 0;
    final cost = (data['unit_cost'] as num?) ?? 0;
    final date = (data['purchase_date'] as String?) ?? (data['date'] as String?) ?? DateTime.now().toIso8601String();

    if (qty > 0) {
      await _prodRepo.increaseStock(sku, qty);
    }
    await _prodRepo.updateLastPurchase(sku, cost, date);
  }
}