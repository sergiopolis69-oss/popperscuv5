import 'dart:typed_data';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

CellValue? _cv(dynamic v) {
  if (v == null) return null;
  if (v is num) return DoubleCellValue(v.toDouble());
  if (v is bool) return BoolCellValue(v);
  return TextCellValue(v.toString());
}

Future<void> _ensureStoragePerms() async {
  await [Permission.storage, Permission.manageExternalStorage].request();
}

/// Guarda el Excel en la carpeta pública de Descargas (no en sandbox).
Future<String> _saveExcelToDownloads(Excel excel, String filename) async {
  await _ensureStoragePerms();
  final bytes = excel.save();
  if (bytes == null) throw Exception('No se pudo generar el archivo XLSX');

  Directory? downloadsDir;
  try {
    downloadsDir = await getDownloadsDirectory(); // en algunos Android 11+ devuelve null
  } catch (_) {}

  // Fallback manual si el anterior no existe
  downloadsDir ??= Directory('/storage/emulated/0/Download');

  final filePath = '${downloadsDir.path}/$filename.xlsx';
  final file = File(filePath);
  await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);

  return file.path;
}

/* ========================= EXPORTS ========================= */

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