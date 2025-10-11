import 'package:sqflite/sqflite.dart';
import '../data/db.dart';

class SupplierRepository {
  Future<Database> get _db async => openAppDb();

  Future<List<Map<String, Object?>>> all() async {
    final db = await _db;
    return db.query('suppliers', orderBy: 'name COLLATE NOCASE');
  }

  Future<List<Map<String, Object?>>> searchLite(String q) async {
    final db = await _db;
    final like = '%$q%';
    return db.query(
      'suppliers',
      columns: ['id', 'name', 'phone', 'address'],
      where: 'name LIKE ? OR phone LIKE ?',
      whereArgs: [like, like],
      orderBy: 'name COLLATE NOCASE',
      limit: 25,
    );
  }

  /// Inserta/actualiza proveedor. PK (id) = phone (igual que clientes).
  Future<void> upsert(Map<String, Object?> data) async {
    final db = await _db;
    await db.insert(
      'suppliers',
      {
        'id': data['id'] ?? data['phone'], // tolerante
        'name': data['name'] ?? '',
        'phone': data['phone'] ?? '',
        'address': data['address'] ?? '',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
