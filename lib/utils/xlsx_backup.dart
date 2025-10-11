// lib/utils/xlsx_backup.dart
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:sqflite/sqflite.dart' show Database, ConflictAlgorithm;
import 'package:popperscuv5/data/db.dart' show AppDb; // Ajusta si tu singleton difiere.

/// ----------------------
/// Helpers de DB/Excel
/// ----------------------

Future<Database> _db() async => AppDb.instance.database;

// celdas helper
CellValue _txt(Object? v) => TextCellValue(v?.toString() ?? '');
CellValue _num(num? v) => v == null ? TextCellValue('') : DoubleCellValue(v.toDouble());

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  // Excel suele venir YYYY-MM-DD o serial date convertido a texto
  // Intento robusto:
  try {
    return DateTime.parse(s);
  } catch (_) {
    return null;
  }
}

String _toIso(DateTime? d) => d == null ? '' : d.toIso8601String();

Future<String> _saveXlsxBytes(String fileName, List<int> bytes) async {
  final res = await FileSaver.instance.saveFile(
    name: fileName,
    bytes: Uint8List.fromList(bytes),
    ext: 'xlsx',
    mimeType: MimeType.microsoftExcelOpenXml,
  );
  // `res` puede ser ruta o content-uri, lo devolvemos como cadena
  return res;
}

/// ----------------------
/// EXPORTACIONES
/// ----------------------

Future<String> exportProductsXlsx() async {
  final db = await _db();
  final rows = await db.rawQuery('''
    SELECT sku, name, category, default_sale_price, last_purchase_price, last_purchase_date, stock
    FROM products
    ORDER BY name COLLATE NOCASE
  ''');

  final excel = Excel.createExcel();
  final sh = excel['products'];

  // encabezados
  sh.appendRow([
    TextCellValue('sku'),
    TextCellValue('name'),
    TextCellValue('category'),
    TextCellValue('default_sale_price'),
    TextCellValue('last_purchase_price'),
    TextCellValue('last_purchase_date'),
    TextCellValue('stock'),
  ]);

  for (final r in rows) {
    sh.appendRow([
      _txt(r['sku']),
      _txt(r['name']),
      _txt(r['category']),
      _num((r['default_sale_price'] as num?)?.toDouble()),
      _num((r['last_purchase_price'] as num?)?.toDouble()),
      _txt(r['last_purchase_date']),
      _num((r['stock'] as num?)?.toDouble()),
    ]);
  }

  return _saveXlsxBytes('productos', excel.encode()!);
}

Future<String> exportClientsXlsx() async {
  final db = await _db();
  final rows = await db.rawQuery('''
    SELECT phone AS phone_id, name, address
    FROM customers
    ORDER BY name COLLATE NOCASE
  ''');

  final excel = Excel.createExcel();
  final sh = excel['clients'];

  sh.appendRow([
    TextCellValue('phone_id'),
    TextCellValue('name'),
    TextCellValue('address'),
  ]);

  for (final r in rows) {
    sh.appendRow([
      _txt(r['phone_id']),
      _txt(r['name']),
      _txt(r['address']),
    ]);
  }

  return _saveXlsxBytes('clientes', excel.encode()!);
}

Future<String> exportSuppliersXlsx() async {
  final db = await _db();
  final rows = await db.rawQuery('''
    SELECT id, name, phone, address
    FROM suppliers
    ORDER BY name COLLATE NOCASE
  ''');

  final excel = Excel.createExcel();
  final sh = excel['suppliers'];

  sh.appendRow([
    TextCellValue('id'),
    TextCellValue('name'),
    TextCellValue('phone'),
    TextCellValue('address'),
  ]);

  for (final r in rows) {
    sh.appendRow([
      _txt(r['id']),
      _txt(r['name']),
      _txt(r['phone']),
      _txt(r['address']),
    ]);
  }

  return _saveXlsxBytes('proveedores', excel.encode()!);
}

Future<String> exportSalesXlsx() async {
  final db = await _db();

  final sales = await db.rawQuery('''
    SELECT s.id, s.date, s.customer_phone, s.payment_method, s.place, s.shipping_cost, s.discount
    FROM sales s
    ORDER BY s.date DESC, s.id DESC
  ''');

  final items = await db.rawQuery('''
    SELECT si.sale_id, si.product_sku, p.name AS product_name, si.quantity, si.unit_price
    FROM sale_items si
    LEFT JOIN products p ON p.sku = si.product_sku
    ORDER BY si.sale_id
  ''');

  final excel = Excel.createExcel();
  final shSales = excel['sales'];
  final shItems = excel['sale_items'];

  shSales.appendRow([
    TextCellValue('sale_id'),
    TextCellValue('date'),
    TextCellValue('customer_phone'),
    TextCellValue('payment_method'),
    TextCellValue('place'),
    TextCellValue('shipping_cost'),
    TextCellValue('discount'),
  ]);

  for (final s in sales) {
    shSales.appendRow([
      _txt(s['id']),
      _txt(s['date']),
      _txt(s['customer_phone']),
      _txt(s['payment_method']),
      _txt(s['place']),
      _num((s['shipping_cost'] as num?)?.toDouble()),
      _num((s['discount'] as num?)?.toDouble()),
    ]);
  }

  shItems.appendRow([
    TextCellValue('sale_id'),
    TextCellValue('product_sku'),
    TextCellValue('product_name'),
    TextCellValue('quantity'),
    TextCellValue('unit_price'),
  ]);

  for (final it in items) {
    shItems.appendRow([
      _txt(it['sale_id']),
      _txt(it['product_sku']),
      _txt(it['product_name']),
      _num((it['quantity'] as num?)?.toDouble()),
      _num((it['unit_price'] as num?)?.toDouble()),
    ]);
  }

  return _saveXlsxBytes('ventas', excel.encode()!);
}

Future<String> exportPurchasesXlsx() async {
  final db = await _db();

  final purchases = await db.rawQuery('''
    SELECT p.id, p.folio, p.date, p.supplier_id
    FROM purchases p
    ORDER BY p.date DESC, p.id DESC
  ''');

  final items = await db.rawQuery('''
    SELECT pi.purchase_id, pi.product_sku, pr.name AS product_name, pi.quantity, pi.unit_cost
    FROM purchase_items pi
    LEFT JOIN products pr ON pr.sku = pi.product_sku
    ORDER BY pi.purchase_id
  ''');

  final excel = Excel.createExcel();
  final shP = excel['purchases'];
  final shI = excel['purchase_items'];

  shP.appendRow([
    TextCellValue('purchase_id'),
    TextCellValue('folio'),
    TextCellValue('date'),
    TextCellValue('supplier_id'),
  ]);

  for (final p in purchases) {
    shP.appendRow([
      _txt(p['id']),
      _txt(p['folio']),
      _txt(p['date']),
      _txt(p['supplier_id']),
    ]);
  }

  shI.appendRow([
    TextCellValue('purchase_id'),
    TextCellValue('product_sku'),
    TextCellValue('product_name'),
    TextCellValue('quantity'),
    TextCellValue('unit_cost'),
  ]);

  for (final it in items) {
    shI.appendRow([
      _txt(it['purchase_id']),
      _txt(it['product_sku']),
      _txt(it['product_name']),
      _num((it['quantity'] as num?)?.toDouble()),
      _num((it['unit_cost'] as num?)?.toDouble()),
    ]);
  }

  return _saveXlsxBytes('compras', excel.encode()!);
}

/// ----------------------
/// IMPORTACIONES
/// ----------------------

Future<void> importProductsXlsx(Uint8List bytes) async {
  final db = await _db();
  final ex = Excel.decodeBytes(bytes);
  final sh = ex['products'];
  if (sh.maxRows < 2) return;

  // Espera encabezados:
  // sku,name,category,default_sale_price,last_purchase_price,last_purchase_date,stock
  await db.transaction((txn) async {
    for (int r = 1; r < sh.maxRows; r++) {
      final row = sh.row(r);
      String sku = (row.elementAtOrNull(0)?.value ?? '').toString().trim();
      if (sku.isEmpty) continue; // SKU obligatorio

      final name = (row.elementAtOrNull(1)?.value ?? '').toString().trim();
      final category = (row.elementAtOrNull(2)?.value ?? '').toString().trim();
      final dsp = num.tryParse((row.elementAtOrNull(3)?.value ?? '').toString());
      final lpp = num.tryParse((row.elementAtOrNull(4)?.value ?? '').toString());
      final lpd = _parseDate(row.elementAtOrNull(5)?.value);
      final stock = num.tryParse((row.elementAtOrNull(6)?.value ?? '').toString());

      await txn.insert('products', {
        'sku': sku,
        'name': name,
        'category': category,
        'default_sale_price': dsp,
        'last_purchase_price': lpp,
        'last_purchase_date': _toIso(lpd),
        'stock': stock ?? 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}

Future<void> importClientsXlsx(Uint8List bytes) async {
  final db = await _db();
  final ex = Excel.decodeBytes(bytes);
  final sh = ex['clients'];
  if (sh.maxRows < 2) return;

  // phone_id,name,address
  await db.transaction((txn) async {
    for (int r = 1; r < sh.maxRows; r++) {
      final row = sh.row(r);
      final phone = (row.elementAtOrNull(0)?.value ?? '').toString().trim();
      if (phone.isEmpty) continue; // obligatorio

      final name = (row.elementAtOrNull(1)?.value ?? '').toString().trim();
      final address = (row.elementAtOrNull(2)?.value ?? '').toString().trim();

      await txn.insert('customers', {
        'phone': phone,
        'name': name,
        'address': address,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}

Future<void> importSuppliersXlsx(Uint8List bytes) async {
  final db = await _db();
  final ex = Excel.decodeBytes(bytes);
  final sh = ex['suppliers'];
  if (sh.maxRows < 2) return;

  // id,name,phone,address
  await db.transaction((txn) async {
    for (int r = 1; r < sh.maxRows; r++) {
      final row = sh.row(r);
      final id = (row.elementAtOrNull(0)?.value ?? '').toString().trim();
      if (id.isEmpty) continue;

      final name = (row.elementAtOrNull(1)?.value ?? '').toString().trim();
      final phone = (row.elementAtOrNull(2)?.value ?? '').toString().trim();
      final address = (row.elementAtOrNull(3)?.value ?? '').toString().trim();

      await txn.insert('suppliers', {
        'id': id,
        'name': name,
        'phone': phone,
        'address': address,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}

Future<void> importSalesXlsx(Uint8List bytes) async {
  final db = await _db();
  final ex = Excel.decodeBytes(bytes);
  final shSales = ex['sales'];
  final shItems = ex['sale_items'];
  if (shSales.maxRows < 2) return;

  // sales: sale_id,date,customer_phone,payment_method,place,shipping_cost,discount
  // sale_items: sale_id,product_sku,product_name,quantity,unit_price
  await db.transaction((txn) async {
    // Primero ventas (cabeceras)
    for (int r = 1; r < shSales.maxRows; r++) {
      final row = shSales.row(r);
      final id = (row.elementAtOrNull(0)?.value ?? '').toString().trim();
      if (id.isEmpty) continue;

      final date = _parseDate(row.elementAtOrNull(1)?.value);
      final phone = (row.elementAtOrNull(2)?.value ?? '').toString().trim();
      final pm = (row.elementAtOrNull(3)?.value ?? '').toString().trim();
      final place = (row.elementAtOrNull(4)?.value ?? '').toString().trim();
      final shipping = num.tryParse((row.elementAtOrNull(5)?.value ?? '').toString()) ?? 0;
      final discount = num.tryParse((row.elementAtOrNull(6)?.value ?? '').toString()) ?? 0;

      await txn.insert('sales', {
        'id': id,
        'date': _toIso(date) ,
        'customer_phone': phone,
        'payment_method': pm,
        'place': place,
        'shipping_cost': shipping,
        'discount': discount,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // Luego items
    if (shItems.maxRows >= 2) {
      for (int r = 1; r < shItems.maxRows; r++) {
        final row = shItems.row(r);
        final saleId = (row.elementAtOrNull(0)?.value ?? '').toString().trim();
        final sku = (row.elementAtOrNull(1)?.value ?? '').toString().trim();
        if (saleId.isEmpty || sku.isEmpty) continue; // SKU obligatorio

        final qty = num.tryParse((row.elementAtOrNull(3)?.value ?? '').toString()) ?? 0;
        final unitPrice = num.tryParse((row.elementAtOrNull(4)?.value ?? '').toString()) ?? 0;

        // Verificar que el producto existe (seguridad)
        final prod = await txn.query('products', where: 'sku=?', whereArgs: [sku], limit: 1);
        if (prod.isEmpty) continue;

        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_sku': sku,
          'quantity': qty,
          'unit_price': unitPrice,
        });

        // Baja inventario
        await txn.rawUpdate(
          'UPDATE products SET stock = COALESCE(stock,0) - ? WHERE sku = ?',
          [qty, sku],
        );
      }
    }
  });
}

Future<void> importPurchasesXlsx(Uint8List bytes) async {
  final db = await _db();
  final ex = Excel.decodeBytes(bytes);
  final shP = ex['purchases'];
  final shI = ex['purchase_items'];
  if (shP.maxRows < 2) return;

  // purchases: purchase_id,folio,date,supplier_id
  // purchase_items: purchase_id,product_sku,product_name,quantity,unit_cost
  await db.transaction((txn) async {
    for (int r = 1; r < shP.maxRows; r++) {
      final row = shP.row(r);
      final id = (row.elementAtOrNull(0)?.value ?? '').toString().trim();
      if (id.isEmpty) continue;

      final folio = (row.elementAtOrNull(1)?.value ?? '').toString().trim();
      final date = _parseDate(row.elementAtOrNull(2)?.value);
      final supplierId = (row.elementAtOrNull(3)?.value ?? '').toString().trim();

      await txn.insert('purchases', {
        'id': id,
        'folio': folio,
        'date': _toIso(date),
        'supplier_id': supplierId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    if (shI.maxRows >= 2) {
      for (int r = 1; r < shI.maxRows; r++) {
        final row = shI.row(r);
        final pid = (row.elementAtOrNull(0)?.value ?? '').toString().trim();
        final sku = (row.elementAtOrNull(1)?.value ?? '').toString().trim();
        if (pid.isEmpty || sku.isEmpty) continue;

        final qty = num.tryParse((row.elementAtOrNull(3)?.value ?? '').toString()) ?? 0;
        final unitCost = num.tryParse((row.elementAtOrNull(4)?.value ?? '').toString()) ?? 0;

        // Debe existir el producto
        final prod = await txn.query('products', where: 'sku=?', whereArgs: [sku], limit: 1);
        if (prod.isEmpty) continue;

        await txn.insert('purchase_items', {
          'purchase_id': pid,
          'product_sku': sku,
          'quantity': qty,
          'unit_cost': unitCost,
        });

        // Sube inventario
        await txn.rawUpdate(
          'UPDATE products SET stock = COALESCE(stock,0) + ?, '
          'last_purchase_price = ?, last_purchase_date = ? '
          'WHERE sku = ?',
          [qty, unitCost, _toIso(DateTime.now()), sku],
        );
      }
    }
  });
}