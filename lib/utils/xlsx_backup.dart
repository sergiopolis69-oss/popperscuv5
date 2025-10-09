import 'dart:typed_data';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

CellValue _cv(dynamic v) {
  if (v == null) return TextCellValue('');
  if (v is int) return IntCellValue(v);
  if (v is num) return DoubleCellValue(v.toDouble());
  return TextCellValue(v.toString());
}

Future<void> _saveExcel(String baseName, Excel excel) async {
  final list = excel.encode();
  if (list == null || list.isEmpty) {
    throw 'No se generó contenido XLSX (excel.encode() vacío).';
  }
  final bytes = Uint8List.fromList(list);
  final out = await FileSaver.instance.saveFile(
    name: baseName,
    bytes: bytes,
    ext: 'xlsx',
    mimeType: MimeType.microsoftExcel,
  );
  if (out == null || (out is String && out.trim().isEmpty)) {
    throw 'El sistema no devolvió una ruta/URI al guardar.';
  }
}

Future<Excel?> _pickExcel() async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
  );
  if (res == null || res.files.isEmpty) return null;
  final path = res.files.single.path;
  if (path == null) return null;
  final bytes = await File(path).readAsBytes();
  return Excel.decodeBytes(bytes);
}

// --------------------- EXPORT ---------------------

Future<void> exportSalesXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.createExcel();

  final sales = await db.rawQuery('''
    SELECT id, customer_phone, payment_method, place, shipping_cost, discount, date
    FROM sales ORDER BY date DESC
  ''');

  final items = await db.rawQuery('''
    SELECT sale_id, sku, quantity, unit_price
    FROM sale_items
  ''');

  final shSales = excel['sales'];
  shSales.appendRow([
    TextCellValue('id'),
    TextCellValue('customer_phone'),
    TextCellValue('payment_method'),
    TextCellValue('place'),
    TextCellValue('shipping_cost'),
    TextCellValue('discount'),
    TextCellValue('date'),
  ]);
  for (final s in sales) {
    shSales.appendRow([
      _cv(s['id']),
      _cv(s['customer_phone']),
      _cv(s['payment_method']),
      _cv(s['place']),
      _cv(s['shipping_cost']),
      _cv(s['discount']),
      _cv(s['date']),
    ]);
  }

  final shItems = excel['sale_items'];
  shItems.appendRow([
    TextCellValue('sale_id'),
    TextCellValue('sku'),
    TextCellValue('quantity'),
    TextCellValue('unit_price'),
  ]);
  for (final it in items) {
    shItems.appendRow([
      _cv(it['sale_id']),
      _cv(it['sku']),
      _cv(it['quantity']),
      _cv(it['unit_price']),
    ]);
  }

  await _saveExcel('ventas', excel);
}

Future<void> exportPurchasesXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.createExcel();

  final purchases = await db.rawQuery('''
    SELECT id, supplier_id, folio, date
    FROM purchases ORDER BY date DESC
  ''');

  final items = await db.rawQuery('''
    SELECT purchase_id, sku, quantity, unit_cost
    FROM purchase_items
  ''');

  final shP = excel['purchases'];
  shP.appendRow([
    TextCellValue('id'),
    TextCellValue('supplier_id'),
    TextCellValue('folio'),
    TextCellValue('date'),
  ]);
  for (final p in purchases) {
    shP.appendRow([
      _cv(p['id']),
      _cv(p['supplier_id']),
      _cv(p['folio']),
      _cv(p['date']),
    ]);
  }

  final shI = excel['purchase_items'];
  shI.appendRow([
    TextCellValue('purchase_id'),
    TextCellValue('sku'),
    TextCellValue('quantity'),
    TextCellValue('unit_cost'),
  ]);
  for (final it in items) {
    shI.appendRow([
      _cv(it['purchase_id']),
      _cv(it['sku']),
      _cv(it['quantity']),
      _cv(it['unit_cost']),
    ]);
  }

  await _saveExcel('compras', excel);
}

Future<void> exportProductsXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.createExcel();

  final products = await db.rawQuery('''
    SELECT id, sku, name, category, default_sale_price, last_purchase_price, stock, last_purchase_date
    FROM products ORDER BY name ASC
  ''');

  final sh = excel['products'];
  sh.appendRow([
    TextCellValue('id'),
    TextCellValue('sku'),
    TextCellValue('name'),
    TextCellValue('category'),
    TextCellValue('default_sale_price'),
    TextCellValue('last_purchase_price'),
    TextCellValue('stock'),
    TextCellValue('last_purchase_date'),
  ]);
  for (final p in products) {
    sh.appendRow([
      _cv(p['id']),
      _cv(p['sku']),
      _cv(p['name']),
      _cv(p['category']),
      _cv(p['default_sale_price']),
      _cv(p['last_purchase_price']),
      _cv(p['stock']),
      _cv(p['last_purchase_date']),
    ]);
  }

  await _saveExcel('productos', excel);
}

Future<void> exportClientsXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.createExcel();

  final rows = await db.rawQuery('''
    SELECT phone, name, address
    FROM customers ORDER BY name ASC
  ''');

  final sh = excel['customers'];
  sh.appendRow([
    TextCellValue('phone'),
    TextCellValue('name'),
    TextCellValue('address'),
  ]);
  for (final c in rows) {
    sh.appendRow([
      _cv(c['phone']),
      _cv(c['name']),
      _cv(c['address']),
    ]);
  }

  await _saveExcel('clientes', excel);
}

Future<void> exportSuppliersXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.createExcel();

  final rows = await db.rawQuery('''
    SELECT phone, name, address
    FROM suppliers ORDER BY name ASC
  ''');

  final sh = excel['suppliers'];
  sh.appendRow([
    TextCellValue('phone'),
    TextCellValue('name'),
    TextCellValue('address'),
  ]);
  for (final s in rows) {
    sh.appendRow([
      _cv(s['phone']),
      _cv(s['name']),
      _cv(s['address']),
    ]);
  }

  await _saveExcel('proveedores', excel);
}

// --------------------- IMPORT ---------------------

Future<void> importSalesXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) throw 'No se eligió archivo .xlsx';

  final db = await DatabaseHelper.instance.db;
  final header = excel['sales'];
  final items  = excel['sale_items'];
  if (header.maxRows <= 1) throw 'La hoja "sales" no tiene datos.';
  if (items.maxRows <= 1) throw 'La hoja "sale_items" no tiene datos.';

  final idMap = <int, int>{};

  for (final r in header.rows.skip(1)) {
    final newId = await db.insert('sales', {
      'customer_phone': r[1]?.value?.toString(),
      'payment_method': r[2]?.value?.toString(),
      'place': r[3]?.value?.toString(),
      'shipping_cost': (r[4]?.value as num?)?.toDouble() ?? 0.0,
      'discount': (r[5]?.value as num?)?.toDouble() ?? 0.0,
      'date': r[6]?.value?.toString(),
    });
    final oldId = (r[0]?.value as num).toInt();
    idMap[oldId] = newId;
  }

  for (final r in items.rows.skip(1)) {
    final oldSale = (r[0]?.value as num).toInt();
    final sku = r[1]?.value?.toString();
    final qty = (r[2]?.value as num?)?.toInt() ?? 0;
    final price = (r[3]?.value as num?)?.toDouble() ?? 0.0;
    if (sku == null || sku.isEmpty || qty <= 0) continue;

    final prod = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
    int productId;
    if (prod.isEmpty) {
      productId = await db.insert('products', {
        'sku': sku,
        'name': 'SKU $sku',
        'default_sale_price': price,
        'last_purchase_price': 0.0,
        'stock': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      if (productId == 0) {
        final again = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
        productId = again.first['id'] as int;
      }
    } else {
      productId = prod.first['id'] as int;
    }

    await db.insert('sale_items', {
      'sale_id': idMap[oldSale],
      'product_id': productId,
      'sku': sku,
      'quantity': qty,
      'unit_price': price,
    });
  }
}

Future<void> importPurchasesXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) throw 'No se eligió archivo .xlsx';

  final db = await DatabaseHelper.instance.db;
  final header = excel['purchases'];
  final items  = excel['purchase_items'];
  if (header.maxRows <= 1) throw 'La hoja "purchases" no tiene datos.';
  if (items.maxRows <= 1) throw 'La hoja "purchase_items" no tiene datos.';

  final idMap = <int, int>{};

  for (final r in header.rows.skip(1)) {
    final newId = await db.insert('purchases', {
      'supplier_id': (r[1]?.value as num?)?.toInt(),
      'folio': r[2]?.value?.toString(),
      'date': r[3]?.value?.toString(),
    });
    final oldId = (r[0]?.value as num).toInt();
    idMap[oldId] = newId;
  }

  for (final r in items.rows.skip(1)) {
    final oldPur = (r[0]?.value as num).toInt();
    final sku = r[1]?.value?.toString();
    final qty = (r[2]?.value as num?)?.toInt() ?? 0;
    final cost = (r[3]?.value as num?)?.toDouble() ?? 0.0;
    if (sku == null || sku.isEmpty || qty <= 0) continue;

    final prod = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
    int productId;
    if (prod.isEmpty) {
      productId = await db.insert('products', {
        'sku': sku,
        'name': 'SKU $sku',
        'last_purchase_price': cost,
        'default_sale_price': 0.0,
        'stock': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      if (productId == 0) {
        final again = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
        productId = again.first['id'] as int;
      }
    } else {
      productId = prod.first['id'] as int;
    }

    await db.insert('purchase_items', {
      'purchase_id': idMap[oldPur],
      'product_id': productId,
      'sku': sku,
      'quantity': qty,
      'unit_cost': cost,
    });

    await db.rawUpdate(
      'UPDATE products SET stock = stock + ?, last_purchase_price = ?, last_purchase_date = ? WHERE id = ?',
      [qty, cost, DateTime.now().toIso8601String(), productId],
    );
  }
}

Future<void> importProductsXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) throw 'No se eligió archivo .xlsx';

  final db = await DatabaseHelper.instance.db;
  final sh = excel['products'];
  if (sh.maxRows <= 1) throw 'La hoja "products" no tiene datos.';

  for (final r in sh.rows.skip(1)) {
    final sku = r[1]?.value?.toString();
    if (sku == null || sku.isEmpty) continue;

    final name = r[2]?.value?.toString();
    final category = r[3]?.value?.toString();
    final defaultSale = (r[4]?.value as num?)?.toDouble() ?? 0.0;
    final lastPurchase = (r[5]?.value as num?)?.toDouble() ?? 0.0;
    final stock = (r[6]?.value as num?)?.toInt() ?? 0;
    final lastPurchaseDate = r[7]?.value?.toString();

    final exists = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
    if (exists.isEmpty) {
      await db.insert('products', {
        'sku': sku,
        'name': name ?? 'SKU $sku',
        'category': category,
        'default_sale_price': defaultSale,
        'last_purchase_price': lastPurchase,
        'stock': stock,
        'last_purchase_date': lastPurchaseDate,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.update(
        'products',
        {
          'name': name ?? exists.first['name'],
          'category': category,
          'default_sale_price': defaultSale,
          'last_purchase_price': lastPurchase,
          'stock': stock,
          'last_purchase_date': lastPurchaseDate,
        },
        where: 'sku = ?',
        whereArgs: [sku],
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
}

Future<void> importClientsXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) throw 'No se eligió archivo .xlsx';

  final db = await DatabaseHelper.instance.db;
  final sh = excel['customers'];
  if (sh.maxRows <= 1) throw 'La hoja "customers" no tiene datos.';

  for (final r in sh.rows.skip(1)) {
    final phone = r[0]?.value?.toString();
    if (phone == null || phone.isEmpty) continue;

    final name = r[1]?.value?.toString();
    final address = r[2]?.value?.toString();

    final exists = await db.query('customers', where: 'phone = ?', whereArgs: [phone], limit: 1);
    if (exists.isEmpty) {
      await db.insert('customers', {
        'phone': phone,
        'name': name,
        'address': address,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.update(
        'customers',
        {'name': name, 'address': address},
        where: 'phone = ?',
        whereArgs: [phone],
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
}

Future<void> importSuppliersXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) throw 'No se eligió archivo .xlsx';

  final db = await DatabaseHelper.instance.db;
  final sh = excel['suppliers'];
  if (sh.maxRows <= 1) throw 'La hoja "suppliers" no tiene datos.';

  for (final r in sh.rows.skip(1)) {
    final phone = r[0]?.value?.toString();
    if (phone == null || phone.isEmpty) continue;

    final name = r[1]?.value?.toString();
    final address = r[2]?.value?.toString();

    final exists = await db.query('suppliers', where: 'phone = ?', whereArgs: [phone], limit: 1);
    if (exists.isEmpty) {
      await db.insert('suppliers', {
        'phone': phone,
        'name': name,
        'address': address,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.update(
        'suppliers',
        {'name': name, 'address': address},
        where: 'phone = ?',
        whereArgs: [phone],
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
}