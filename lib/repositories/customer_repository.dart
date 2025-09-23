
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';
import '../models/customer.dart';

class CustomerRepository {
  Future<int> upsert(Customer c) async {
    final db = await AppDatabase().db();
    return db.insert('customers', c.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Customer>> search(String q) async {
    final db = await AppDatabase().db();
    final res = await db.query('customers',
      where: 'name LIKE ? OR phone LIKE ?',
      whereArgs: ['%$q%', '%$q%'],
      orderBy: 'name ASC');
    return res.map(Customer.fromMap).toList();
  }

  Future<Customer?> findByPhone(String phone) async {
    final db = await AppDatabase().db();
    final res = await db.query('customers', where: 'phone=?', whereArgs: [phone]);
    if (res.isEmpty) return null;
    return Customer.fromMap(res.first);
  }

  Future<int> count() async {
    final db = await AppDatabase().db();
    final res = await db.rawQuery('SELECT COUNT(*) as c FROM customers');
    return (res.first['c'] as int);
  }

  Future<List<Map<String, Object?>>> topCustomers({int limit=10}) async {
    final db = await AppDatabase().db();
    final res = await db.rawQuery('''
      SELECT c.phone, c.name, COUNT(s.id) as salesCount
      FROM customers c
      LEFT JOIN sales s ON s.customerPhone=c.phone
      GROUP BY c.phone, c.name
      ORDER BY salesCount DESC
      LIMIT ?;
    ''', [limit]);
    return res;
  }
}
