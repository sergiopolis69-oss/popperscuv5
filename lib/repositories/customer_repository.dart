import 'package:sqflite/sqflite.dart';
import '../data/database_provider.dart';

class CustomerRepository {
  Future<Database> get _db async => DatabaseProvider.instance.database;

  Future<int> count() async {
    final db = await _db;
    final r = await db.rawQuery('SELECT COUNT(*) c FROM customers');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<List<Map<String, Object?>>> top(int limit) async {
    final db = await _db;
    return db.rawQuery('''
      SELECT c.phone, c.name, COUNT(s.id) as sales
      FROM customers c
      LEFT JOIN sales s ON s.customer_phone = c.phone
      GROUP BY c.phone, c.name
      ORDER BY sales DESC, c.name ASC
      LIMIT ?
    ''', [limit]);
  }

  Future<List<Map<String, Object?>>> search(String q) async {
    final db = await _db;
    final like = '%${q.trim()}%';
    return db.query('customers',
        where: 'phone LIKE ? OR name LIKE ?',
        whereArgs: [like, like],
        limit: 20,
        orderBy: 'name ASC');
  }

  Future<int> upsert(String phone, String name, String? address) async {
    final db = await _db;
    return db.insert('customers', {
      'phone': phone,
      'name': name,
      'address': address,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}