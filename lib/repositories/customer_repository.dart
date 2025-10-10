import 'package:sqflite/sqflite.dart';
import '../data/db.dart';

class CustomerRepository {
  Future<Database> get _db async => await openAppDb();

  Future<List<Map<String, Object?>>> searchByPhoneOrName(String q, {int limit = 20}) async {
    final db = await _db;
    final like = '%$q%';
    return db.query(
      'customers',
      where: 'phone LIKE ? OR name LIKE ?',
      whereArgs: [like, like],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
    );
  }

  Future<int> insertQuick({required String phone, required String name, String? address}) async {
    final db = await _db;
    return db.insert('customers', {
      'phone': phone,
      'name': name,
      'address': address ?? '',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<Map<String, Object?>?> findByPhone(String phone) async {
    final db = await _db;
    final r = await db.query('customers', where: 'phone = ?', whereArgs: [phone], limit: 1);
    return r.isEmpty ? null : r.first;
  }
}