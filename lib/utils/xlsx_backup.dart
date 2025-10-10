import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart'
    show Excel, Sheet, CellValue, TextCellValue, DoubleCellValue;
import 'package:file_saver/file_saver.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// ============================================================================
/// Helper: acceso a DB
/// ============================================================================

Future<Database> _openDb() async {
  // Ajusta el nombre si tu DB se llama distinto.
  final path = p.join(await getDatabasesPath(), 'app.db');
  return openDatabase(path);
}

/// Helpers de celdas para Excel (nunca uses String/Object? directo)
CellValue _text(String? s) => TextCellValue(s ?? '');
CellValue _num(num? v) => v == null ? TextCellValue('') : DoubleCellValue(v.toDouble());

/// Guardar en Descargas usando file_saver (sin permisos legacy)
Future<String> _saveToDownloads({
  required String baseName, // sin extensión
  required List<int> bytes,
}) async {
  final path = await FileSaver.instance.saveFile(
    name: baseName,
    ext: 'xlsx',
    // MimeType.xlsx NO existe en algunas versiones; usa other.
    mimeType: MimeType.other,
    bytes: Uint8List.fromList(bytes),
  );
  return path;
}

/// Crea un Excel con una sola hoja y devuelve bytes
List<int> _excelToBytes(Excel excel) {
  final data = excel.save();
  if (data == null) {
    throw Exception('No se pudo generar el archivo XLSX');
  }
  return data;
}

/// ============================================================================
/// EXPORTS
/// ============================================================================

Future<String> exportProductsXlsx() async {
  final db = await _openDb();

  // Lee productos
  final rows = await db.rawQuery('''
    SELECT sku, name, category, default_sale_price, last_purchase_price, last_purchase_date, stock
    FROM products
    ORDER BY name COLLATE NOCASE ASC
  ''');

  final excel = Excel.createExcel();
  final Sheet sh = excel['products'];
  // Header
  sh.appendRow([
    _text('sku'),
    _text('name'),
    _text('category'),
    _text('default_sale_price'),
    _text('last_purchase_price'),
    _text('last_purchase_date'),
    _text('stock'),
  ]);
  // Data
  for (final r in rows) {
    sh.appendRow([
      _text(r['sku']?.toString()),
      _text(r['name']?.toString()),
      _text(r['category']?.toString()),
      _num(r['default_sale_price'] as num?),
      _num(r['last_purchase_price'] as num?),
      _text(r['last_purchase_date']?.toString()),
      _num(r['stock'] as num?),
    ]);
  }

  final bytes = _excelToBytes(excel);
  return _saveToDownloads(baseName: 'productos', bytes: bytes);
}

Future<String> exportClientsXlsx() async {
  final db = await _openDb();
  final rows = await db.rawQuery('''
    SELECT phone AS phone_id, name, address
    FROM customers
    ORDER BY name COLLATE NOCASE ASC
  ''');

  final excel = Excel.createExcel();
  final Sheet sh = excel['customers'];
  sh.appendRow([_text('phone_id'), _text('name'), _text('address')]);
  for (final r in rows) {
    sh.appendRow([
      _text(r['phone']?.toString()),
      _text(r['name']?.toString()),
      _text(r['address']?.toString()),
    ]);
  }

  final bytes = _excelToBytes(excel);
  return _saveToDownloads(baseName: 'clientes', bytes: bytes);
}

Future<String> exportSuppliersXlsx() async {
  final db = await _openDb();
  final rows = await db.rawQuery('''
    SELECT id, name, phone, address
    FROM suppliers
    ORDER BY name COLLATE NOCASE ASC
  ''');

  final excel = Excel.createExcel();
  final Sheet sh = excel['suppliers'];
  sh.appendRow([_text('id'), _text('name'), _text('phone'), _text('address')]);
  for (final r in rows) {
    sh.appendRow([
      _text(r['id']?.toString()),
      _text(r['name']?.toString()),
      _text(r['phone']?.toString()),
      _text(r['address']?.toString()),
    ]);
  }

  final bytes = _excelToBytes(excel);
  return _saveToDownloads(baseName: 'proveedores', bytes: bytes);
}

/// Ventas: encabezado + items con SKU
Future<String> exportSalesXlsx() async {
  final db = await _openDb();

  final sales = await db.rawQuery('''
    SELECT id, date, customer_phone, payment_method, place, shipping_cost, discount
    FROM sales
    ORDER BY date ASC
  ''');

  final items = await db.rawQuery('''
    SELECT sale_id, product_sku, product_name, quantity, unit_price
    FROM sale_items
    ORDER BY sale_id ASC
  ''');

  final excel = Excel.createExcel();
  final Sheet shSales = excel['sales'];
  final Sheet shItems = excel['sale_items'];

  shSales.appendRow([
    _text('sale_id'),
    _text('date'),
    _text('customer_phone'),
    _text('payment_method'),
    _text('place'),
    _num(null), // shipping_cost
    _num(null), // discount
  ]);
  // Corrige header numérico con textos en columnas anteriores
  shSales.removeRow(1);
  shSales.appendRow([
    _text('sale_id'),
    _text('date'),
    _text('customer_phone'),
    _text('payment_method'),
    _text('place'),
    _text('shipping_cost'),
    _text('discount'),
  ]);

  for (final s in sales) {
    shSales.appendRow([
      _text(s['id']?.toString()),
      _text(s['date']?.toString()),
      _text(s['customer_phone']?.toString()),
      _text(s['payment_method']?.toString()),
      _text(s['place']?.toString()),
      _num(s['shipping_cost'] as num?),
      _num(s['discount'] as num?),
    ]);
  }

  shItems.appendRow([
    _text('sale_id'),
    _text('product_sku'),
    _text('product_name'),
    _text('quantity'),
    _text('unit_price'),
  ]);

  for (final it in items) {
    shItems.appendRow([
      _text(it['sale_id']?.toString()),
      _text(it['product_sku']?.toString()),
      _text(it['product_name']?.toString()),
      _num(it['quantity'] as num?),
      _num(it['unit_price'] as num?),
    ]);
  }

  final bytes = _excelToBytes(excel);
  return _saveToDownloads(baseName: 'ventas', bytes: bytes);
}

/// Compras: encabezado + items con SKU
Future<String> exportPurchasesXlsx() async {
  final db = await _openDb();

  final purchases = await db.rawQuery('''
    SELECT id, folio, date, supplier_id
    FROM purchases
    ORDER BY date ASC
  ''');

  final items = await db.rawQuery('''
    SELECT purchase_id, product_sku, product_name, quantity, unit_cost
    FROM purchase_items
    ORDER BY purchase_id ASC
  ''');

  final excel = Excel.createExcel();
  final Sheet shP = excel['purchases'];
  final Sheet shI = excel['purchase_items'];

  shP.appendRow([
    _text('purchase_id'),
    _text('folio'),
    _text('date'),
    _text('supplier_id'),
  ]);

  for (final pRow in purchases) {
    shP.appendRow([
      _text(pRow['id']?.toString()),
      _text(pRow['folio']?.toString()),
      _text(pRow['date']?.toString()),
      _text(pRow['supplier_id']?.toString()),
    ]);
  }

  shI.appendRow([
    _text('purchase_id'),
    _text('product_sku'),
    _text('product_name'),
    _text('quantity'),
    _text('unit_cost'),
  ]);

  for (final it in items) {
    shI.appendRow([
      _text(it['purchase_id']?.toString()),
      _text(it['product_sku']?.toString()),
      _text(it['product_name']?.toString()),
      _num(it['quantity'] as num?),
      _num(it['unit_cost'] as num?),
    ]);
  }

  final bytes = _excelToBytes(excel);
  return _saveToDownloads(baseName: 'compras', bytes: bytes);
}

/// ============================================================================
/// IMPORTS
/// ============================================================================

Future<void> importProductsXlsx(Uint8List bytes) async {
  final db = await _openDb();
  final excel = Excel.decodeBytes(bytes);
  final sh = excel.sheets['products'];
  if (sh == null) throw Exception('Hoja "products" no encontrada');

  // Espera header: sku, name, category, default_sale_price, last_purchase_price, last_purchase_date, stock
  final rows = sh.rows;
  if (rows.isEmpty) return;
  final start = 1; // fila 0 = headers

  final batch = db.batch();
  for (int i = start; i < rows.length; i++) {
    final r = rows[i];
    if (r.isEmpty) continue;

    final sku = (r[0]?.value)?.toString().trim();
    final name = (r[1]?.value)?.toString().trim();
    if (sku == null || sku.isEmpty) continue; // no agregues sin SKU
    final category = (r[2]?.value)?.toString().trim();
    final dsp = num.tryParse((r[3]?.value)?.toString() ?? '');
    final lpp = num.tryParse((r[4]?.value)?.toString() ?? '');
    final lpd = (r[5]?.value)?.toString();
    final stock = num.tryParse((r[6]?.value)?.toString() ?? '');

    batch.insert(
      'products',
      {
        'sku': sku,
        'name': name,
        'category': category,
        'default_sale_price': dsp,
        'last_purchase_price': lpp,
        'last_purchase_date': lpd,
        'stock': stock,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  await batch.commit(noResult: true);
}

Future<void> importClientsXlsx(Uint8List bytes) async {
  final db = await _openDb();
  final excel = Excel.decodeBytes(bytes);
  final sh = excel.sheets['customers'];
  if (sh == null) throw Exception('Hoja "customers" no encontrada');

  final rows = sh.rows;
  if (rows.isEmpty) return;
  final start = 1;

  final batch = db.batch();
  for (int i = start; i < rows.length; i++) {
    final r = rows[i];
    if (r.isEmpty) continue;

    final phone = (r[0]?.value)?.toString().trim();
    if (phone == null || phone.isEmpty) continue; // id = phone
    final name = (r[1]?.value)?.toString();
    final address = (r[2]?.value)?.toString();

    batch.insert(
      'customers',
      {'phone': phone, 'name': name, 'address': address},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  await batch.commit(noResult: true);
}

Future<void> importSuppliersXlsx(Uint8List bytes) async {
  final db = await _openDb();
  final excel = Excel.decodeBytes(bytes);
  final sh = excel.sheets['suppliers'];
  if (sh == null) throw Exception('Hoja "suppliers" no encontrada');

  final rows = sh.rows;
  if (rows.isEmpty) return;
  final start = 1;

  final batch = db.batch();
  for (int i = start; i < rows.length; i++) {
    final r = rows[i];
    if (r.isEmpty) continue;

    final idStr = (r[0]?.value)?.toString();
    final id = int.tryParse(idStr ?? '');
    final name = (r[1]?.value)?.toString();
    final phone = (r[2]?.value)?.toString();
    final address = (r[3]?.value)?.toString();

    if (id == null) continue;

    batch.insert(
      'suppliers',
      {'id': id, 'name': name, 'phone': phone, 'address': address},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  await batch.commit(noResult: true);
}

Future<void> importSalesXlsx(Uint8List bytes) async {
  final db = await _openDb();
  final excel = Excel.decodeBytes(bytes);
  final shSales = excel.sheets['sales'];
  final shItems = excel.sheets['sale_items'];
  if (shSales == null || shItems == null) {
    throw Exception('Hojas "sales" y/o "sale_items" no encontradas');
  }

  final rowsS = shSales.rows;
  final rowsI = shItems.rows;
  if (rowsS.isEmpty || rowsI.isEmpty) return;

  final batch = db.batch();

  // Ventas
  for (int i = 1; i < rowsS.length; i++) {
    final r = rowsS[i];
    if (r.isEmpty) continue;

    final id = int.tryParse((r[0]?.value)?.toString() ?? '');
    final date = (r[1]?.value)?.toString();
    final phone = (r[2]?.value)?.toString();
    final method = (r[3]?.value)?.toString();
    final place = (r[4]?.value)?.toString();
    final ship = num.tryParse((r[5]?.value)?.toString() ?? '');
    final disc = num.tryParse((r[6]?.value)?.toString() ?? '');

    if (id == null) continue;

    batch.insert(
      'sales',
      {
        'id': id,
        'date': date,
        'customer_phone': phone,
        'payment_method': method,
        'place': place,
        'shipping_cost': ship,
        'discount': disc,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Items (valida SKU existente)
  for (int i = 1; i < rowsI.length; i++) {
    final r = rowsI[i];
    if (r.isEmpty) continue;

    final saleId = int.tryParse((r[0]?.value)?.toString() ?? '');
    final sku = (r[1]?.value)?.toString();
    final name = (r[2]?.value)?.toString();
    final qty = num.tryParse((r[3]?.value)?.toString() ?? '');
    final price = num.tryParse((r[4]?.value)?.toString() ?? '');
    if (saleId == null || sku == null || sku.isEmpty) continue;

    final prod = await db.rawQuery('SELECT sku FROM products WHERE sku = ?', [sku]);
    if (prod.isEmpty) continue; // omite item si SKU no existe

    batch.insert(
      'sale_items',
      {
        'sale_id': saleId,
        'product_sku': sku,
        'product_name': name,
        'quantity': qty,
        'unit_price': price,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  await batch.commit(noResult: true);
}

Future<void> importPurchasesXlsx(Uint8List bytes) async {
  final db = await _openDb();
  final excel = Excel.decodeBytes(bytes);
  final shP = excel.sheets['purchases'];
  final shI = excel.sheets['purchase_items'];
  if (shP == null || shI == null) {
    throw Exception('Hojas "purchases" y/o "purchase_items" no encontradas');
  }

  final rowsP = shP.rows;
  final rowsI = shI.rows;
  if (rowsP.isEmpty || rowsI.isEmpty) return;

  final batch = db.batch();

  for (int i = 1; i < rowsP.length; i++) {
    final r = rowsP[i];
    if (r.isEmpty) continue;

    final id = int.tryParse((r[0]?.value)?.toString() ?? '');
    final folio = (r[1]?.value)?.toString();
    final date = (r[2]?.value)?.toString();
    final supplierId = int.tryParse((r[3]?.value)?.toString() ?? '');

    if (id == null) continue;

    batch.insert(
      'purchases',
      {
        'id': id,
        'folio': folio,
        'date': date,
        'supplier_id': supplierId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  for (int i = 1; i < rowsI.length; i++) {
    final r = rowsI[i];
    if (r.isEmpty) continue;

    final purchaseId = int.tryParse((r[0]?.value)?.toString() ?? '');
    final sku = (r[1]?.value)?.toString();
    final name = (r[2]?.value)?.toString();
    final qty = num.tryParse((r[3]?.value)?.toString() ?? '');
    final cost = num.tryParse((r[4]?.value)?.toString() ?? '');
    if (purchaseId == null || sku == null || sku.isEmpty) continue;

    final prod = await db.rawQuery('SELECT sku FROM products WHERE sku = ?', [sku]);
    if (prod.isEmpty) continue;

    batch.insert(
      'purchase_items',
      {
        'purchase_id': purchaseId,
        'product_sku': sku,
        'product_name': name,
        'quantity': qty,
        'unit_cost': cost,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  await batch.commit(noResult: true);
}