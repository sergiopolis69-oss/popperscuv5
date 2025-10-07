import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

class Supplier {
  final int? id;
  final String name;
  final String phone;
  final String address;
  Supplier({this.id, required this.name, required this.phone, required this.address});
}

class SupplierRepository {
  final _dbF = DatabaseHelper.instance;

  Future<List<Supplier>> searchByNameOrPhone(String q, {int limit = 20}) async {
    final db = await _dbF.db;
    final rows = await db.query(
      'suppliers',
      where: 'name LIKE ? OR phone LIKE ?',
      whereArgs: ['%$q%','%$q%'],
      orderBy: 'name ASC',
      limit: limit,
    );
    return rows.map((r)=>Supplier(
      id: r['id'] as int?,
      name: (r['name'] ?? '') as String,
      phone: (r['phone'] ?? '') as String,
      address: (r['address'] ?? '') as String,
    )).toList();
  }

  Future<int> upsertByPhone({required String phone, required String name, String address = ''}) async {
    final db = await _dbF.db;
    final existing = await db.query('suppliers', where: 'phone = ?', whereArgs: [phone], limit: 1);
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      await db.update('suppliers', {'name': name, 'address': address}, where: 'id=?', whereArgs: [id]);
      return id;
    }
    return await db.insert('suppliers', {'name': name, 'phone': phone, 'address': address});
  }

  Future<Supplier?> getById(int id) async {
    final db = await _dbF.db;
    final r = await db.query('suppliers', where: 'id=?', whereArgs: [id], limit: 1);
    if (r.isEmpty) return null;
    final x = r.first;
    return Supplier(
      id: x['id'] as int?,
      name: (x['name'] ?? '') as String,
      phone: (x['phone'] ?? '') as String,
      address: (x['address'] ?? '') as String,
    );
  }
}