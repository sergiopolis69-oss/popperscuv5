import 'package:sqflite/sqflite.dart';
import '../data/database.dart';
import '../models/supplier.dart';

class SupplierRepository {
  final _dbF = DatabaseHelper.instance;

  Future<int> insert(Supplier s) async {
    final db = await _dbF.db;
    return db.insert('suppliers', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Supplier>> searchByName(String q, {int limit = 20}) async {
    final db = await _dbF.db;
    final res = await db.query(
      'suppliers',
      where: 'name LIKE ?',
      whereArgs: ['%$q%'],
      limit: limit,
      orderBy: 'name ASC',
    );
    return res.map(Supplier.fromMap).toList();
  }

  Future<List<Supplier>> all({int limit = 100}) async {
    final db = await _dbF.db;
    final res = await db.query('suppliers', orderBy: 'name ASC', limit: limit);
    return res.map(Supplier.fromMap).toList();
  }
}
