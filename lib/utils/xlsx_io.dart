// lib/utils/xlsx_io.dart
import 'dart:typed_data';

import 'package:excel/excel.dart' as ex;
import 'package:sqflite/sqflite.dart';
import 'package:popperscuv5/data/database.dart' as appdb;

/// ========= Helpers: Excel -> Dart =========

String _asString(ex.Data? d) {
  final v = d?.value;
  if (v == null) return '';
  if (v is ex.TextCellValue) return v.value;
  if (v is ex.DoubleCellValue) return v.value.toString();
  if (v is ex.IntCellValue) return v.value.toString();
  if (v is ex.DateCellValue) return v.value.toIso8601String();
  return v.toString();
}

double _asDouble(ex.Data? d) {
  final v = d?.value;
  if (v == null) return 0.0;
  if (v is ex.DoubleCellValue) return v.value;
  if (v is ex.IntCellValue) return v.value.toDouble();
  if (v is ex.TextCellValue) {
    final s = v.value.replaceAll(',', '.');
    return double.tryParse(s) ?? 0.0;
  }
  return 0.0;
}

int _asInt(ex.Data? d) {
  final v = d?.value;
  if (v == null) return 0;
  if (v is ex.IntCellValue) return v.value;
  if (v is ex.DoubleCellValue) return v.value.round();
  if (v is ex.TextCellValue) return int.tryParse(v.value) ?? 0;
  return 0;
}

DateTime? _asDate(ex.Data? d) {
  final v = d?.value;
  if (v == null) return null;
  if (v is ex.DateCellValue) return v.value;
  if (v is ex.TextCellValue) return DateTime.tryParse(v.value);
  return null;
}

/// ========= Writers: Dart -> Excel =========

ex.CellValue _tx(String s) => ex.TextCellValue(s);
ex.CellValue _i(int n) => ex.IntCellValue(n);
ex.CellValue _d(num n) => ex.DoubleCellValue(n.toDouble());
ex.CellValue _date(DateTime dt) =>
    ex.DateCellValue(year: dt.year, month: dt.month, day: dt.day);

// Excel 4.x: book[name] crea/obtiene la hoja.
ex.Sheet _sheet(ex.Excel book, String name) => book[name];

Future<Database> _db() async {
  try {
    // Si existe getDb() lo usamos
    return await appdb.getDb();
  } catch (_) {
    // Fallback al singleton clásico
    return await appdb.DatabaseHelper.instance.db;
  }
}

/// ========= EXPORT =========

Future<Uint8List> buildProductsXlsxBytes() async {
  final db = await _db();
  final rows = await db.rawQuery('''
    SELECT sku, name, category, default_sale_price, last_purchase_price, stock
    FROM products
    ORDER BY name
  ''');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'products');

  sh.appendRow([
    _tx('sku'),
    _tx('name'),
    _tx('category'),
    _tx('default_sale_price'),
    _tx('last_purchase_price'),
    _tx('stock'),
  ]);

  for (final r in rows) {
    sh.appendRow([
      _tx((r['sku'] ?? '').toString()),
      _tx((r['name'] ?? '').toString()),
      _tx((r['category'] ?? '').toString()),
      _d((r['default_sale_price'] as num?)?.toDouble() ?? 0.0),
      _d((r['last_purchase_price'] as num?)?.toDouble() ?? 0.0),
      _i((r['stock'] as num?)?.toInt() ?? 0),
    ]);
  }

  return Uint8List.fromList(book.encode()!);
}

Future<Uint8List> buildClientsXlsxBytes() async {
  final db = await _db();
  final rows = await db
      .rawQuery('SELECT phone, name, address FROM customers ORDER BY name');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'clients');

  sh.appendRow([_tx('phone'), _tx('name'), _tx('address')]);

  for (final r in rows) {
    sh.appendRow([
      _tx((r['phone'] ?? '').toString()),
      _tx((r['name'] ?? '').toString()),
      _tx((r['address'] ?? '').toString()),
    ]);
  }

  return Uint8List.fromList(book.encode()!);
}

Future<Uint8List> buildSuppliersXlsxBytes() async {
  final db = await _db();
  final rows = await db
      .rawQuery('SELECT phone, name, address FROM suppliers ORDER BY name');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'suppliers');

  sh.appendRow([_tx('phone'), _tx('name'), _tx('address')]);

  for (final r in rows) {
    sh.appendRow([
      _tx((r['phone'] ?? '').toString()),
      _tx((r['name'] ?? '').toString()),
      _tx((r['address'] ?? '').toString()),
    ]);
  }

  return Uint8List.fromList(book.encode()!);
}

///
/// VENTAS: ahora la hoja `sale_items` incluye:
/// - sale_id
/// - product_sku
/// - quantity
/// - unit_price
/// - unit_cost
/// - unit_discount
/// - unit_shipping
/// - line_profit
///
/// Los primeros 4 campos se mantienen igual → importSalesXlsxBytes sigue sirviendo.
///
Future<Uint8List> buildSalesXlsxBytes() async {
  final db = await _db();

  // Cabeceras de ventas
  final sales = await db.rawQuery('''
    SELECT id, customer_phone, payment_method, place, shipping_cost, discount, date
    FROM sales
    ORDER BY id
  ''');

  // Ítems con costo unitario estimado (último precio de compra)
  final items = await db.rawQuery('''
    SELECT
      si.sale_id,
      p.sku AS product_sku,
      si.quantity,
      si.unit_price,
      COALESCE(p.last_purchase_price, 0) AS unit_cost
    FROM sale_items si
    JOIN products p ON p.id = si.product_id
    ORDER BY si.sale_id
  ''');

  // Mapas auxiliares por venta
  final Map<int, double> saleDiscounts = {};
  final Map<int, double> saleShipping = {};
  final Map<int, double> saleSubtotals = {};

  for (final s in sales) {
    final id = (s['id'] as num?)?.toInt() ?? 0;
    if (id == 0) continue;
    saleDiscounts[id] = (s['discount'] as num?)?.toDouble() ?? 0.0;
    saleShipping[id] = (s['shipping_cost'] as num?)?.toDouble() ?? 0.0;
  }

  // Calculamos subtotales de cada venta (solo artículos, sin descuento/ envío)
  for (final r in items) {
    final saleId = (r['sale_id'] as num?)?.toInt() ?? 0;
    final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
    final unitPrice = (r['unit_price'] as num?)?.toDouble() ?? 0.0;
    final lineSub = qty * unitPrice;
    saleSubtotals[saleId] = (saleSubtotals[saleId] ?? 0.0) + lineSub;
  }

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'sales');
  final si = _sheet(book, 'sale_items');

  // Hoja sales (igual que antes)
  sh.appendRow([
    _tx('id'),
    _tx('customer_phone'),
    _tx('payment_method'),
    _tx('place'),
    _tx('shipping_cost'),
    _tx('discount'),
    _tx('date'),
  ]);

  for (final r in sales) {
    sh.appendRow([
      _i((r['id'] as num?)?.toInt() ?? 0),
      _tx((r['customer_phone'] ?? '').toString()),
      _tx((r['payment_method'] ?? '').toString()),
      _tx((r['place'] ?? '').toString()),
      _d((r['shipping_cost'] as num?)?.toDouble() ?? 0.0),
      _d((r['discount'] as num?)?.toDouble() ?? 0.0),
      _tx((r['date'] ?? '').toString()),
    ]);
  }

  // Hoja sale_items con columnas extra por SKU
  si.appendRow([
    _tx('sale_id'),
    _tx('product_sku'),
    _tx('quantity'),
    _tx('unit_price'),
    _tx('unit_cost'),
    _tx('unit_discount'),
    _tx('unit_shipping'),
    _tx('line_profit'),
  ]);

  for (final r in items) {
    final saleId = (r['sale_id'] as num?)?.toInt() ?? 0;
    final qtyInt = (r['quantity'] as num?)?.toInt() ?? 0;
    final qty = qtyInt.toDouble();
    final unitPrice = (r['unit_price'] as num?)?.toDouble() ?? 0.0;
    final unitCost = (r['unit_cost'] as num?)?.toDouble() ?? 0.0;

    final lineSub = qty * unitPrice;
    final saleSub = saleSubtotals[saleId] ?? 0.0;
    final share = saleSub > 0 ? (lineSub / saleSub) : 0.0;

    final saleDisc = saleDiscounts[saleId] ?? 0.0;
    final saleShip = saleShipping[saleId] ?? 0.0;

    final lineDiscTotal = share * saleDisc;
    final lineShipTotal = share * saleShip;

    final unitDisc = qty > 0 ? (lineDiscTotal / qty) : 0.0;
    final unitShip = qty > 0 ? (lineShipTotal / qty) : 0.0;

    final lineCostTotal = unitCost * qty;
    final lineProfit =
        lineSub - lineCostTotal - lineDiscTotal - lineShipTotal;

    si.appendRow([
      _i(saleId),
      _tx((r['product_sku'] ?? '').toString()),
      _i(qtyInt),
      _d(unitPrice),
      _d(unitCost),
      _d(unitDisc),
      _d(unitShip),
      _d(lineProfit),
    ]);
  }

  return Uint8List.fromList(book.encode()!);
}

Future<Uint8List> buildPurchasesXlsxBytes() async {
  final db = await _db();

  final pur = await db.rawQuery('''
    SELECT pu.id AS id, pu.folio, s.phone AS supplier_phone, pu.date
    FROM purchases pu
    LEFT JOIN suppliers s ON s.id = pu.supplier_id
    ORDER BY pu.id
  ''');

  final items = await db.rawQuery('''
    SELECT
      pu.id AS purchase_id,
      p.sku AS product_sku,
      pi.quantity,
      pi.unit_cost
    FROM purchases pu
    JOIN purchase_items pi ON pi.purchase_id = pu.id
    JOIN products p ON p.id = pi.product_id
    ORDER BY pu.id
  ''');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'purchases');
  final si = _sheet(book, 'purchase_items');

  sh.appendRow([_tx('id'), _tx('folio'), _tx('supplier_phone'), _tx('date')]);
  for (final r in pur) {
    sh.appendRow([
      _i((r['id'] as num?)?.toInt() ?? 0),
      _tx((r['folio'] ?? '').toString()),
      _tx((r['supplier_phone'] ?? '').toString()),
      _tx((r['date'] ?? '').toString()),
    ]);
  }

  si.appendRow([
    _tx('purchase_id'),
    _tx('product_sku'),
    _tx('quantity'),
    _tx('unit_cost'),
  ]);
  for (final r in items) {
    si.appendRow([
      _i((r['purchase_id'] as num?)?.toInt() ?? 0),
      _tx((r['product_sku'] ?? '').toString()),
      _i((r['quantity'] as num?)?.toInt() ?? 0),
      _d((r['unit_cost'] as num?)?.toDouble() ?? 0.0),
    ]);
  }

  return Uint8List.fromList(book.encode()!);
}

/// ========= IMPORT (desde bytes) =========

Future<void> importProductsXlsxBytes(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book.sheets['products'];
  if (sh == null) return;

  final db = await _db();
  await db.transaction((txn) async {
    var first = true;
    for (final row in sh.rows) {
      if (first) {
        first = false;
        continue;
      }

      final sku = _asString(row.elementAtOrNull(0));
      if (sku.trim().isEmpty) continue;
      final name = _asString(row.elementAtOrNull(1));
      final category = _asString(row.elementAtOrNull(2));
      final dsp = _asDouble(row.elementAtOrNull(3));
      final lpp = _asDouble(row.elementAtOrNull(4));
      final stock = _asInt(row.elementAtOrNull(5));

      final pid = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT id FROM products WHERE sku=?', [sku]),
          ) ??
          0;

      final data = {
        'sku': sku,
        'name': name,
        'category': category,
        'default_sale_price': dsp,
        'last_purchase_price': lpp,
        'stock': stock,
      };

      if (pid == 0) {
        await txn.insert('products', data,
            conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        await txn.update(
          'products',
          data,
          where: 'id=?',
          whereArgs: [pid],
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
  });
}

Future<void> importClientsXlsxBytes(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book.sheets['clients'];
  if (sh == null) return;

  final db = await _db();
  await db.transaction((txn) async {
    var first = true;
    for (final r in sh.rows) {
      if (first) {
        first = false;
        continue;
      }

      final phone = _asString(r.elementAtOrNull(0));
      if (phone.isEmpty) continue;

      await txn.insert(
        'customers',
        {
          'phone': phone,
          'name': _asString(r.elementAtOrNull(1)),
          'address': _asString(r.elementAtOrNull(2)),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  });
}

Future<void> importSuppliersXlsxBytes(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book.sheets['suppliers'];
  if (sh == null) return;

  final db = await _db();
  await db.transaction((txn) async {
    var first = true;
    for (final r in sh.rows) {
      if (first) {
        first = false;
        continue;
      }

      final phone = _asString(r.elementAtOrNull(0));
      if (phone.isEmpty) continue;

      final sid = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT id FROM suppliers WHERE phone=?', [phone]),
          ) ??
          0;

      final data = {
        'phone': phone,
        'name': _asString(r.elementAtOrNull(1)),
        'address': _asString(r.elementAtOrNull(2)),
      };

      if (sid == 0) {
        await txn.insert('suppliers', data,
            conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        await txn.update(
          'suppliers',
          data,
          where: 'id=?',
          whereArgs: [sid],
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
  });
}

Future<void> importSalesXlsxBytes(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book.sheets['sales'];
  final si = book.sheets['sale_items'];
  if (sh == null || si == null) return;

  final db = await _db();
  await db.transaction((txn) async {
    // Cabeceras de ventas
    var first = true;
    for (final r in sh.rows) {
      if (first) {
        first = false;
        continue;
      }

      final id = _asInt(r.elementAtOrNull(0));
      if (id == 0) continue;

      final exist = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM sales WHERE id=?', [id]),
          ) ??
          0;

      final data = {
        'id': id,
        'customer_phone': _asString(r.elementAtOrNull(1)),
        'payment_method': _asString(r.elementAtOrNull(2)),
        'place': _asString(r.elementAtOrNull(3)),
        'shipping_cost': _asDouble(r.elementAtOrNull(4)),
        'discount': _asDouble(r.elementAtOrNull(5)),
        'date': _asString(r.elementAtOrNull(6)),
      };

      if (exist == 0) {
        await txn.insert('sales', data,
            conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        await txn.update(
          'sales',
          data,
          where: 'id=?',
          whereArgs: [id],
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    // Ítems de venta
    first = true;
    for (final r in si.rows) {
      if (first) {
        first = false;
        continue;
      }

      final saleId = _asInt(r.elementAtOrNull(0));
      if (saleId == 0) continue;

      final sku = _asString(r.elementAtOrNull(1));
      final qty = _asInt(r.elementAtOrNull(2));
      final unit = _asDouble(r.elementAtOrNull(3)); // las columnas extra se ignoran

      final pid = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT id FROM products WHERE sku=?', [sku]),
          ) ??
          0;
      if (pid == 0) continue;

      await txn.insert(
        'sale_items',
        {
          'sale_id': saleId,
          'product_id': pid,
          'quantity': qty,
          'unit_price': unit,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  });
}

Future<int?> _ensureSupplierByPhone(
    DatabaseExecutor txn, String phone) async {
  if (phone.isEmpty) return null;
  final id = Sqflite.firstIntValue(
        await txn.rawQuery('SELECT id FROM suppliers WHERE phone=?', [phone]),
      ) ??
      0;
  if (id != 0) return id;

  return await txn.insert(
    'suppliers',
    {'phone': phone},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<int> _ensureProductBySku(DatabaseExecutor txn, String sku) async {
  final id = Sqflite.firstIntValue(
        await txn.rawQuery('SELECT id FROM products WHERE sku=?', [sku]),
      ) ??
      0;
  if (id != 0) return id;

  return await txn.insert(
    'products',
    {'sku': sku, 'name': sku},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> importPurchasesXlsxBytes(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book.sheets['purchases'];
  final si = book.sheets['purchase_items'];
  if (sh == null || si == null) return;

  final db = await _db();
  await db.transaction((txn) async {
    var first = true;
    for (final r in sh.rows) {
      if (first) {
        first = false;
        continue;
      }

      final extId = _asInt(r.elementAtOrNull(0));
      final folio = _asString(r.elementAtOrNull(1));
      final supplierPhone = _asString(r.elementAtOrNull(2));
      final date = _asString(r.elementAtOrNull(3));

      final supId = await _ensureSupplierByPhone(txn, supplierPhone);

      final exist = Sqflite.firstIntValue(
            await txn
                .rawQuery('SELECT COUNT(*) FROM purchases WHERE id=?', [extId]),
          ) ??
          0;

      final data = {
        'id': extId,
        'folio': folio,
        'supplier_id': supId,
        'date': date,
      };

      if (exist == 0) {
        await txn.insert('purchases', data,
            conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        await txn.update(
          'purchases',
          data,
          where: 'id=?',
          whereArgs: [extId],
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    first = true;
    for (final r in si.rows) {
      if (first) {
        first = false;
        continue;
      }

      final pid = _asInt(r.elementAtOrNull(0));
      final sku = _asString(r.elementAtOrNull(1));
      final qty = _asInt(r.elementAtOrNull(2));
      final cost = _asDouble(r.elementAtOrNull(3));

      final dbPid = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT id FROM purchases WHERE id=?', [pid]),
          ) ??
          0;
      if (dbPid == 0) continue;

      final prodId = await _ensureProductBySku(txn, sku);

      await txn.insert(
        'purchase_items',
        {
          'purchase_id': dbPid,
          'product_id': prodId,
          'quantity': qty,
          'unit_cost': cost,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  });
}