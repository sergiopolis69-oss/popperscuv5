import 'package:sqflite/sqflite.dart';
import '../data/database_provider.dart';

class SupplierRepository {
  Future<Database> get _db async => DatabaseProvider.instance.database;

  Future<List<Map<String, Object?>>> search(String q) async {
    final db = await _db;
    final like = '%${q.trim()}%';
    return db.query('suppliers',
        where: 'phone LIKE ? OR name LIKE ?',
        whereArgs: [like, like],
        limit: 20,
        orderBy: 'name ASC');
  }

  Future<int> upsert(String phone, String name, String? address) async {
    final db = await _db;
    return db.insert('suppliers', {
      'phone': phone,
      'name': name,
      'address': address,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}