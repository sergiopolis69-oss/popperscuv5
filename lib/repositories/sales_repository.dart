import 'package:sqflite/sqflite.dart';
import '../data/database.dart';
import '../models/sale.dart';

class SalesRepository {
  final _dbF = DatabaseHelper.instance;

  Future<int> createSale(Sale s) async {
    final db = await _dbF.db;
    return await db.transaction<int>((txn) async {
      final id = await txn.insert('sales', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      for (final it in s.items) {
        await txn.insert('sale_items', it.toMap(id));
        final prod = await txn.query('products', where: 'id=?', whereArgs: [it.productId], limit: 1);
        final curr = (prod.isNotEmpty ? (prod.first['stock'] as int? ?? 0) : 0);
        await txn.update('products', {'stock': curr - it.quantity}, where: 'id=?', whereArgs: [it.productId]);
      }
      return id;
    });
  }

  Future<List<Map<String, dynamic>>> salesBetween(DateTime from, DateTime to) async {
    final db = await _dbF.db;
    return db.query('sales',
      where: 'date >= ? AND date <= ?',
      whereArgs: [from.toIso8601String(), to.toIso8601String()],
      orderBy: 'date DESC');
  }
}
