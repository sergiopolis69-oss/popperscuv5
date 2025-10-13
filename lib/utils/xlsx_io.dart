// lib/utils/xlsx_io.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:excel/excel.dart' as ex;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Importa todo lo necesario de sqflite (incluye DatabaseExecutor y getDatabasesPath si lo usas aquí)
import 'package:sqflite/sqflite.dart'
    show
        Database,
        DatabaseExecutor,
        ConflictAlgorithm,
        Sqflite;

import '../data/database.dart' as appdb;

/// ------ Helpers de ruta/guardado ------

Future<Directory> _downloadsDir() async {
  if (Platform.isAndroid) {
    final d = Directory('/storage/emulated/0/Download');
    if (await d.exists()) return d;
    return await getApplicationDocumentsDirectory();
  }
  return await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
}

/// Guarda bytes en Descargas con un nombre dado. Devuelve la ruta final.
Future<String> saveBytesToDownloads(
  BuildContext? _,
  {
    required String fileName,
    required List<int> bytes,
  }
) async {
  final dir = await _downloadsDir();
  final path = p.join(dir.path, fileName);
  final f = File(path);
  await f.writeAsBytes(bytes, flush: true);
  return path;
}

/// ------ Helpers de Excel ------

ex.Sheet _sheet(ex.Excel book, String name) => book[name];

List<List<ex.Data?>> _rows(ex.Sheet sh) => sh.rows;

/// Lectura segura de celdas (ex.Data? -> tipos base)
String _asString(ex.Data? d) {
  if (d is ex.TextCellValue) {
    final tv = d as ex.TextCellValue;
    return tv.value.text ?? '';
  }
  if (d is ex.DoubleCellValue) {
    final dv = d as ex.DoubleCellValue;
    return dv.value.toString();
  }
  if (d is ex.IntCellValue) {
    final iv = d as ex.IntCellValue;
    return iv.value.toString();
  }
  if (d is ex.DateCellValue) {
    final dt = d as ex.DateCellValue;
    return dt.value.toIso8601String();
  }
  return d?.toString() ?? '';
}

double _asDouble(ex.Data? d) {
  if (d is ex.DoubleCellValue) {
    final dv = d as ex.DoubleCellValue;
    return dv.value;
  }
  if (d is ex.IntCellValue) {
    final iv = d as ex.IntCellValue;
    return iv.value.toDouble();
  }
  if (d is ex.TextCellValue) {
    final tv = d as ex.TextCellValue;
    final s = (tv.value.text ?? '').replaceAll(',', '.');
    return double.tryParse(s) ?? 0.0;
  }
  return 0.0;
}

int _asInt(ex.Data? d) {
  if (d is ex.IntCellValue) {
    final iv = d as ex.IntCellValue;
    return iv.value;
  }
  if (d is ex.DoubleCellValue) {
    final dv = d as ex.DoubleCellValue;
    return dv.value.round();
  }
  if (d is ex.TextCellValue) {
    final tv = d as ex.TextCellValue;
    return int.tryParse(tv.value.text ?? '') ?? 0;
  }
  return 0;
}

DateTime? _asDateTime(ex.Data? d) {
  if (d is ex.DateCellValue) {
    final dt = d as ex.DateCellValue;
    return dt.value;
  }
  if (d is ex.TextCellValue) {
    final tv = d as ex.TextCellValue;
    return DateTime.tryParse(tv.value.text ?? '');
  }
  return null;
}

/// Constructores de celdas para escribir
ex.CellValue _tx(String s) => ex.TextCellValue(s);
ex.CellValue _dbl(num n) => ex.DoubleCellValue(n.toDouble());
ex.CellValue _int(int n) => ex.IntCellValue(n);

/// Serializa un libro a bytes
List<int> _excelToBytes(ex.Excel book) => book.encode()!;

/// ------ EXPORTS ------

Future<List<int>> buildProductsXlsxBytes() async {
  final db = await appdb.getDb();
  final rows = await db.rawQuery('''
    SELECT sku, name, IFNULL(category,'') AS category,
           IFNULL(default_sale_price,0) AS default_sale_price,
           IFNULL(last_purchase_price,0) AS last_purchase_price,
           IFNULL(stock,0) AS stock
    FROM products
    ORDER BY name
  ''');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'products');
  sh.appendRow(<ex.CellValue?>[
    _tx('sku'),
    _tx('name'),
    _tx('category'),
    _tx('default_sale_price'),
    _tx('last_purchase_price'),
    _tx('stock'),
  ]);

  for (final r in rows) {
    sh.appendRow(<ex.CellValue?>[
      _tx((r['sku'] ?? '').toString()),
      _tx((r['name'] ?? '').toString()),
      _tx((r['category'] ?? '').toString()),
      _dbl((r['default_sale_price'] as num?)?.toDouble() ?? 0.0),
      _dbl((r['last_purchase_price'] as num?)?.toDouble() ?? 0.0),
      _int((r['stock'] as num?)?.toInt() ?? 0),
    ]);
  }
  return _excelToBytes(book);
}

Future<List<int>> buildClientsXlsxBytes() async {
  final db = await appdb.getDb();
  final rows = await db.rawQuery('SELECT phone, name, IFNULL(address,"") AS address FROM customers ORDER BY name');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'clients');
  sh.appendRow(<ex.CellValue?>[_tx('phone'), _tx('name'), _tx('address')]);
  for (final r in rows) {
    sh.appendRow(<ex.CellValue?>[
      _tx((r['phone'] ?? '').toString()),
      _tx((r['name'] ?? '').toString()),
      _tx((r['address'] ?? '').toString()),
    ]);
  }
  return _excelToBytes(book);
}

Future<List<int>> buildSuppliersXlsxBytes() async {
  final db = await appdb.getDb();
  final rows = await db.rawQuery('SELECT phone, name, IFNULL(address,"") AS address FROM suppliers ORDER BY name');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'suppliers');
  sh.appendRow(<ex.CellValue?>[_tx('phone'), _tx('name'), _tx('address')]);
  for (final r in rows) {
    sh.appendRow(<ex.CellValue?>[
      _tx((r['phone'] ?? '').toString()),
      _tx((r['name'] ?? '').toString()),
      _tx((r['address'] ?? '').toString()),
    ]);
  }
  return _excelToBytes(book);
}

Future<List<int>> buildSalesXlsxBytes() async {
  final db = await appdb.getDb();
  final sales = await db.rawQuery('''
    SELECT id, customer_phone, payment_method, place,
           IFNULL(shipping_cost,0) AS shipping_cost,
           IFNULL(discount,0) AS discount,
           IFNULL(date,'') AS date
    FROM sales
    ORDER BY id
  ''');

  final items = await db.rawQuery('''
    SELECT si.sale_id, p.sku AS product_sku, si.quantity, si.unit_price
    FROM sale_items si
    JOIN products p ON p.id = si.product_id
    ORDER BY si.sale_id, p.sku
  ''');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'sales');
  sh.appendRow(<ex.CellValue?>[
    _tx('id'),
    _tx('customer_phone'),
    _tx('payment_method'),
    _tx('place'),
    _tx('shipping_cost'),
    _tx('discount'),
    _tx('date'),
  ]);

  for (final r in sales) {
    sh.appendRow(<ex.CellValue?>[
      _int((r['id'] as num?)?.toInt() ?? 0),
      _tx((r['customer_phone'] ?? '').toString()),
      _tx((r['payment_method'] ?? '').toString()),
      _tx((r['place'] ?? '').toString()),
      _dbl((r['shipping_cost'] as num?)?.toDouble() ?? 0.0),
      _dbl((r['discount'] as num?)?.toDouble() ?? 0.0),
      _tx((r['date'] ?? '').toString()),
    ]);
  }

  final si = _sheet(book, 'sales_items');
  si.appendRow(<ex.CellValue?>[
    _tx('sale_id'),
    _tx('product_sku'),
    _tx('quantity'),
    _tx('unit_price'),
  ]);

  for (final r in items) {
    si.appendRow(<ex.CellValue?>[
      _int((r['sale_id'] as num?)?.toInt() ?? 0),
      _tx((r['product_sku'] ?? '').toString()),
      _int((r['quantity'] as num?)?.toInt() ?? 0),
      _dbl((r['unit_price'] as num?)?.toDouble() ?? 0.0),
    ]);
  }

  return _excelToBytes(book);
}

Future<List<int>> buildPurchasesXlsxBytes() async {
  final db = await appdb.getDb();
  final purchases = await db.rawQuery('''
    SELECT pu.id, pu.folio, s.phone AS supplier_phone, IFNULL(pu.date,'') AS date
    FROM purchases pu
    LEFT JOIN suppliers s ON s.id = pu.supplier_id
    ORDER BY pu.id
  ''');

  final items = await db.rawQuery('''
    SELECT pi.purchase_id, p.sku AS product_sku, pi.quantity, pi.unit_cost
    FROM purchase_items pi
    JOIN products p ON p.id = pi.product_id
    ORDER BY pi.purchase_id, p.sku
  ''');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'purchases');
  sh.appendRow(<ex.CellValue?>[
    _tx('id'),
    _tx('folio'),
    _tx('supplier_phone'),
    _tx('date'),
  ]);

  for (final r in purchases) {
    sh.appendRow(<ex.CellValue?>[
      _int((r['id'] as num?)?.toInt() ?? 0),
      _tx((r['folio'] ?? '').toString()),
      _tx((r['supplier_phone'] ?? '').toString()),
      _tx((r['date'] ?? '').toString()),
    ]);
  }

  final si = _sheet(book, 'purchase_items');
  si.appendRow(<ex.CellValue?>[
    _tx('purchase_id'),
    _tx('product_sku'),
    _tx('quantity'),
    _tx('unit_cost'),
  ]);

  for (final r in items) {
    si.appendRow(<ex.CellValue?>[
      _int((r['purchase_id'] as num?)?.toInt() ?? 0),
      _tx((r['product_sku'] ?? '').toString()),
      _int((r['quantity'] as num?)?.toInt() ?? 0),
      _dbl((r['unit_cost'] as num?)?.toDouble() ?? 0.0),
    ]);
  }

  return _excelToBytes(book);
}

/// ------ IMPORTS ------

Future<void> importProductsXlsx(Uint8List bytes) async {
  final db = await appdb.getDb();
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book['products'];
  final rows = _rows(sh);
  if (rows.isEmpty) return;

  await db.transaction((txn) async {
    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final sku = _asString(r.elementAtOrNull(0)).trim();
      if (sku.isEmpty) continue;

      final name = _asString(r.elementAtOrNull(1)).trim();
      final category = _asString(r.elementAtOrNull(2)).trim();
      final dsp = _asDouble(r.elementAtOrNull(3));
      final lpp = _asDouble(r.elementAtOrNull(4));
      final stock = _asInt(r.elementAtOrNull(5));

      final exist = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM products WHERE sku=?',
        [sku],
      )) ?? 0;

      if (exist == 0) {
        await txn.insert('products', {
          'sku': sku,
          'name': name.isEmpty ? sku : name,
          'category': category,
          'default_sale_price': dsp,
          'last_purchase_price': lpp,
          'stock': stock,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      } else {
        await txn.update('products', {
          'name': name.isEmpty ? sku : name,
          'category': category,
          'default_sale_price': dsp,
          'last_purchase_price': lpp,
          'stock': stock,
        }, where: 'sku=?', whereArgs: [sku]);
      }
    }
  });
}

Future<void> importClientsXlsx(Uint8List bytes) async {
  final db = await appdb.getDb();
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book['clients'];
  final rows = _rows(sh);
  if (rows.isEmpty) return;

  await db.transaction((txn) async {
    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final phone = _asString(r.elementAtOrNull(0)).trim();
      if (phone.isEmpty) continue;
      final name = _asString(r.elementAtOrNull(1)).trim();
      final address = _asString(r.elementAtOrNull(2)).trim();

      final exist = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM customers WHERE phone = ?',
        [phone],
      )) ?? 0;

      if (exist == 0) {
        await txn.insert('customers', {
          'phone': phone,
          'name': name,
          'address': address,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      } else {
        await txn.update('customers', {
          'name': name,
          'address': address,
        }, where: 'phone=?', whereArgs: [phone]);
      }
    }
  });
}

Future<void> importSuppliersXlsx(Uint8List bytes) async {
  final db = await appdb.getDb();
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book['suppliers'];
  final rows = _rows(sh);
  if (rows.isEmpty) return;

  await db.transaction((txn) async {
    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      final phone = _asString(r.elementAtOrNull(0)).trim();
      if (phone.isEmpty) continue;
      final name = _asString(r.elementAtOrNull(1)).trim();
      final address = _asString(r.elementAtOrNull(2)).trim();

      final exist = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM suppliers WHERE phone=?',
        [phone],
      )) ?? 0;

      if (exist == 0) {
        await txn.insert('suppliers', {
          'phone': phone,
          'name': name,
          'address': address,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      } else {
        await txn.update('suppliers', {
          'name': name,
          'address': address,
        }, where: 'phone=?', whereArgs: [phone]);
      }
    }
  });
}

/// Asegura proveedor por teléfono y regresa su id.
Future<int?> _ensureSupplierByPhone(DatabaseExecutor txn, String phone) async {
  if (phone.isEmpty) return null;
  final got = await txn.query('suppliers', columns: ['id'], where: 'phone=?', whereArgs: [phone], limit: 1);
  if (got.isNotEmpty) return got.first['id'] as int;

  final id = await txn.insert('suppliers', {
    'phone': phone,
    'name': '',
    'address': '',
  }, conflictAlgorithm: ConflictAlgorithm.abort);
  return id;
}

/// Asegura producto por sku y regresa su id.
Future<int> _ensureProductBySku(DatabaseExecutor txn, String sku) async {
  final got = await txn.query('products', columns: ['id'], where: 'sku=?', whereArgs: [sku], limit: 1);
  if (got.isNotEmpty) return got.first['id'] as int;

  final id = await txn.insert('products', {
    'sku': sku,
    'name': sku,
    'category': '',
    'default_sale_price': 0.0,
    'last_purchase_price': 0.0,
    'stock': 0,
  }, conflictAlgorithm: ConflictAlgorithm.abort);
  return id;
}

Future<void> importSalesXlsx(Uint8List bytes) async {
  final db = await appdb.getDb();
  final book = ex.Excel.decodeBytes(bytes);

  final shSales = book['sales'];
  final shItems = book.sheets['sales_items'];

  final rowsSales = _rows(shSales);
  final rowsItems = shItems != null ? _rows(shItems) : const <List<ex.Data?>>[];
  if (rowsSales.isEmpty) return;

  final Map<int, List<Map<String, dynamic>>> itemsBySale = {};
  if (rowsItems.isNotEmpty) {
    for (var i = 1; i < rowsItems.length; i++) {
      final r = rowsItems[i];
      final saleId = _asInt(r.elementAtOrNull(0));
      final sku = _asString(r.elementAtOrNull(1)).trim();
      final qty = _asInt(r.elementAtOrNull(2));
      final unit = _asDouble(r.elementAtOrNull(3));
      if (saleId <= 0 || sku.isEmpty || qty <= 0) continue;
      (itemsBySale[saleId] ??= []).add({'sku': sku, 'quantity': qty, 'unit_price': unit});
    }
  }

  await db.transaction((txn) async {
    for (var i = 1; i < rowsSales.length; i++) {
      final r = rowsSales[i];
      final extId = _asInt(r.elementAtOrNull(0));
      final phone = _asString(r.elementAtOrNull(1)).trim();
      final pay = _asString(r.elementAtOrNull(2)).trim();
      final place = _asString(r.elementAtOrNull(3)).trim();
      final ship = _asDouble(r.elementAtOrNull(4));
      final disc = _asDouble(r.elementAtOrNull(5));
      final date = _asString(r.elementAtOrNull(6)).trim();

      int saleId;
      if (extId > 0) {
        final exist = Sqflite.firstIntValue(await txn.rawQuery('SELECT COUNT(*) FROM sales WHERE id=?', [extId])) ?? 0;
        if (exist == 0) {
          saleId = await txn.insert('sales', {
            'id': extId,
            'customer_phone': phone,
            'payment_method': pay,
            'place': place,
            'shipping_cost': ship,
            'discount': disc,
            'date': date,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        } else {
          saleId = extId;
          await txn.update('sales', {
            'customer_phone': phone,
            'payment_method': pay,
            'place': place,
            'shipping_cost': ship,
            'discount': disc,
            'date': date,
          }, where: 'id=?', whereArgs: [extId]);
          await txn.delete('sale_items', where: 'sale_id=?', whereArgs: [extId]);
        }
      } else {
        saleId = await txn.insert('sales', {
          'customer_phone': phone,
          'payment_method': pay,
          'place': place,
          'shipping_cost': ship,
          'discount': disc,
          'date': date,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }

      final items = itemsBySale[saleId] ?? itemsBySale[extId] ?? <Map<String, dynamic>>[];
      for (final it in items) {
        final pid = await _ensureProductBySku(txn, it['sku'] as String);
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': pid,
          'quantity': it['quantity'],
          'unit_price': it['unit_price'],
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }
    }
  });
}

Future<void> importPurchasesXlsx(Uint8List bytes) async {
  final db = await appdb.getDb();
  final book = ex.Excel.decodeBytes(bytes);

  final shPur = book['purchases'];
  final shItems = book.sheets['purchase_items'];

  final rowsPur = _rows(shPur);
  final rowsItems = shItems != null ? _rows(shItems) : const <List<ex.Data?>>[];
  if (rowsPur.isEmpty) return;

  final Map<int, List<Map<String, dynamic>>> itemsByPurchase = {};
  if (rowsItems.isNotEmpty) {
    for (var i = 1; i < rowsItems.length; i++) {
      final r = rowsItems[i];
      final purchaseId = _asInt(r.elementAtOrNull(0));
      final sku = _asString(r.elementAtOrNull(1)).trim();
      final qty = _asInt(r.elementAtOrNull(2));
      final cost = _asDouble(r.elementAtOrNull(3));
      if (purchaseId <= 0 || sku.isEmpty || qty <= 0) continue;
      (itemsByPurchase[purchaseId] ??= []).add({'sku': sku, 'quantity': qty, 'unit_cost': cost});
    }
  }

  await db.transaction((txn) async {
    for (var i = 1; i < rowsPur.length; i++) {
      final r = rowsPur[i];
      final id = _asInt(r.elementAtOrNull(0));
      final folio = _asString(r.elementAtOrNull(1)).trim();
      final supplierPhone = _asString(r.elementAtOrNull(2)).trim();
      final date = _asString(r.elementAtOrNull(3)).trim();

      final supplierId = await _ensureSupplierByPhone(txn, supplierPhone) ?? 0;

      int purchaseId;
      if (id > 0) {
        final exist = Sqflite.firstIntValue(await txn.rawQuery('SELECT COUNT(*) FROM purchases WHERE id=?', [id])) ?? 0;
        if (exist == 0) {
          purchaseId = await txn.insert('purchases', {
            'id': id,
            'folio': folio,
            'supplier_id': supplierId,
            'date': date,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        } else {
          purchaseId = id;
          await txn.update('purchases', {
            'folio': folio,
            'supplier_id': supplierId,
            'date': date,
          }, where: 'id=?', whereArgs: [id]);
          await txn.delete('purchase_items', where: 'purchase_id=?', whereArgs: [id]);
        }
      } else {
        purchaseId = await txn.insert('purchases', {
          'folio': folio,
          'supplier_id': supplierId,
          'date': date,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }

      final items = itemsByPurchase[purchaseId] ?? itemsByPurchase[id] ?? <Map<String, dynamic>>[];
      for (final it in items) {
        final pid = await _ensureProductBySku(txn, it['sku'] as String);
        await txn.insert('purchase_items', {
          'purchase_id': purchaseId,
          'product_id': pid,
          'quantity': it['quantity'],
          'unit_cost': it['unit_cost'],
        }, conflictAlgorithm: ConflictAlgorithm.abort);

        // Actualiza último costo de compra
        await txn.update('products', {
          'last_purchase_price': it['unit_cost'],
          'last_purchase_date': DateTime.now().toIso8601String(),
        }, where: 'id=?', whereArgs: [pid]);
      }
    }
  });
}