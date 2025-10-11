import 'package:sqflite/sqflite.dart';
import '../data/db.dart';

class CustomerRepository {
  Future<Database> get _db async => openAppDb();

  Future<List<Map<String, Object?>>> all() async {
    final db = await _db;
    return db.query('customers', orderBy: 'name COLLATE NOCASE');
  }

  Future<List<Map<String, Object?>>> searchLite(String q) async {
    final db = await _db;
    final like = '%$q%';
    return db.query(
      'customers',
      columns: ['phone', 'name', 'address'],
      where: 'name LIKE ? OR phone LIKE ?',
      whereArgs: [like, like],
      orderBy: 'name COLLATE NOCASE',
      limit: 25,
    );
  }

  Future<void> upsert(Map<String, Object?> data) async {
    final db = await _db;
    await db.insert(
      'customers',
      {
        'phone': data['phone'],
        'name': data['name'] ?? '',
        'address': data['address'] ?? '',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}