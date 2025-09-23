
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';
import '../models/sale.dart';

class SaleRepository {
  Future<int> createSale(Sale s, List<SaleItem> items) async {
    final db = await AppDatabase().db();
    return await db.transaction<int>((txn) async {
      final saleId = await txn.insert('sales', s.toMap());
      for (final it in items) {
        await txn.insert('sale_items', {
          ...it.toMap(),
          'saleId': saleId,
        });
        // reducir inventario
        await txn.rawUpdate('UPDATE products SET stock = MAX(stock - ?, 0) WHERE id=?', [it.quantity, it.productId]);
      }
      return saleId;
    });
  }

  Future<List<Map<String, Object?>>> history({
    String? customerPhone,
    String? paymentMethod,
    String? productNameLike,
    String? fromDateInclusive,
    String? toDateInclusive,
  }) async {
    final db = await AppDatabase().db();
    final where = <String>[];
    final args = <Object?>[];
    if (customerPhone != null && customerPhone.isNotEmpty){ where.add('s.customerPhone=?'); args.add(customerPhone); }
    if (paymentMethod != null && paymentMethod.isNotEmpty){ where.add('s.paymentMethod=?'); args.add(paymentMethod); }
    if (productNameLike != null && productNameLike.isNotEmpty){
      where.add('p.name LIKE ?'); args.add('%$productNameLike%');
    }
    if (fromDateInclusive != null) { where.add('date(s.datetime) >= date(?)'); args.add(fromDateInclusive); }
    if (toDateInclusive != null) { where.add('date(s.datetime) <= date(?)'); args.add(toDateInclusive); }

    final res = await db.rawQuery('''
      SELECT s.id, s.datetime, s.customerPhone, s.paymentMethod, s.place, s.shippingCost, s.discount,
             SUM(si.quantity*si.unitPrice) as subtotal
      FROM sales s
      JOIN sale_items si ON si.saleId=s.id
      JOIN products p ON p.id=si.productId
      ${where.isEmpty ? '' : 'WHERE ' + where.join(' AND ')}
      GROUP BY s.id
      ORDER BY s.datetime DESC;
    ''', args);
    return res;
  }

  Future<List<Map<String, Object?>>> dailyHistogram(String from, String to) async {
    final db = await AppDatabase().db();
    final res = await db.rawQuery('''
      SELECT strftime('%Y-%m-%d', datetime) as day,
             SUM(si.quantity*si.unitPrice) as total
      FROM sales s
      JOIN sale_items si ON si.saleId=s.id
      WHERE date(s.datetime) BETWEEN date(?) AND date(?)
      GROUP BY day
      ORDER BY day ASC;
    ''', [from, to]);
    return res;
  }
}
