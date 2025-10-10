import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
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

/// Pide permisos de almacenamiento (compatibilidad Android 10–14)
Future<void> _ensureStoragePerms() async {
  final req = await [
    Permission.storage,
    Permission.manageExternalStorage,
  ].request();

  final ok = (req[Permission.manageExternalStorage]?.isGranted ?? false) ||
      (req[Permission.storage]?.isGranted ?? false);
  if (!ok) throw Exception('Permiso de almacenamiento denegado');
}

/// Obtiene la carpeta pública de Descargas (no privada de la app)
Directory _publicDownloadsDir() {
  final d1 = Directory('/storage/emulated/0/Download');
  if (d1.existsSync()) return d1;
  final d2 = Directory('/sdcard/Download');
  if (d2.existsSync()) return d2;
  final root = Directory('/storage/emulated/0');
  final d3 = Directory('${root.path}/Download');
  if (!d3.existsSync()) d3.createSync(recursive: true);
  return d3;
}

/// Guarda Excel en carpeta pública de Descargas
Future<String> _saveExcelToDownloads(Excel excel, String filename) async {
  await _ensureStoragePerms();
  final bytes = excel.save();
  if (bytes == null) throw Exception('No se pudo generar XLSX');
  final downloads = _publicDownloadsDir();
  final file = File('${downloads.path}/$filename.xlsx');
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
    SELECT id, folio, date, supplier_id FROM purchases ORDER BY date DESC
  ''');
  for (final p in purchases) {
    shP.appendRow([
      _cv(p['id']),
      _cv(p['folio']),
      _cv(p['date']),
      _cv(p['supplier_id']),
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
  for (var r = 1; r < sh.maxRows; r++) {
    final row = sh.row(r);
    final phone = _getCell<String>(row[0]);
    if (phone == null || phone.isEmpty) continue;
    await db.insert('customers', {
      'phone': phone,
      'name': _getCell<String>(row[1]) ?? '',
      'address': _getCell<String>(row[2]) ?? '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<void> importSuppliersXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.decodeBytes(bytes);
  final sh = excel['proveedores'];
  if (sh.maxRows <= 1) return;
  for (var r = 1; r < sh.maxRows; r++) {
    final row = sh.row(r);
    final id = _getCell<String>(row[0]);
    if (id == null || id.isEmpty) continue;
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
  for (var r = 1; r < sh.maxRows; r++) {
    final row = sh.row(r);
    final sku = _getCell<String>(row[1]);
    if (sku == null || sku.isEmpty) continue;
    await db.insert('products', {
      'id': _getCell<int>(row[0]),
      'sku': sku,
      'name': _getCell<String>(row[2]) ?? '',
      'category': _getCell<String>(row[3]) ?? '',
      'default_sale_price': double.tryParse((_getCell(row[4]) ?? '').toString()) ?? 0.0,
      'last_purchase_price': double.tryParse((_getCell(row[5]) ?? '').toString()) ?? 0.0,
      'last_purchase_date': _getCell<String>(row[6]) ?? '',
      'stock': int.tryParse((_getCell(row[7]) ?? '').toString()) ?? 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<void> importSalesXlsx(Uint8List bytes) async {
  // Opcional según diseño actual
}

Future<void> importPurchasesXlsx(Uint8List bytes) async {
  // Opcional según diseño actual
}