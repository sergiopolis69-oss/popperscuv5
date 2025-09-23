
import '../data/database.dart';

class ProfitRepository {
  Future<double> weightedProfitPercent({
    required String from,
    required String to,
    String? customerPhone,
    String? category,
  }) async {
    final db = await AppDatabase().db();
    final where = <String>[];
    final args = <Object?>[from, to];
    where.add('date(s.datetime) BETWEEN date(?) AND date(?)');
    if (customerPhone != null && customerPhone.isNotEmpty){
      where.add('s.customerPhone=?'); args.add(customerPhone);
    }
    if (category != null && category.isNotEmpty){
      where.add('p.category=?'); args.add(category);
    }

    final rows = await db.rawQuery('''
      SELECT s.id as saleId, s.discount, SUM(si.quantity*si.unitPrice) as subtotal
      FROM sales s
      JOIN sale_items si ON si.saleId=s.id
      JOIN products p ON p.id=si.productId
      WHERE ${where.join(' AND ')}
      GROUP BY s.id;
    ''', args);

    if (rows.isEmpty) return 0.0;

    double totalRevenue = 0.0;
    double totalCost = 0.0;

    for (final r in rows) {
      final saleId = r['saleId'] as int;
      final subtotal = (r['subtotal'] as num).toDouble();
      final discount = (r['discount'] as num).toDouble();
      final discountFactor = (subtotal <= 0) ? 0.0 : discount / subtotal;

      final items = await db.rawQuery('''
        SELECT si.quantity, si.unitPrice, p.lastPurchasePrice
        FROM sale_items si
        JOIN products p ON p.id=si.productId
        WHERE si.saleId=?;
      ''', [saleId]);

      for (final it in items) {
        final qty = (it['quantity'] as num).toInt();
        final price = (it['unitPrice'] as num).toDouble();
        final cost = (it['lastPurchasePrice'] as num).toDouble();
        final lineRevenue = qty * price * (1 - discountFactor);
        final lineCost = qty * cost;
        totalRevenue += lineRevenue;
        totalCost += lineCost;
      }
    }

    if (totalRevenue <= 0) return 0.0;
    final profit = totalRevenue - totalCost;
    return (profit / totalRevenue) * 100.0;
  }

  Future<List<Map<String, Object?>>> dailySales(String from, String to) async {
    final db = await AppDatabase().db();
    return await db.rawQuery('''
      SELECT strftime('%Y-%m-%d', s.datetime) as day,
             SUM(si.quantity*si.unitPrice) as revenue
      FROM sales s
      JOIN sale_items si ON si.saleId=s.id
      WHERE date(s.datetime) BETWEEN date(?) AND date(?)
      GROUP BY day
      ORDER BY day ASC;
    ''', [from, to]);
  }

  Future<List<Map<String, Object?>>> dailyProfitPercent(String from, String to) async {
    final db = await AppDatabase().db();
    final sales = await db.rawQuery('''
      SELECT s.id as saleId, strftime('%Y-%m-%d', s.datetime) as day,
             s.discount as discount,
             SUM(si.quantity*si.unitPrice) as subtotal
      FROM sales s
      JOIN sale_items si ON si.saleId=s.id
      WHERE date(s.datetime) BETWEEN date(?) AND date(?)
      GROUP BY s.id
      ORDER BY s.datetime ASC;
    ''', [from, to]);

    final Map<String, List<Map<String, Object?>>> byDay = {};
    for (final row in sales){
      final day = row['day'] as String;
      (byDay[day] ??= []).add(row);
    }

    final result = <Map<String, Object?>>[];
    for (final entry in byDay.entries){
      double revenue = 0.0;
      double cost = 0.0;
      for (final r in entry.value){
        final saleId = r['saleId'] as int;
        final subtotal = (r['subtotal'] as num).toDouble();
        final discount = (r['discount'] as num).toDouble();
        final discountFactor = (subtotal <= 0) ? 0.0 : discount / subtotal;

        final items = await db.rawQuery('''
          SELECT si.quantity, si.unitPrice, p.lastPurchasePrice
          FROM sale_items si
          JOIN products p ON p.id=si.productId
          WHERE si.saleId=?;
        ''', [saleId]);

        for (final it in items){
          final qty = (it['quantity'] as num).toInt();
          final price = (it['unitPrice'] as num).toDouble();
          final lc = (it['lastPurchasePrice'] as num).toDouble();
          final lineRevenue = qty * price * (1 - discountFactor);
          final lineCost = qty * lc;
          revenue += lineRevenue;
          cost += lineCost;
        }
      }
      final pct = revenue <= 0 ? 0.0 : ((revenue - cost) / revenue) * 100.0;
      result.add({'day': entry.key, 'pct': pct, 'revenue': revenue});
    }
    result.sort((a,b)=> (a['day'] as String).compareTo(b['day'] as String));
    return result;
  }
}
