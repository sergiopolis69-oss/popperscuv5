import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

class ClientRepository {
  final _dbF = DatabaseHelper.instance;

  Future<void> upsert(String phone, String name, String address) async {
    final db = await _dbF.db;
    await db.insert('customers', {
      'phone': phone, 'name': name, 'address': address
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> count() async {
    final db = await _dbF.db;
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM customers');
    return (r.first['c'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> topClients({int limit = 10}) async {
    final db = await _dbF.db;
    final r = await db.rawQuery('''
      SELECT c.phone, c.name, COALESCE(SUM(si.quantity*si.unit_price),0) AS total
      FROM customers c
      LEFT JOIN sales s ON s.customer_phone = c.phone
      LEFT JOIN sale_items si ON si.sale_id = s.id
      GROUP BY c.phone
      ORDER BY total DESC
      LIMIT ?
    ''', [limit]);
    return r;
  }

  Future<List<Map<String, dynamic>>> search(String q) async {
    final db = await _dbF.db;
    return db.query('customers',
      where: 'name LIKE ? OR phone LIKE ?',
      whereArgs: ['%'+q+'%','%'+q+'%'],
      orderBy: 'name ASC',
      limit: 50);
  }

  Future<List<Map<String, dynamic>>> all() async {
    final db = await _dbF.db;
    return db.query('customers', orderBy: 'name ASC', limit: 200);
  }
}
