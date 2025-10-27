import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

class PurchaseSuggestion {
  PurchaseSuggestion({
    required this.productId,
    required this.sku,
    required this.name,
    required this.stock,
    required this.suggestedQuantity,
    required this.averageDailySales,
    required this.soldLastPeriod,
    required this.estimatedCost,
  });

  final int productId;
  final String sku;
  final String name;
  final int stock;
  final int suggestedQuantity;
  final double averageDailySales;
  final int soldLastPeriod;
  final double estimatedCost;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'sku': sku,
        'name': name,
        'stock': stock,
        'suggestedQuantity': suggestedQuantity,
        'averageDailySales': averageDailySales,
        'soldLastPeriod': soldLastPeriod,
        'estimatedCost': estimatedCost,
      };
}

Future<List<PurchaseSuggestion>> fetchPurchaseSuggestions(
  Database db, {
  DateTime? from,
  DateTime? to,
  int planningHorizonDays = 30,
  double safetyDays = 7,
}) async {
  final DateTime end = to ?? DateTime.now();
  final DateTime start = from ?? end.subtract(Duration(days: planningHorizonDays));
  final formatter = DateFormat('yyyy-MM-dd');
  final fromTxt = formatter.format(DateTime(start.year, start.month, start.day));
  final toTxt = formatter.format(DateTime(end.year, end.month, end.day));

  final rows = await db.rawQuery('''
    SELECT
      p.id,
      p.sku,
      p.name,
      COALESCE(p.stock, 0) AS stock,
      COALESCE(p.last_purchase_price, 0) AS last_cost,
      COALESCE(SUM(si.quantity), 0) AS sold_qty
    FROM products p
    LEFT JOIN sale_items si ON si.product_id = p.id
    LEFT JOIN sales s ON s.id = si.sale_id AND s.date BETWEEN ? AND ?
    GROUP BY p.id, p.sku, p.name, p.stock, p.last_purchase_price
    HAVING sold_qty > 0
    ORDER BY sold_qty DESC
  ''', [fromTxt, toTxt]);

  final totalDays = end.difference(start).inDays.abs();
  final days = totalDays == 0 ? 1 : totalDays;
  final suggestions = <PurchaseSuggestion>[];

  for (final row in rows) {
    final sold = (row['sold_qty'] as num?)?.toDouble() ?? 0.0;
    final avgDaily = sold / days;
    final stock = (row['stock'] as num?)?.toInt() ?? 0;
    final targetStock = (avgDaily * planningHorizonDays).ceil();
    final safetyStock = (avgDaily * safetyDays).ceil();
    final suggestedQty = math.max(targetStock - stock, 0);

    if (stock < safetyStock && suggestedQty > 0) {
      final lastCost = (row['last_cost'] as num?)?.toDouble() ?? 0.0;
      suggestions.add(PurchaseSuggestion(
        productId: row['id'] as int,
        sku: (row['sku'] ?? '').toString(),
        name: (row['name'] ?? '').toString(),
        stock: stock,
        suggestedQuantity: suggestedQty,
        averageDailySales: avgDaily,
        soldLastPeriod: sold.round(),
        estimatedCost: suggestedQty * lastCost,
      ));
    }
  }

  return suggestions;
}
