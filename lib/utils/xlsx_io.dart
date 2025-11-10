// lib/utils/xlsx_io.dart
import 'dart:typed_data';

import 'package:excel/excel.dart' as ex;
import 'package:sqflite/sqflite.dart';
import 'package:popperscuv5/data/database.dart' as appdb;

//
// ========= Helpers: Excel -> Dart =========
//

String _asString(ex.Data? d) {
  if (d == null) return '';

  if (d is ex.TextCellValue) {
    return d.value.text ?? '';
  }
  if (d is ex.DoubleCellValue) {
    return d.value.toString();
  }
  if (d is ex.IntCellValue) {
    return d.value.toString();
  }
  if (d is ex.DateCellValue) {
    final dt = DateTime(d.year, d.month, d.day);
    return dt.toIso8601String();
  }
  return d.toString();
}

double _asDouble(ex.Data? d) {
  if (d == null) return 0.0;

  if (d is ex.DoubleCellValue) {
    return d.value;
  }
  if (d is ex.IntCellValue) {
    return d.value.toDouble();
  }
  if (d is ex.TextCellValue) {
    final s = (d.value.text ?? '').replaceAll(',', '.');
    return double.tryParse(s) ?? 0.0;
  }
  return 0.0;
}

int _asInt(ex.Data? d) {
  if (d == null) return 0;

  if (d is ex.IntCellValue) {
    return d.value;
  }
  if (d is ex.DoubleCellValue) {
    return d.value.round();
  }
  if (d is ex.TextCellValue) {
    return int.tryParse(d.value.text ?? '') ?? 0;
  }
  return 0;
}

DateTime? _asDate(ex.Data? d) {
  if (d == null) return null;

  if (d is ex.DateCellValue) {
    return DateTime(d.year, d.month, d.day);
  }
  if (d is ex.TextCellValue) {
    return DateTime.tryParse(d.value.text ?? '');
  }
  return null;
}

//
// ========= Writers: Dart -> Excel =========
//

ex.CellValue _tx(String s) => ex.TextCellValue(s);
ex.CellValue _i(int n) => ex.IntCellValue(n);
ex.CellValue _d(num n) => ex.DoubleCellValue(n.toDouble());
ex.CellValue _date(DateTime dt) =>
    ex.DateCellValue(year: dt.year, month: dt.month, day: dt.day);

/// Excel 4.x: book[name] crea/obtiene la hoja.
ex.Sheet _sheet(ex.Excel book, String name) => book[name];

//
// ========= EXPORT =========
//

Future<Uint8List> buildProductsXlsxBytes() async {
  final db = await appdb.getDb();
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
  final db = await appdb.getDb();
  final rows =
      await db.rawQuery('SELECT phone, name, address FROM customers ORDER BY name');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'clients');

  sh.appendRow([
    _tx('phone'),
    _tx('name'),
    _tx('address'),
  ]);

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
  final db = await appdb.getDb();
  final rows =
      await db.rawQuery('SELECT phone, name, address FROM suppliers ORDER BY name');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'suppliers');

  sh.appendRow([
    _tx('phone'),
    _tx('name'),
    _tx('address'),
  ]);

  for (final r in rows) {
    sh.appendRow([
      _tx((r['phone'] ?? '').toString()),
      _tx((r['name'] ?? '').toString()),
      _tx((r['address'] ?? '').toString()),
    ]);
  }

  return Uint8List.fromList(book.encode()!);
}

/// Exporta:
/// - Hoja `sales` (igual que antes, compatible con import)
/// - Hoja `sale_items` (igual que antes)
/// - **Nueva hoja `sales_detailed`** con:
///   sale_id, date, customer_id, customer_name, payment_method,
///   sku, product_name, quantity, unit_price, line_gross,
///   unit_cost, line_cost, discount_total_alloc, discount_per_unit,
///   shipping_total_alloc, shipping_per_unit, line_profit
Future<Uint8List> buildSalesXlsxBytes() async {
  final db = await appdb.getDb();

  // Cabeceras de venta (igual que antes, aunque aquí agrego el nombre del cliente
  // solo para la hoja detallada).
  final sales = await db.rawQuery('''
    SELECT
      s.id,
      s.customer_phone,
      COALESCE(c.name, '') AS customer_name,
      s.payment_method,
      s.place,
      s.shipping_cost,
      s.discount,
      s.date
    FROM sales s
    LEFT JOIN customers c ON c.phone = s.customer_phone
    ORDER BY s.id
  ''');

  // Ítems de venta, con info adicional de producto para la hoja detallada.
  final items = await db.rawQuery('''
    SELECT
      si.sale_id,
      si.product_id,
      p.sku       AS product_sku,
      p.name      AS product_name,
      si.quantity,
      si.unit_price,
      COALESCE(p.last_purchase_price, 0) AS unit_cost
    FROM sale_items si
    JOIN products p ON p.id = si.product_id
    ORDER BY si.sale_id
  ''');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'sales');
  final si = _sheet(book, 'sale_items');
  final sd = _sheet(book, 'sales_detailed');

  //
  // Hoja "sales" (como antes, para compatibilidad con importSalesXlsxBytes)
  //
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

  //
  // Hoja "sale_items" (como antes, para compatibilidad con importSalesXlsxBytes)
  //
  si.appendRow([
    _tx('sale_id'),
    _tx('product_sku'),
    _tx('quantity'),
    _tx('unit_price'),
  ]);

  for (final r in items) {
    si.appendRow([
      _i((r['sale_id'] as num?)?.toInt() ?? 0),
      _tx((r['product_sku'] ?? '').toString()),
      _i((r['quantity'] as num?)?.toInt() ?? 0),
      _d((r['unit_price'] as num?)?.toDouble() ?? 0.0),
    ]);
  }

  //
  // NUEVA Hoja "sales_detailed": una sola página con todo por SKU
  //

  sd.appendRow([
    _tx('sale_id'),
    _tx('date'),
    _tx('customer_id'),
    _tx('customer_name'),
    _tx('payment_method'),
    _tx('sku'),
    _tx('product_name'),
    _tx('quantity'),
    _tx('unit_price'),
    _tx('line_gross'),
    _tx('unit_cost'),
    _tx('line_cost'),
    _tx('discount_total_alloc'),
    _tx('discount_per_unit'),
    _tx('shipping_total_alloc'),
    _tx('shipping_per_unit'),
    _tx('line_profit'),
  ]);

  // Indexar ventas por id para acceso rápido
  final salesById = <int, Map<String, Object?>>{};
  for (final s in sales) {
    final id = (s['id'] as num?)?.toInt() ?? 0;
    if (id != 0) {
      salesById[id] = s;
    }
  }

  // Agrupar items por sale_id
  final itemsBySale = <int, List<Map<String, Object?>>>{};
  for (final it in items) {
    final saleId = (it['sale_id'] as num?)?.toInt() ?? 0;
    if (saleId == 0) continue;
    itemsBySale.putIfAbsent(saleId, () => []).add(it);
  }

  // Construir filas detalladas
  for (final entry in itemsBySale.entries) {
    final saleId = entry.key;
    final saleItems = entry.value;

    final sale = salesById[saleId];
    if (sale == null) continue;

    final date = (sale['date'] ?? '').toString();
    final custPhone = (sale['customer_phone'] ?? '').toString();
    final custName = (sale['customer_name'] ?? '').toString();
    final payMethod = (sale['payment_method'] ?? '').toString();
    final shipping =
        (sale['shipping_cost'] as num?)?.toDouble() ?? 0.0;
    final discount =
        (sale['discount'] as num?)?.toDouble() ?? 0.0;

    // Total bruto de la venta (para prorratear descuento y envío)
    double totalGross = 0.0;
    for (final it in saleItems) {
      final qty = (it['quantity'] as num?)?.toDouble() ?? 0.0;
      final unitPrice = (it['unit_price'] as num?)?.toDouble() ?? 0.0;
      totalGross += qty * unitPrice;
    }
    if (totalGross <= 0) {
      totalGross = 1; // evitar división entre cero
    }

    // Filas por ítem
    for (final it in saleItems) {
      final sku = (it['product_sku'] ?? '').toString();
      final productName = (it['product_name'] ?? '').toString();

      final qty = (it['quantity'] as num?)?.toDouble() ?? 0.0;
      final unitPrice = (it['unit_price'] as num?)?.toDouble() ?? 0.0;
      final unitCost = (it['unit_cost'] as num?)?.toDouble() ?? 0.0;

      final lineGross = qty * unitPrice;
      final lineCost = qty * unitCost;

      // Prorrateo de descuento y envío en función del valor bruto
      final shareFactor = lineGross / totalGross;

      final lineDiscountTotal = discount * shareFactor;
      final discountPerUnit =
          qty > 0 ? (lineDiscountTotal / qty) : 0.0;

      final lineShippingTotal = shipping * shareFactor;
      final shippingPerUnit =
          qty > 0 ? (lineShippingTotal / qty) : 0.0;

      // Utilidad por línea:
      // ingreso neto = lineGross - lineDiscountTotal
      // utilidad = ingreso neto - costo (envío no se descuenta porque no lo consideramos ingreso)
      final netRevenue = lineGross - lineDiscountTotal;
      final lineProfit = netRevenue - lineCost;

      sd.appendRow([
        _i(saleId),
        _tx(date),
        _tx(custPhone),
        _tx(custName),
        _tx(payMethod),
        _tx(sku),
        _tx(productName),
        _d(qty),
        _d(unitPrice),
        _d(lineGross),
        _d(unitCost),
        _d(lineCost),
        _d(lineDiscountTotal),
        _d(discountPerUnit),
        _d(lineShippingTotal),
        _d(shippingPerUnit),
        _d(lineProfit),
      ]);
    }
  }

  return Uint8List.fromList(book.encode()!);
}

Future<Uint8List> buildPurchasesXlsxBytes() async {
  final db = await appdb.getDb();

  final pur = await db.rawQuery('''
    SELECT
      pu.id   AS id,
      pu.folio,
      s.phone AS supplier_phone,
      pu.date
    FROM purchases pu
    LEFT JOIN suppliers s ON s.id = pu.supplier_id
    ORDER BY pu.id
  ''');

  final items = await db.rawQuery('''
    SELECT
      pu.id           AS purchase_id,
      p.sku           AS product_sku,
      pi.quantity,
      pi.unit_cost
    FROM purchases pu
    JOIN purchase_items pi ON pi.purchase_id = pu.id
    JOIN products p        ON p.id = pi.product_id
    ORDER BY pu.id
  ''');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'purchases');
  final si = _sheet(book, 'purchase_items');

  sh.appendRow([
    _tx('id'),
    _tx('folio'),
    _tx('supplier_phone'),
    _tx('date'),
  ]);

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

//
// ========= IMPORT (desde bytes) =========
//

Future<void> importProductsXlsxBytes(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book.sheets['products'];
  if (sh == null) return;

  final db = await appdb.getDb();

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
            await txn.rawQuery(
              'SELECT id FROM products WHERE sku=?',
              [sku],
            ),
          ) ??
          0;

      final data = <String, Object?>{
        'sku': sku,
        'name': name,
        'category': category,
        'default_sale_price': dsp,
        'last_purchase_price': lpp,
        'stock': stock,
      };

      if (pid == 0) {
        await txn.insert(
          'products',
          data,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
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

  final db = await appdb.getDb();

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

  final db = await appdb.getDb();

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
            await txn.rawQuery(
              'SELECT id FROM suppliers WHERE phone=?',
              [phone],
            ),
          ) ??
          0;

      final data = <String, Object?>{
        'phone': phone,
        'name': _asString(r.elementAtOrNull(1)),
        'address': _asString(r.elementAtOrNull(2)),
      };

      if (sid == 0) {
        await txn.insert(
          'suppliers',
          data,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
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

  final db = await appdb.getDb();

  await db.transaction((txn) async {
    // CABECERAS
    var first = true;
    for (final r in sh.rows) {
      if (first) {
        first = false;
        continue;
      }

      final id = _asInt(r.elementAtOrNull(0));
      if (id == 0) continue;

      final exist = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM sales WHERE id=?',
              [id],
            ),
          ) ??
          0;

      final data = <String, Object?>{
        'id': id,
        'customer_phone': _asString(r.elementAtOrNull(1)),
        'payment_method': _asString(r.elementAtOrNull(2)),
        'place': _asString(r.elementAtOrNull(3)),
        'shipping_cost': _asDouble(r.elementAtOrNull(4)),
        'discount': _asDouble(r.elementAtOrNull(5)),
        'date': _asString(r.elementAtOrNull(6)),
      };

      if (exist == 0) {
        await txn.insert(
          'sales',
          data,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
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

    // ITEMS
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
      final unit = _asDouble(r.elementAtOrNull(3));

      final pid = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT id FROM products WHERE sku=?',
              [sku],
            ),
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

Future<int?> _ensureSupplierByPhone(DatabaseExecutor txn, String phone) async {
  if (phone.isEmpty) return null;

  final id = Sqflite.firstIntValue(
        await txn.rawQuery(
          'SELECT id FROM suppliers WHERE phone=?',
          [phone],
        ),
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
        await txn.rawQuery(
          'SELECT id FROM products WHERE sku=?',
          [sku],
        ),
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

  final db = await appdb.getDb();

  await db.transaction((txn) async {
    // CABECERAS
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
            await txn.rawQuery(
              'SELECT COUNT(*) FROM purchases WHERE id=?',
              [extId],
            ),
          ) ??
          0;

      final data = <String, Object?>{
        'id': extId,
        'folio': folio,
        'supplier_id': supId,
        'date': date,
      };

      if (exist == 0) {
        await txn.insert(
          'purchases',
          data,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
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

    // ITEMS
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
            await txn.rawQuery(
              'SELECT id FROM purchases WHERE id=?',
              [pid],
            ),
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