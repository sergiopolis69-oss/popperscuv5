import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

/* ===================== Helpers ===================== */

CellValue? _cv(dynamic v) {
  if (v == null) return null;
  if (v is num) return DoubleCellValue(v.toDouble());
  if (v is bool) return BoolCellValue(v);
  return TextCellValue(v.toString());
}

T? _getCell<T>(Data? cell) {
  if (cell == null) return null;
  final v = cell.value;
  if (v is TextCellValue) return (T == String ? v.value as T : v.value.toString() as T);
  if (v is DoubleCellValue) return (T == double ? v.value as T : v.value.toString() as T);
  if (v is IntCellValue) return (T == int ? v.value as T : v.value.toString() as T);
  if (v is BoolCellValue) return (T == bool ? v.value as T : v.value.toString() as T);
  return v as T?;
}

Future<void> _ensureStoragePerms() async {
  await [Permission.storage, Permission.manageExternalStorage].request();
}

/// Guarda Excel en carpeta pública de Descargas.
Future<String> _saveExcelToDownloads(Excel excel, String filename) async {
  await _ensureStoragePerms();
  final bytes = excel.save();
  if (bytes == null) throw Exception('No se pudo generar XLSX');

  Directory? downloadsDir;
  try {
    downloadsDir = await getDownloadsDirectory(); // puede venir null en Android 11+
  } catch (_) {}
  downloadsDir ??= Directory('/storage/emulated/0/Download');

  final file = File('${downloadsDir.path}/$filename.xlsx');
  await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
  return file.path;
}

/* ===================== EXPORTS ===================== */

Future<String> exportClientsXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('customers', orderBy: 'name COLLATE NOCASE ASC');

  final excel = Excel.createExcel();
  final sh = excel['clientes'];
  sh.appendRow([
    TextCellValue('phone_id'),
    TextCellValue('name'),
    TextCellValue('address'),
  ]);
  for (final r in rows) {
    sh.appendRow([_cv(r['phone']), _cv(r['name']), _cv(r['address'])]);
  }
  return _saveExcelToDownloads(excel, 'clientes');
}

Future<String> exportSuppliersXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('suppliers', orderBy: 'name COLLATE NOCASE ASC');

  final excel = Excel.createExcel();
  final sh = excel['proveedores'];
  sh.appendRow([
    TextCellValue('id'),
    TextCellValue('name'),
    TextCellValue('phone'),
    TextCellValue('address'),
  ]);
  for (final r in rows) {
    sh.appendRow([_cv(r['id']), _cv(r['name']), _cv(r['phone']), _cv(r['address'])]);
  }
  return _saveExcelToDownloads(excel, 'proveedores');
}

Future<String> exportProductsXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('products', orderBy: 'name COLLATE NOCASE ASC');

  final excel = Excel.createExcel();
  final sh = excel['productos'];
  sh.appendRow([
    TextCellValue('id'),
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
      _cv(r['id']),
      _cv(r['sku']),
      _cv(r['name']),
      _cv(r['category']),
      _cv(r['default_sale_price']),
      _cv(r['last_purchase_price']),
      _cv(r['last_purchase_date']),
      _cv(r['stock']),
    ]);
  }
  return _saveExcelToDownloads(excel, 'productos');
}

Future<String> exportSalesXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.createExcel();

  final shSales = excel['ventas'];
  shSales.appendRow([
    TextCellValue('sale_id'),
    TextCellValue('date'),
    TextCellValue('customer_phone'),
    TextCellValue('payment_method'),
    TextCellValue('place'),
    TextCellValue('shipping_cost'),
    TextCellValue('discount'),
  ]);
  final sales = await db.rawQuery('''
    SELECT id, date, customer_phone, payment_method, place,
           CAST(IFNULL(shipping_cost,0) AS REAL) AS shipping_cost,
           CAST(IFNULL(discount,0) AS REAL) AS discount
    FROM sales ORDER BY date DESC
  ''');
  for (final s in sales) {
    shSales.appendRow([
      _cv(s['id']),
      _cv(s['date']),
      _cv(s['customer_phone']),
      _cv(s['payment_method']),
      _cv(s['place']),
      _cv(s['shipping_cost']),
      _cv(s['discount']),
    ]);
  }

  final shItems = excel['venta_items'];
  shItems.appendRow([
    TextCellValue('sale_id'),
    TextCellValue('product_sku'),
    TextCellValue('product_name'),
    TextCellValue('quantity'),
    TextCellValue('unit_price'),
  ]);
  final items = await db.rawQuery('''
    SELECT si.sale_id, p.sku AS product_sku, p.name AS product_name,
           CAST(si.quantity AS INTEGER) AS quantity,
           CAST(si.unit_price AS REAL) AS unit_price
    FROM sale_items si
    JOIN products p ON p.id = si.product_id
    ORDER BY si.sale_id DESC
  ''');
  for (final it in items) {
    shItems.appendRow([
      _cv(it['sale_id']),
      _cv(it['product_sku']),
      _cv(it['product_name']),
      _cv(it['quantity']),
      _cv(it['unit_price']),
    ]);
  }

  return _saveExcelToDownloads(excel, 'ventas');
}

Future<String> exportPurchasesXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.createExcel();

  final shP = excel['compras'];
  shP.appendRow([
    TextCellValue('purchase_id'),
    TextCellValue('folio'),
    TextCellValue('date'),
    TextCellValue('supplier_id'),
  ]);
  final purchases = await db.rawQuery('''
    SELECT id, folio, date, supplier_id
    FROM purchases ORDER BY date DESC
  ''');
  for (final p in purchases) {
    shP.appendRow([
      _cv(p['id']),
      _cv(p['folio']),
      _cv(p['date']),
      _cv(p['supplier_id']),
    ]);
  }

  final shI = excel['compra_items'];
  shI.appendRow([
    TextCellValue('purchase_id'),
    TextCellValue('product_sku'),
    TextCellValue('product_name'),
    TextCellValue('quantity'),
    TextCellValue('unit_cost'),
  ]);
  final items = await db.rawQuery('''
    SELECT pi.purchase_id, p.sku AS product_sku, p.name AS product_name,
           CAST(pi.quantity AS INTEGER) AS quantity,
           CAST(pi.unit_cost AS REAL) AS unit_cost
    FROM purchase_items pi
    JOIN products p ON p.id = pi.product_id
    ORDER BY pi.purchase_id DESC
  ''');
  for (final it in items) {
    shI.appendRow([
      _cv(it['purchase_id']),
      _cv(it['product_sku']),
      _cv(it['product_name']),
      _cv(it['quantity']),
      _cv(it['unit_cost']),
    ]);
  }

  return _saveExcelToDownloads(excel, 'compras');
}

/* ===================== IMPORTS ===================== */

Future<void> importClientsXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.decodeBytes(bytes);
  final sh = excel['clientes'];
  if (sh.maxRows <= 1) return;

  // Espera encabezados: phone_id, name, address
  for (var r = 1; r < sh.maxRows; r++) {
    final row = sh.row(r);
    final phone = _getCell<String>(row[0]);
    if (phone == null || phone.trim().isEmpty) continue;
    final name = _getCell<String>(row[1]) ?? '';
    final address = _getCell<String>(row[2]) ?? '';
    await db.insert('customers', {
      'phone': phone,
      'name': name,
      'address': address,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<void> importSuppliersXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.decodeBytes(bytes);
  final sh = excel['proveedores'];
  if (sh.maxRows <= 1) return;

  // Encabezados: id, name, phone, address
  for (var r = 1; r < sh.maxRows; r++) {
    final row = sh.row(r);
    final id = _getCell<String>(row[0]);
    if (id == null || id.trim().isEmpty) continue;
    await db.insert('suppliers', {
      'id': id,
      'name': _getCell<String>(row[1]) ?? '',
      'phone': _getCell<String>(row[2]) ?? '',
      'address': _getCell<String>(row[3]) ?? '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<void> importProductsXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.decodeBytes(bytes);
  final sh = excel['productos'];
  if (sh.maxRows <= 1) return;

  // Encabezados: id, sku, name, category, default_sale_price, last_purchase_price, last_purchase_date, stock
  for (var r = 1; r < sh.maxRows; r++) {
    final row = sh.row(r);
    final id = _getCell<int>(row[0]) ?? _getCell<String>(row[0]);
    final sku = _getCell<String>(row[1]);
    final name = _getCell<String>(row[2]);
    if ((sku == null || sku.isEmpty) && (name == null || name.isEmpty)) continue;

    await db.insert('products', {
      if (id != null) 'id': id,
      'sku': sku ?? '',
      'name': name ?? '',
      'category': _getCell<String>(row[3]) ?? '',
      'default_sale_price': double.tryParse((_getCell(row[4]) ?? '').toString()) ?? 0.0,
      'last_purchase_price': double.tryParse((_getCell(row[5]) ?? '').toString()) ?? 0.0,
      'last_purchase_date': _getCell<String>(row[6]) ?? '',
      'stock': int.tryParse((_getCell(row[7]) ?? '').toString()) ?? 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<void> importSalesXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.decodeBytes(bytes);
  final shSales = excel['ventas'];
  final shItems = excel['venta_items'];
  if (shSales.maxRows <= 1) return;

  // Insert ventas
  for (var r = 1; r < shSales.maxRows; r++) {
    final row = shSales.row(r);
    final id = _getCell<int>(row[0]) ?? int.tryParse((_getCell(row[0]) ?? '').toString());
    final date = _getCell<String>(row[1]);
    if (id == null || date == null) continue;

    await db.insert('sales', {
      'id': id,
      'date': date,
      'customer_phone': _getCell<String>(row[2]) ?? '',
      'payment_method': _getCell<String>(row[3]) ?? '',
      'place': _getCell<String>(row[4]) ?? '',
      'shipping_cost': double.tryParse((_getCell(row[5]) ?? '').toString()) ?? 0.0,
      'discount': double.tryParse((_getCell(row[6]) ?? '').toString()) ?? 0.0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Insert items (requiere SKU válido en products)
  if (shItems.maxRows > 1) {
    for (var r = 1; r < shItems.maxRows; r++) {
      final row = shItems.row(r);
      final saleId = _getCell<int>(row[0]) ?? int.tryParse((_getCell(row[0]) ?? '').toString());
      final sku = _getCell<String>(row[1]) ?? '';
      if (saleId == null || sku.isEmpty) continue;
      final prod = await db.query('products', where: 'sku=?', whereArgs: [sku], limit: 1);
      if (prod.isEmpty) continue;

      await db.insert('sale_items', {
        'sale_id': saleId,
        'product_id': prod.first['id'],
        'quantity': int.tryParse((_getCell(row[3]) ?? '').toString()) ?? 0,
        'unit_price': double.tryParse((_getCell(row[4]) ?? '').toString()) ?? 0.0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}

Future<void> importPurchasesXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.decodeBytes(bytes);
  final shP = excel['compras'];
  final shI = excel['compra_items'];
  if (shP.maxRows <= 1) return;

  for (var r = 1; r < shP.maxRows; r++) {
    final row = shP.row(r);
    final id = _getCell<int>(row[0]) ?? int.tryParse((_getCell(row[0]) ?? '').toString());
    final date = _getCell<String>(row[2]);
    if (id == null || date == null) continue;

    await db.insert('purchases', {
      'id': id,
      'folio': _getCell<String>(row[1]) ?? '',
      'date': date,
      'supplier_id': _getCell<String>(row[3]) ?? '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  if (shI.maxRows > 1) {
    for (var r = 1; r < shI.maxRows; r++) {
      final row = shI.row(r);
      final purchaseId = _getCell<int>(row[0]) ?? int.tryParse((_getCell(row[0]) ?? '').toString());
      final sku = _getCell<String>(row[1]) ?? '';
      if (purchaseId == null || sku.isEmpty) continue;
      final prod = await db.query('products', where: 'sku=?', whereArgs: [sku], limit: 1);
      if (prod.isEmpty) continue;

      await db.insert('purchase_items', {
        'purchase_id': purchaseId,
        'product_id': prod.first['id'],
        'quantity': int.tryParse((_getCell(row[3]) ?? '').toString()) ?? 0,
        'unit_cost': double.tryParse((_getCell(row[4]) ?? '').toString()) ?? 0.0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Actualiza último costo/fecha y stock
      await db.update(
        'products',
        {
          'last_purchase_price': double.tryParse((_getCell(row[4]) ?? '').toString()) ?? 0.0,
          'last_purchase_date': DateTime.now().toIso8601String(),
          'stock': (prod.first['stock'] as int? ?? 0) +
              (int.tryParse((_getCell(row[3]) ?? '').toString()) ?? 0),
        },
        where: 'id=?',
        whereArgs: [prod.first['id']],
      );
    }
  }
}