// lib/utils/xlsx_io.dart
import 'dart:typed_data';

import 'package:excel/excel.dart' as ex;
import 'package:sqflite/sqflite.dart';

import '../data/database.dart' as appdb;

/// Helpers ====================================================================

Future<Database> _db() async {
  try {
    return await appdb.getDb();
  } catch (_) {
    return await appdb.DatabaseHelper.instance.db;
  }
}

/// Lectura genérica de celdas, evitando APIs raras de excel 4.x.
/// Convertimos todo a String y luego a num/DateTime cuando hace falta.

String _cellStr(ex.Data? d) {
  final v = d?.value;
  if (v == null) return '';
  // En excel 4.x, value suele ser un CellValue (Int, Double, Text, Date, etc)
  // pero su toString() es razonable. Para evitar guerra de tipos,
  // usamos eso y parseamos.
  return v.toString().trim();
}

double _cellDouble(ex.Data? d) {
  final s = _cellStr(d).replaceAll(',', '.');
  if (s.isEmpty) return 0.0;
  return double.tryParse(s) ?? 0.0;
}

int _cellInt(ex.Data? d) {
  final s = _cellStr(d);
  if (s.isEmpty) return 0;
  return int.tryParse(s) ?? _cellDouble(d).round();
}

DateTime? _cellDate(ex.Data? d) {
  final s = _cellStr(d);
  if (s.isEmpty) return null;
  // Intentamos parsear ISO o 'yyyy-MM-dd'
  final dt = DateTime.tryParse(s);
  if (dt != null) return dt;
  // Si viene en formato 'dd/MM/yyyy', lo intentamos manualmente.
  final parts = s.split(RegExp(r'[/-]'));
  if (parts.length == 3) {
    final p0 = int.tryParse(parts[0]);
    final p1 = int.tryParse(parts[1]);
    final p2 = int.tryParse(parts[2]);
    if (p0 != null && p1 != null && p2 != null) {
      // Suponemos dd/MM/yyyy
      return DateTime(p2, p1, p0);
    }
  }
  return null;
}

/// Crea un libro nuevo con una hoja de nombre [name].
ex.Excel _newBookWithSheet(String name) {
  final book = ex.Excel.createExcel();
  // El createExcel crea una hoja por defecto llamada "Sheet1".
  // Podemos renombrar o simplemente usar [name].
  if (!book.sheets.containsKey(name)) {
    book.rename(book.getDefaultSheet()!, name);
  }
  return book;
}

/// EXPORTS =====================================================================

Future<Uint8List> buildProductsXlsxBytes() async {
  final db = await _db();
  final rows = await db.rawQuery('SELECT * FROM products ORDER BY name COLLATE NOCASE');

  final book = _newBookWithSheet('products');
  final sheet = book['products'];

  sheet.appendRow([
    'id',
    'sku',
    'name',
    'category',
    'default_sale_price',
    'last_purchase_price',
    'stock',
  ]);

  for (final r in rows) {
    sheet.appendRow([
      r['id'],
      r['sku'],
      r['name'],
      r['category'],
      r['default_sale_price'],
      r['last_purchase_price'],
      r['stock'],
    ]);
  }

  return Uint8List.fromList(book.encode()!);
}

Future<Uint8List> buildClientsXlsxBytes() async {
  final db = await _db();
  final rows = await db.rawQuery('SELECT * FROM customers ORDER BY name COLLATE NOCASE');

  final book = _newBookWithSheet('clients');
  final sheet = book['clients'];

  sheet.appendRow([
    'phone',
    'name',
    'address',
  ]);

  for (final r in rows) {
    sheet.appendRow([
      r['phone'],
      r['name'],
      r['address'],
    ]);
  }

  return Uint8List.fromList(book.encode()!);
}

Future<Uint8List> buildSuppliersXlsxBytes() async {
  final db = await _db();
  final rows = await db.rawQuery('SELECT * FROM suppliers ORDER BY name COLLATE NOCASE');

  final book = _newBookWithSheet('suppliers');
  final sheet = book['suppliers'];

  sheet.appendRow([
    'phone',
    'name',
    'address',
  ]);

  for (final r in rows) {
    sheet.appendRow([
      r['phone'],
      r['name'],
      r['address'],
    ]);
  }

  return Uint8List.fromList(book.encode()!);
}

/// EXPORT SALES XLSX (con costo, descuento unitario, envío por SKU, utilidad)
Future<Uint8List> buildSalesXlsxBytes() async {
  final db = await _db();

  // Totales por venta para prorratear descuento y envío
  final totals = await db.rawQuery('''
    SELECT
      s.id AS sale_id,
      COALESCE(SUM(si.quantity * si.unit_price), 0) AS items_sum,
      COALESCE(MAX(s.discount), 0) AS discount,
      COALESCE(MAX(s.shipping_cost), 0) AS shipping
    FROM sales s
    JOIN sale_items si ON si.sale_id = s.id
    GROUP BY s.id
  ''');

  final totalsBySale = <int, Map<String, double>>{};
  for (final t in totals) {
    final id = (t['sale_id'] as num).toInt();
    totalsBySale[id] = {
      'items_sum': (t['items_sum'] as num?)?.toDouble() ?? 0.0,
      'discount': (t['discount'] as num?)?.toDouble() ?? 0.0,
      'shipping': (t['shipping'] as num?)?.toDouble() ?? 0.0,
    };
  }

  // Detalle por SKU
  final rows = await db.rawQuery('''
    SELECT
      s.id AS sale_id,
      s.date,
      s.customer_phone,
      COALESCE(c.name, '') AS customer_name,
      COALESCE(s.payment_method, '') AS payment_method,
      COALESCE(s.discount, 0) AS sale_discount,
      COALESCE(s.shipping_cost, 0) AS sale_shipping,
      si.quantity,
      si.unit_price,
      p.sku,
      p.name AS product_name,
      COALESCE(p.last_purchase_price, 0) AS unit_cost
    FROM sale_items si
    JOIN sales s   ON s.id = si.sale_id
    JOIN products p ON p.id = si.product_id
    LEFT JOIN customers c ON c.phone = s.customer_phone
    ORDER BY s.date, s.id, p.name
  ''');

  final book = _newBookWithSheet('sales');
  final sheet = book['sales'];

  sheet.appendRow([
    'sale_id',
    'date',
    'customer_id',
    'customer_name',
    'payment_method',
    'sku',
    'product_name',
    'quantity',
    'unit_price',
    'line_gross',
    'unit_cost',
    'line_cost',
    'discount_total_alloc',
    'discount_per_unit',
    'shipping_total_alloc',
    'shipping_per_unit',
    'line_profit',
  ]);

  for (final r in rows) {
    final saleId = (r['sale_id'] as num).toInt();
    final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
    final unitPrice = (r['unit_price'] as num?)?.toDouble() ?? 0.0;
    final unitCost = (r['unit_cost'] as num?)?.toDouble() ?? 0.0;

    final lineGross = qty * unitPrice;

    final t = totalsBySale[saleId];
    final itemsSum = t?['items_sum'] ?? lineGross;
    final saleDiscount = t?['discount'] ?? (r['sale_discount'] as num?)?.toDouble() ?? 0.0;
    final saleShipping = t?['shipping'] ?? (r['sale_shipping'] as num?)?.toDouble() ?? 0.0;

    double lineDiscountTotal = 0.0;
    double lineShippingTotal = 0.0;

    if (itemsSum > 0) {
      final ratio = lineGross / itemsSum;
      lineDiscountTotal = saleDiscount * ratio;
      lineShippingTotal = saleShipping * ratio;
    }

    final discountPerUnit = qty > 0 ? lineDiscountTotal / qty : 0.0;
    final shippingPerUnit = qty > 0 ? lineShippingTotal / qty : 0.0;

    // Utilidad por SKU (NO restamos envío en la utilidad, sólo el descuento)
    final lineRevenueNet = lineGross - lineDiscountTotal;
    final lineCost = qty * unitCost;
    final lineProfit = lineRevenueNet - lineCost;

    sheet.appendRow([
      saleId,
      r['date'],
      r['customer_phone'],
      r['customer_name'],
      r['payment_method'],
      r['sku'],
      r['product_name'],
      qty,
      unitPrice,
      lineGross,
      unitCost,
      lineCost,
      lineDiscountTotal,
      discountPerUnit,
      lineShippingTotal,
      shippingPerUnit,
      lineProfit,
    ]);
  }

  return Uint8List.fromList(book.encode()!);
}

Future<Uint8List> buildPurchasesXlsxBytes() async {
  final db = await _db();

  final rows = await db.rawQuery('''
    SELECT
      p.id AS purchase_id,
      p.folio,
      p.date,
      p.supplier_phone,
      COALESCE(s.name,'') AS supplier_name,
      pi.quantity,
      pi.unit_cost,
      pr.sku,
      pr.name AS product_name
    FROM purchase_items pi
    JOIN purchases p ON p.id = pi.purchase_id
    JOIN products pr ON pr.id = pi.product_id
    LEFT JOIN suppliers s ON s.phone = p.supplier_phone
    ORDER BY p.date DESC, p.id DESC, pr.name
  ''');

  final book = _newBookWithSheet('purchases');
  final sheet = book['purchases'];

  sheet.appendRow([
    'purchase_id',
    'folio',
    'date',
    'supplier_phone',
    'supplier_name',
    'sku',
    'product_name',
    'quantity',
    'unit_cost',
    'line_total',
  ]);

  for (final r in rows) {
    final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
    final unitCost = (r['unit_cost'] as num?)?.toDouble() ?? 0.0;
    final lineTotal = qty * unitCost;

    sheet.appendRow([
      r['purchase_id'],
      r['folio'],
      r['date'],
      r['supplier_phone'],
      r['supplier_name'],
      r['sku'],
      r['product_name'],
      qty,
      unitCost,
      lineTotal,
    ]);
  }

  return Uint8List.fromList(book.encode()!);
}

/// IMPORTS ====================================================================

Future<void> importProductsXlsxBytes(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);
  final sheet = book.tables.values.first;
  if (sheet == null) return;

  final db = await _db();
  await db.transaction((txn) async {
    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      final sku = _cellStr(row[1]);
      if (sku.isEmpty) continue;

      final name = _cellStr(row[2]);
      final category = _cellStr(row[3]);
      final defaultSalePrice = _cellDouble(row[4]);
      final lastPurchasePrice = _cellDouble(row[5]);
      final stock = _cellInt(row[6]);

      await txn.insert(
        'products',
        {
          'sku': sku,
          'name': name,
          'category': category,
          'default_sale_price': defaultSalePrice,
          'last_purchase_price': lastPurchasePrice,
          'stock': stock,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  });
}

Future<void> importClientsXlsxBytes(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);
  final sheet = book.tables.values.first;
  if (sheet == null) return;

  final db = await _db();
  await db.transaction((txn) async {
    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      final phone = _cellStr(row[0]);
      if (phone.isEmpty) continue;

      final name = _cellStr(row[1]);
      final address = _cellStr(row[2]);

      await txn.insert(
        'customers',
        {
          'phone': phone,
          'name': name,
          'address': address,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  });
}

Future<void> importSuppliersXlsxBytes(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);
  final sheet = book.tables.values.first;
  if (sheet == null) return;

  final db = await _db();
  await db.transaction((txn) async {
    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      final phone = _cellStr(row[0]);
      if (phone.isEmpty) continue;

      final name = _cellStr(row[1]);
      final address = _cellStr(row[2]);

      await txn.insert(
        'suppliers',
        {
          'phone': phone,
          'name': name,
          'address': address,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  });
}

/// Import ventas en el NUEVO formato de sales.xlsx.
/// Si el usuario importa un archivo generado por esta misma app,
/// reconstruimos sales + sale_items de forma básica.
Future<void> importSalesXlsxBytes(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);
  final sheet = book.tables['sales'] ?? book.tables.values.first;
  if (sheet == null) return;

  final db = await _db();
  await db.transaction((txn) async {
    // Para evitar duplicar ventas, usamos sale_id + sku como llave simple.
    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (row.isEmpty) continue;

      final saleId = _cellInt(row[0]);
      if (saleId == 0) continue;

      final date = _cellStr(row[1]);
      final customerPhone = _cellStr(row[2]);
      final customerName = _cellStr(row[3]);
      final paymentMethod = _cellStr(row[4]);
      final sku = _cellStr(row[5]);
      if (sku.isEmpty) continue;

      final productName = _cellStr(row[6]);
      final qty = _cellInt(row[7]);
      final unitPrice = _cellDouble(row[8]);

      // Aseguramos producto por SKU
      final prodRows = await txn.query(
        'products',
        where: 'sku = ?',
        whereArgs: [sku],
        limit: 1,
      );
      int productId;
      if (prodRows.isEmpty) {
        productId = await txn.insert('products', {
          'sku': sku,
          'name': productName,
          'category': '',
          'default_sale_price': unitPrice,
          'last_purchase_price': 0.0,
          'stock': 0,
        });
      } else {
        productId = (prodRows.first['id'] as num).toInt();
      }

      // Aseguramos cliente
      if (customerPhone.isNotEmpty) {
        await txn.insert(
          'customers',
          {
            'phone': customerPhone,
            'name': customerName,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      // Insertamos/aseguramos la venta (id se ignora, se usa autoincrement; saleId del XLSX
      // es sólo informativo, no se reutiliza como PK para evitar conflictos)
      final realSaleId = await txn.insert(
        'sales',
        {
          'date': date,
          'customer_phone': customerPhone.isEmpty ? null : customerPhone,
          'payment_method': paymentMethod,
          // Descuento y envío no se reconstruyen con precisión desde este formato.
          'discount': 0.0,
          'shipping_cost': 0.0,
        },
      );

      await txn.insert(
        'sale_items',
        {
          'sale_id': realSaleId,
          'product_id': productId,
          'quantity': qty,
          'unit_price': unitPrice,
        },
      );

      // Actualizamos stock de forma simple (sumando ventas negativas NO, aquí sólo dejamos base).
      // Si quisieras ajustar stock aquí, habría que definir una política más fina.
    }
  });
}

/// Import compras en el formato actual de purchases.xlsx.
Future<void> importPurchasesXlsxBytes(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);
  final sheet = book.tables['purchases'] ?? book.tables.values.first;
  if (sheet == null) return;

  final db = await _db();
  await db.transaction((txn) async {
    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (row.isEmpty) continue;

      final folio = _cellStr(row[1]);
      final date = _cellStr(row[2]);
      final supplierPhone = _cellStr(row[3]);
      final supplierName = _cellStr(row[4]);
      final sku = _cellStr(row[5]);
      if (sku.isEmpty) continue;

      final productName = _cellStr(row[6]);
      final qty = _cellInt(row[7]);
      final unitCost = _cellDouble(row[8]);

      // Proveedor
      if (supplierPhone.isNotEmpty) {
        await txn.insert(
          'suppliers',
          {
            'phone': supplierPhone,
            'name': supplierName,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      // Producto
      final prodRows = await txn.query(
        'products',
        where: 'sku = ?',
        whereArgs: [sku],
        limit: 1,
      );
      int productId;
      if (prodRows.isEmpty) {
        productId = await txn.insert('products', {
          'sku': sku,
          'name': productName,
          'category': '',
          'default_sale_price': 0.0,
          'last_purchase_price': unitCost,
          'stock': qty,
        });
      } else {
        final existing = prodRows.first;
        productId = (existing['id'] as num).toInt();
        final prevStock = (existing['stock'] as num?)?.toInt() ?? 0;
        await txn.update(
          'products',
          {
            'last_purchase_price': unitCost,
            'stock': prevStock + qty,
          },
          where: 'id = ?',
          whereArgs: [productId],
        );
      }

      // Compra
      final realPurchaseId = await txn.insert(
        'purchases',
        {
          'folio': folio,
          'date': date,
          'supplier_phone': supplierPhone.isEmpty ? null : supplierPhone,
        },
      );

      await txn.insert(
        'purchase_items',
        {
          'purchase_id': realPurchaseId,
          'product_id': productId,
          'quantity': qty,
          'unit_cost': unitCost,
        },
      );
    }
  });
}