import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

class Supplier {
  final int? id;
  final String name;
  final String phone;
  final String address;

  Supplier({
    this.id,
    required this.name,
    required this.phone,
    required this.address,
  });
}

class SupplierRepository {
  Future<Database> get _db async => DatabaseHelper.instance.db;

  Future<List<Supplier>> searchByNameOrPhone(String q, {int limit = 20}) async {
    final db = await _db;
    final rows = await db.query(
      'suppliers',
      where: 'name LIKE ? OR phone LIKE ?',
      whereArgs: ['%$q%', '%$q%'],
      orderBy: 'name ASC',
      limit: limit,
    );
    return rows.map((r) => Supplier(
      id: r['id'] as int?,
      name: (r['name'] ?? '') as String,
      phone: (r['phone'] ?? '') as String,
      address: (r['address'] ?? '') as String,
    )).toList();
  }

  Future<int> upsertByPhone({
    required String phone,
    required String name,
    String address = '',
  }) async {
    final db = await _db;
    final existing = await db.query('suppliers', where: 'phone = ?', whereArgs: [phone], limit: 1);
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      await db.update('suppliers', {'name': name, 'address': address}, where: 'id=?', whereArgs: [id]);
      return id;
    }
    return await db.insert('suppliers', {'name': name, 'phone': phone, 'address': address});
  }

  Future<List<Supplier>> all({int limit = 100, int offset = 0}) async {
    final db = await _db;
    final rows = await db.query('suppliers', orderBy: 'name ASC', limit: limit, offset: offset);
    return rows.map((r) => Supplier(
      id: r['id'] as int?,
      name: (r['name'] ?? '') as String,
      phone: (r['phone'] ?? '') as String,
      address: (r['address'] ?? '') as String,
    )).toList();
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('suppliers', where: 'id=?', whereArgs: [id]);
  }
}
