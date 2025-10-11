import 'package:sqflite/sqflite.dart';
import '../data/database_provider.dart';

class SaleRepository {
  Future<Database> get _db async => DatabaseProvider.instance.database;

  Future<int> create({
    required String dateIso,
    String? customerPhone,
    required String paymentMethod,
    String? place,
    double shipping = 0,
    double discount = 0,
    required List<Map<String, Object?>> items, // {sku, name, qty, price}
  }) async {
    final db = await _db;
    return await db.transaction<int>((txn) async {
      final saleId = await txn.insert('sales', {
        'date': dateIso,
        'customer_phone': customerPhone,
        'payment_method': paymentMethod,
        'place': place,
        'shipping_cost': shipping,
        'discount': discount,
      });

      double totalQty = 0;
      for (final it in items) {
        final sku = it['sku'] as String;
        final name = it['name'] as String;
        final qty  = (it['qty'] as num).toDouble();
        final price= (it['price'] as num).toDouble();
        totalQty += qty;

        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_sku': sku,
          'product_name': name,
          'quantity': qty,
          'unit_price': price,
        });

        // disminuir stock
        await txn.rawUpdate('UPDATE products SET stock = COALESCE(stock,0) - ? WHERE sku = ?', [qty, sku]);
      }

      return saleId;
    });
  }

  Future<List<Map<String, Object?>>> history({
    String? customerPhoneOrNameLike,
    String? paymentMethod,
    String? productSkuOrNameLike,
    String? dateFromIso,
    String? dateToIso,
  }) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];

    if (customerPhoneOrNameLike != null && customerPhoneOrNameLike.trim().isNotEmpty) {
      where.add('(s.customer_phone LIKE ? OR c.name LIKE ?)');
      final like = '%${customerPhoneOrNameLike.trim()}%';
      args..add(like)..add(like);
    }
    if (paymentMethod != null && paymentMethod.trim().isNotEmpty) {
      where.add('s.payment_method = ?');
      args.add(paymentMethod);
    }
    if (productSkuOrNameLike != null && productSkuOrNameLike.trim().isNotEmpty) {
      where.add('EXISTS(SELECT 1 FROM sale_items si WHERE si.sale_id = s.id AND (si.product_sku LIKE ? OR si.product_name LIKE ?))');
      final like = '%${productSkuOrNameLike.trim()}%';
      args..add(like)..add(like);
    }
    if (dateFromIso != null) { where.add('s.date >= ?'); args.add(dateFromIso); }
    if (dateToIso != null)   { where.add('s.date <= ?'); args.add(dateToIso); }

    final sql = '''
      SELECT s.*, c.name AS customer_name,
        (SELECT SUM(quantity * unit_price) FROM sale_items WHERE sale_id = s.id) AS subtotal_items
      FROM sales s
      LEFT JOIN customers c ON c.phone = s.customer_phone
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY s.date DESC, s.id DESC
      LIMIT 500
    ''';
    return db.rawQuery(sql, args);
  }

  Future<List<Map<String, Object?>>> itemsOf(int saleId) async {
    final db = await _db;
    return db.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId], orderBy: 'id ASC');
  }
}