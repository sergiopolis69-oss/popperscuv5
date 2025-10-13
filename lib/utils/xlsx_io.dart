import 'dart:typed_data';
import 'dart:io';

import 'package:excel/excel.dart' as ex;
import 'package:sqflite/sqflite.dart';
import 'package:file_picker/file_picker.dart';

import '../data/database.dart' as appdb;

/// Guarda bytes usando el diálogo del sistema (evita permisos de almacenamiento).
Future<String> saveBytesWithSystemPicker({
  required String fileName,
  required List<int> bytes,
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Guardar $fileName',
    fileName: fileName,
    bytes: Uint8List.fromList(bytes),
    type: FileType.custom,
    allowedExtensions: const ['xlsx', 'db'],
  );
  if (path == null) {
    throw 'Guardado cancelado';
  }
  return path;
}

// ======================= Helpers Excel =======================

/// En excel 4.x se crea/obtiene la hoja usando el operador [].
ex.Sheet _sheet(ex.Excel book, String name) => book[name];

ex.CellValue _tx(String s) => ex.TextCellValue(s);
ex.CellValue _dbl(num n) => ex.DoubleCellValue(n.toDouble());
ex.CellValue _int(int n) => ex.IntCellValue(n);

/// Para máxima compatibilidad, exportamos fechas como TEXTO ISO8601.
ex.CellValue _dtAsText(DateTime d) => _tx(d.toIso8601String());

String _cellAsString(ex.Data? d) {
  if (d == null || d.value == null) return '';
  final v = d.value!;
  if (v is ex.TextCellValue) return v.value.text ?? '';
  if (v is ex.DoubleCellValue) return v.value.toString();
  if (v is ex.IntCellValue) return v.value.toString();
  if (v is ex.DateCellValue) {
    // Algunas versiones no exponen hora/min/seg; usamos sólo Y-M-D
    final dt = DateTime(v.year, v.month, v.day);
    return dt.toIso8601String();
  }
  return v.toString();
}

double _cellAsDouble(ex.Data? d) {
  if (d == null || d.value == null) return 0.0;
  final v = d.value!;
  if (v is ex.DoubleCellValue) return v.value;
  if (v is ex.IntCellValue) return v.value.toDouble();
  if (v is ex.TextCellValue) {
    final s = (v.value.text ?? '').replaceAll(',', '.');
    return double.tryParse(s) ?? 0.0;
  }
  return 0.0;
}

int _cellAsInt(ex.Data? d) {
  if (d == null || d.value == null) return 0;
  final v = d.value!;
  if (v is ex.IntCellValue) return v.value;
  if (v is ex.DoubleCellValue) return v.value.round();
  if (v is ex.TextCellValue) return int.tryParse(v.value.text ?? '') ?? 0;
  return 0;
}

DateTime? _cellAsDate(ex.Data? d) {
  if (d == null || d.value == null) return null;
  final v = d.value!;
  if (v is ex.DateCellValue) {
    return DateTime(v.year, v.month, v.day);
  }
  if (v is ex.TextCellValue) return DateTime.tryParse(v.value.text ?? '');
  return null;
}

Map<String, int> _headerIndex(List<ex.Data?> header) {
  final m = <String, int>{};
  for (var i = 0; i < header.length; i++) {
    final key = _cellAsString(header[i]).trim().toLowerCase();
    if (key.isEmpty) continue;
    m[key] = i;
  }
  return m;
}

int _idx(Map<String, int> m, List<String> keys) {
  for (final k in keys) {
    final idx = m[k];
    if (idx != null) return idx;
  }
  return -1;
}

ex.Sheet? _findSheetWithHeaders(ex.Excel book, List<String> requiredKeys) {
  for (final entry in book.sheets.entries) {
    final rows = entry.value.rows;
    if (rows.isEmpty) continue;
    final h = _headerIndex(rows.first);
    final ok = requiredKeys.every((k) => h.containsKey(k));
    if (ok) return entry.value;
  }
  return null;
}

// ======================= EXPORT =======================

Future<List<int>> buildProductsXlsxBytes() async {
  final db = await appdb.getDb();
  final rows = await db.rawQuery(
    'SELECT sku,name,category,default_sale_price,last_purchase_price,stock '
    'FROM products ORDER BY name',
  );

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'productos');
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
      _dbl((r['default_sale_price'] as num?)?.toDouble() ?? 0),
      _dbl((r['last_purchase_price'] as num?)?.toDouble() ?? 0),
      _int((r['stock'] as num?)?.toInt() ?? 0),
    ]);
  }
  return book.encode()!;
}

Future<List<int>> buildClientsXlsxBytes() async {
  final db = await appdb.getDb();
  final rows =
      await db.rawQuery('SELECT phone,name,address FROM customers ORDER BY name');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'clientes');
  sh.appendRow([_tx('phone'), _tx('name'), _tx('address')]);
  for (final r in rows) {
    sh.appendRow([
      _tx((r['phone'] ?? '').toString()),
      _tx((r['name'] ?? '').toString()),
      _tx((r['address'] ?? '').toString()),
    ]);
  }
  return book.encode()!;
}

Future<List<int>> buildSuppliersXlsxBytes() async {
  final db = await appdb.getDb();
  final rows =
      await db.rawQuery('SELECT phone,name,address FROM suppliers ORDER BY name');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'proveedores');
  sh.appendRow([_tx('phone'), _tx('name'), _tx('address')]);
  for (final r in rows) {
    sh.appendRow([
      _tx((r['phone'] ?? '').toString()),
      _tx((r['name'] ?? '').toString()),
      _tx((r['address'] ?? '').toString()),
    ]);
  }
  return book.encode()!;
}

Future<List<int>> buildSalesXlsxBytes() async {
  final db = await appdb.getDb();
  final sales = await db.rawQuery(
    'SELECT id, customer_phone, payment_method, place, shipping_cost, discount, date '
    'FROM sales ORDER BY id',
  );
  final items = await db.rawQuery(
    'SELECT sale_id, p.sku AS product_sku, quantity, unit_price '
    'FROM sale_items si JOIN products p ON p.id=si.product_id ORDER BY sale_id',
  );

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'ventas');
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
      _int((r['id'] as num?)?.toInt() ?? 0),
      _tx((r['customer_phone'] ?? '').toString()),
      _tx((r['payment_method'] ?? '').toString()),
      _tx((r['place'] ?? '').toString()),
      _dbl((r['shipping_cost'] as num?)?.toDouble() ?? 0),
      _dbl((r['discount'] as num?)?.toDouble() ?? 0),
      _tx((r['date'] ?? '').toString()),
    ]);
  }

  final si = _sheet(book, 'venta_items');
  si.appendRow([_tx('sale_id'), _tx('product_sku'), _tx('quantity'), _tx('unit_price')]);
  for (final r in items) {
    si.appendRow([
      _int((r['sale_id'] as num?)?.toInt() ?? 0),
      _tx((r['product_sku'] ?? '').toString()),
      _int((r['quantity'] as num?)?.toInt() ?? 0),
      _dbl((r['unit_price'] as num?)?.toDouble() ?? 0),
    ]);
  }
  return book.encode()!;
}

Future<List<int>> buildPurchasesXlsxBytes() async {
  final db = await appdb.getDb();
  final purchases = await db.rawQuery(
    'SELECT id, folio, s.phone AS supplier_phone, date '
    'FROM purchases pu LEFT JOIN suppliers s ON s.id=pu.supplier_id ORDER BY id',
  );
  final items = await db.rawQuery(
    'SELECT purchase_id, p.sku AS product_sku, quantity, unit_cost '
    'FROM purchase_items pi JOIN products p ON p.id=pi.product_id ORDER BY purchase_id',
  );

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'compras');
  sh.appendRow([_tx('id'), _tx('folio'), _tx('supplier_phone'), _tx('date')]);
  for (final r in purchases) {
    sh.appendRow([
      _int((r['id'] as num?)?.toInt() ?? 0),
      _tx((r['folio'] ?? '').toString()),
      _tx((r['supplier_phone'] ?? '').toString()),
      _tx((r['date'] ?? '').toString()),
    ]);
  }

  final si = _sheet(book, 'compra_items');
  si.appendRow([_tx('purchase_id'), _tx('product_sku'), _tx('quantity'), _tx('unit_cost')]);
  for (final r in items) {
    si.appendRow([
      _int((r['purchase_id'] as num?)?.toInt() ?? 0),
      _tx((r['product_sku'] ?? '').toString()),
      _int((r['quantity'] as num?)?.toInt() ?? 0),
      _dbl((r['unit_cost'] as num?)?.toDouble() ?? 0),
    ]);
  }
  return book.encode()!;
}

// ======================= IMPORT =======================

Future<int?> _ensureSupplierByPhone(DatabaseExecutor txn, String phone) async {
  if (phone.isEmpty) return null;
  final exist = Sqflite.firstIntValue(
    await txn.rawQuery('SELECT id FROM suppliers WHERE phone=? LIMIT 1', [phone]),
  );
  if (exist != null) return exist;
  return await txn.insert('suppliers', {'phone': phone, 'name': '', 'address': ''});
}

Future<int> _ensureProductBySku(DatabaseExecutor txn, String sku) async {
  final exist = Sqflite.firstIntValue(
    await txn.rawQuery('SELECT id FROM products WHERE sku=? LIMIT 1', [sku]),
  );
  if (exist != null) return exist;
  return await txn.insert('products', {
    'sku': sku,
    'name': sku,
    'category': '',
    'default_sale_price': 0,
    'last_purchase_price': 0,
    'stock': 0,
  });
}

Future<void> importProductsXlsx(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);

  final required = [
    'sku',
    'name',
    'category',
    'default_sale_price',
    'last_purchase_price',
    'stock'
  ];
  final sh = book.sheets['productos'] ?? _findSheetWithHeaders(book, required);
  if (sh == null || sh.rows.isEmpty) {
    throw 'Hoja de productos inválida';
  }
  final head = _headerIndex(sh.rows.first);
  final iSku = _idx(head, ['sku']);
  final iName = _idx(head, ['name', 'nombre']);
  final iCat = _idx(head, ['category', 'categoria', 'categoría']);
  final iDsp = _idx(head, ['default_sale_price', 'precio', 'precio_venta']);
  final iLpp = _idx(head, ['last_purchase_price', 'costo', 'ultimo_costo', 'último_costo']);
  final iStock = _idx(head, ['stock', 'existencias']);

  final db = await appdb.getDb();
  await db.transaction((txn) async {
    for (var r = 1; r < sh.rows.length; r++) {
      final row = sh.rows[r];
      final sku = _cellAsString(row.elementAtOrNull(iSku)).trim();
      if (sku.isEmpty) continue;
      final name = _cellAsString(row.elementAtOrNull(iName)).trim();
      final data = {
        'sku': sku,
        'name': name.isEmpty ? sku : name,
        'category': _cellAsString(row.elementAtOrNull(iCat)).trim(),
        'default_sale_price': _cellAsDouble(row.elementAtOrNull(iDsp)),
        'last_purchase_price': _cellAsDouble(row.elementAtOrNull(iLpp)),
        'stock': _cellAsInt(row.elementAtOrNull(iStock)),
      };
      final exists = Sqflite.firstIntValue(
        await txn.rawQuery('SELECT id FROM products WHERE sku=?', [sku]),
      );
      if (exists == null) {
        await txn.insert('products', data, conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        await txn.update('products', data, where: 'id=?', whereArgs: [exists]);
      }
    }
  });
}

Future<void> importClientsXlsx(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book.sheets['clientes'] ??
      _findSheetWithHeaders(book, ['phone', 'name', 'address']);
  if (sh == null || sh.rows.isEmpty) throw 'Hoja de clientes inválida';
  final head = _headerIndex(sh.rows.first);
  final iPhone = _idx(head, ['phone', 'telefono', 'teléfono']);
  final iName = _idx(head, ['name', 'nombre']);
  final iAddr = _idx(head, ['address', 'direccion', 'dirección']);

  final db = await appdb.getDb();
  await db.transaction((txn) async {
    for (var i = 1; i < sh.rows.length; i++) {
      final r = sh.rows[i];
      final phone = _cellAsString(r.elementAtOrNull(iPhone)).trim();
      if (phone.isEmpty) continue;
      final data = {
        'phone': phone,
        'name': _cellAsString(r.elementAtOrNull(iName)).trim(),
        'address': _cellAsString(r.elementAtOrNull(iAddr)).trim(),
      };
      final exists = Sqflite.firstIntValue(
        await txn.rawQuery('SELECT COUNT(*) FROM customers WHERE phone=?', [phone]),
      );
      if ((exists ?? 0) > 0) {
        await txn.update('customers', data, where: 'phone=?', whereArgs: [phone]);
      } else {
        await txn.insert('customers', data, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  });
}

Future<void> importSuppliersXlsx(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book.sheets['proveedores'] ??
      _findSheetWithHeaders(book, ['phone', 'name', 'address']);
  if (sh == null || sh.rows.isEmpty) throw 'Hoja de proveedores inválida';
  final head = _headerIndex(sh.rows.first);
  final iPhone = _idx(head, ['phone', 'telefono', 'teléfono']);
  final iName = _idx(head, ['name', 'nombre']);
  final iAddr = _idx(head, ['address', 'direccion', 'dirección']);

  final db = await appdb.getDb();
  await db.transaction((txn) async {
    for (var i = 1; i < sh.rows.length; i++) {
      final r = sh.rows[i];
      final phone = _cellAsString(r.elementAtOrNull(iPhone)).trim();
      if (phone.isEmpty) continue;
      final data = {
        'phone': phone,
        'name': _cellAsString(r.elementAtOrNull(iName)).trim(),
        'address': _cellAsString(r.elementAtOrNull(iAddr)).trim(),
      };
      final existId = Sqflite.firstIntValue(
        await txn.rawQuery('SELECT id FROM suppliers WHERE phone=?', [phone]),
      );
      if (existId == null) {
        await txn.insert('suppliers', data, conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        await txn.update('suppliers', data, where: 'id=?', whereArgs: [existId]);
      }
    }
  });
}

Future<void> importSalesXlsx(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);

  final shSales = book.sheets['ventas'] ??
      _findSheetWithHeaders(book, [
        'id',
        'customer_phone',
        'payment_method',
        'place',
        'shipping_cost',
        'discount',
        'date'
      ]);
  final shItems = book.sheets['venta_items'] ??
      _findSheetWithHeaders(book, ['sale_id', 'product_sku', 'quantity', 'unit_price']);
  if (shSales == null || shItems == null) throw 'Hojas de ventas inválidas';

  final hS = _headerIndex(shSales.rows.first);
  final sId = _idx(hS, ['id']);
  final sPhone = _idx(hS, ['customer_phone', 'cliente', 'telefono', 'teléfono']);
  final sPay = _idx(hS, ['payment_method', 'pago']);
  final sPlace = _idx(hS, ['place', 'lugar']);
  final sShip = _idx(hS, ['shipping_cost', 'envio', 'envío']);
  final sDisc = _idx(hS, ['discount', 'descuento']);
  final sDate = _idx(hS, ['date', 'fecha']);

  final hI = _headerIndex(shItems.rows.first);
  final iSale = _idx(hI, ['sale_id']);
  final iSku = _idx(hI, ['product_sku', 'sku']);
  final iQty = _idx(hI, ['quantity', 'cantidad']);
  final iUnit = _idx(hI, ['unit_price', 'precio']);

  final db = await appdb.getDb();
  await db.transaction((txn) async {
    // ventas
    for (var r = 1; r < shSales.rows.length; r++) {
      final row = shSales.rows[r];
      final extId = _cellAsInt(row.elementAtOrNull(sId));
      final phone = _cellAsString(row.elementAtOrNull(sPhone)).trim();
      final data = {
        'id': extId,
        'customer_phone': phone.isEmpty ? null : phone,
        'payment_method': _cellAsString(row.elementAtOrNull(sPay)).trim(),
        'place': _cellAsString(row.elementAtOrNull(sPlace)).trim(),
        'shipping_cost': _cellAsDouble(row.elementAtOrNull(sShip)),
        'discount': _cellAsDouble(row.elementAtOrNull(sDisc)),
        'date': _cellAsString(row.elementAtOrNull(sDate)),
      };
      final exists = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM sales WHERE id=?', [extId]),
          ) ??
          0;
      if (exists > 0) {
        await txn.update('sales', data, where: 'id=?', whereArgs: [extId]);
      } else {
        await txn.insert('sales', data, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    // items
    for (var r = 1; r < shItems.rows.length; r++) {
      final row = shItems.rows[r];
      final saleId = _cellAsInt(row.elementAtOrNull(iSale));
      final sku = _cellAsString(row.elementAtOrNull(iSku)).trim();
      if (sku.isEmpty) continue;
      final prodId = await _ensureProductBySku(txn, sku);
      final data = {
        'sale_id': saleId,
        'product_id': prodId,
        'quantity': _cellAsInt(row.elementAtOrNull(iQty)),
        'unit_price': _cellAsDouble(row.elementAtOrNull(iUnit)),
      };
      await txn.insert('sale_items', data, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}

Future<void> importPurchasesXlsx(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);

  final shPurch = book.sheets['compras'] ??
      _findSheetWithHeaders(book, ['id', 'folio', 'supplier_phone', 'date']);
  final shItems = book.sheets['compra_items'] ??
      _findSheetWithHeaders(book, ['purchase_id', 'product_sku', 'quantity', 'unit_cost']);
  if (shPurch == null || shItems == null) throw 'Hojas de compras inválidas';

  final hP = _headerIndex(shPurch.rows.first);
  final pId = _idx(hP, ['id']);
  final pFolio = _idx(hP, ['folio']);
  final pPhone = _idx(hP, ['supplier_phone', 'phone', 'telefono', 'teléfono']);
  final pDate = _idx(hP, ['date', 'fecha']);

  final hI = _headerIndex(shItems.rows.first);
  final iPid = _idx(hI, ['purchase_id']);
  final iSku = _idx(hI, ['product_sku', 'sku']);
  final iQty = _idx(hI, ['quantity', 'cantidad']);
  final iCost = _idx(hI, ['unit_cost', 'costo']);

  final db = await appdb.getDb();
  await db.transaction((txn) async {
    for (var r = 1; r < shPurch.rows.length; r++) {
      final row = shPurch.rows[r];
      final id = _cellAsInt(row.elementAtOrNull(pId));
      final phone = _cellAsString(row.elementAtOrNull(pPhone)).trim();
      final supId = await _ensureSupplierByPhone(txn, phone);
      final data = {
        'id': id,
        'folio': _cellAsString(row.elementAtOrNull(pFolio)).trim(),
        'supplier_id': supId,
        'date': _cellAsString(row.elementAtOrNull(pDate)),
      };
      final exists = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM purchases WHERE id=?', [id]),
          ) ??
          0;
      if (exists > 0) {
        await txn.update('purchases', data, where: 'id=?', whereArgs: [id]);
      } else {
        await txn.insert('purchases', data, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    for (var r = 1; r < shItems.rows.length; r++) {
      final row = shItems.rows[r];
      final pid = _cellAsInt(row.elementAtOrNull(iPid));
      final sku = _cellAsString(row.elementAtOrNull(iSku)).trim();
      if (sku.isEmpty) continue;
      final prodId = await _ensureProductBySku(txn, sku);
      final data = {
        'purchase_id': pid,
        'product_id': prodId,
        'quantity': _cellAsInt(row.elementAtOrNull(iQty)),
        'unit_cost': _cellAsDouble(row.elementAtOrNull(iCost)),
      };
      await txn.insert('purchase_items', data, conflictAlgorithm: ConflictAlgorithm.replace);

      // actualiza costo y stock
      await txn.update('products', {
        'last_purchase_price': data['unit_cost'],
      }, where: 'id=?', whereArgs: [prodId]);

      await txn.rawUpdate(
          'UPDATE products SET stock = IFNULL(stock,0) + ? WHERE id=?',
          [data['quantity'], prodId]);
    }
  });
}