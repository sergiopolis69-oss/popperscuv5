import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database.dart';
import '../repositories/product_repository.dart';

/// Reporte simple para importaciones XLSX.
class ImportReport {
  final int ok;
  final List<String> errors;
  ImportReport(this.ok, this.errors);
}

/// ------------------------------------------------------------
/// Utilidades: permisos, carpeta Descargas y celdas de Excel.
/// ------------------------------------------------------------

Future<void> _ensureStoragePermission() async {
  // En Android 10–12 se requiere el permiso de almacenamiento para escribir en /Download.
  final status = await Permission.storage.status;
  if (!status.isGranted) {
    await Permission.storage.request();
  }
}

/// Intenta usar /storage/emulated/0/Download si existe.
/// Si no, usa getExternalStorageDirectory() y por último la carpeta de DB.
Future<Directory> _downloadsDir() async {
  // 1) Intento directo a Descargas en Android.
  final dl = Directory('/storage/emulated/0/Download');
  if (Platform.isAndroid && await dl.exists()) {
    return dl;
  }

  // 2) External Storage (propia de la app).
  try {
    final ext = await getExternalStorageDirectory();
    if (ext != null) return ext;
  } catch (_) {}

  // 3) Fallback: carpeta de la DB (siempre existe).
  final dbPath = await getDatabasesPath();
  return Directory(dbPath);
}

// Convierte cualquier valor a CellValue para excel ^4.x
CellValue _cv(dynamic v) {
  if (v == null) return const TextCellValue('');
  if (v is num) return DoubleCellValue(v.toDouble());
  return TextCellValue(v.toString());
}

// ------------------------------------------------------------
// EXPORTACIONES
// ------------------------------------------------------------

Future<File> exportProductsXlsx() async {
  await _ensureStoragePermission();
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('products', orderBy: 'name COLLATE NOCASE');

  final x = Excel.createExcel();
  final s = x['productos'];
  s.appendRow([
    const TextCellValue('sku'),
    const TextCellValue('name'),
    const TextCellValue('category'),
    const TextCellValue('default_sale_price'),
    const TextCellValue('last_purchase_price'),
    const TextCellValue('stock'),
  ]);

  for (final r in rows) {
    s.appendRow([
      _cv(r['sku']),
      _cv(r['name']),
      _cv(r['category']),
      _cv((r['default_sale_price'] as num?)?.toDouble() ?? 0.0),
      _cv((r['last_purchase_price'] as num?)?.toDouble() ?? 0.0),
      _cv((r['stock'] as num?)?.toInt() ?? 0),
    ]);
  }

  final bytes = x.encode()!;
  final dir = await _downloadsDir();
  final file = File(p.join(dir.path, 'productos.xlsx'));
  return file..writeAsBytesSync(bytes, flush: true);
}

Future<File> exportClientsXlsx() async {
  await _ensureStoragePermission();
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('customers', orderBy: 'name COLLATE NOCASE');

  final x = Excel.createExcel();
  final s = x['clientes'];
  s.appendRow([
    const TextCellValue('phone'),
    const TextCellValue('name'),
    const TextCellValue('address'),
  ]);

  for (final r in rows) {
    s.appendRow([_cv(r['phone']), _cv(r['name']), _cv(r['address'])]);
  }

  final bytes = x.encode()!;
  final dir = await _downloadsDir();
  final file = File(p.join(dir.path, 'clientes.xlsx'));
  return file..writeAsBytesSync(bytes, flush: true);
}

Future<File> exportSuppliersXlsx() async {
  await _ensureStoragePermission();
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('suppliers', orderBy: 'name COLLATE NOCASE');

  final x = Excel.createExcel();
  final s = x['proveedores'];
  s.appendRow([
    const TextCellValue('phone'),
    const TextCellValue('name'),
    const TextCellValue('address'),
  ]);

  for (final r in rows) {
    s.appendRow([_cv(r['phone']), _cv(r['name']), _cv(r['address'])]);
  }

  final bytes = x.encode()!;
  final dir = await _downloadsDir();
  final file = File(p.join(dir.path, 'proveedores.xlsx'));
  return file..writeAsBytesSync(bytes, flush: true);
}

/// Ventas: hoja `ventas` y `venta_items` (product_sku).
Future<File> exportSalesXlsx() async {
  await _ensureStoragePermission();
  final db = await DatabaseHelper.instance.db;

  final x = Excel.createExcel();
  final s = x['ventas'];
  final si = x['venta_items'];

  s.appendRow([
    const TextCellValue('id'),
    const TextCellValue('customer_phone'),
    const TextCellValue('payment_method'),
    const TextCellValue('place'),
    const TextCellValue('shipping_cost'),
    const TextCellValue('discount'),
    const TextCellValue('date'),
  ]);

  final sales = await db.query('sales', orderBy: 'date DESC');
  for (final r in sales) {
    s.appendRow([
      _cv(r['id']),
      _cv(r['customer_phone']),
      _cv(r['payment_method']),
      _cv(r['place']),
      _cv(r['shipping_cost']),
      _cv(r['discount']),
      _cv(r['date']),
    ]);
  }

  si.appendRow([
    const TextCellValue('sale_id'),
    const TextCellValue('product_sku'),
    const TextCellValue('quantity'),
    const TextCellValue('unit_price'),
  ]);

  final items = await db.rawQuery('''
    SELECT si.sale_id, p.sku AS product_sku, si.quantity, si.unit_price
    FROM sale_items si
    JOIN products p ON p.id = si.product_id
    ORDER BY si.sale_id
  ''');

  for (final r in items) {
    si.appendRow([
      _cv(r['sale_id']),
      _cv(r['product_sku']),
      _cv(r['quantity']),
      _cv(r['unit_price']),
    ]);
  }

  final bytes = x.encode()!;
  final dir = await _downloadsDir();
  final file = File(p.join(dir.path, 'ventas.xlsx'));
  return file..writeAsBytesSync(bytes, flush: true);
}

/// Compras: hoja `compras` y `compra_items` (product_sku).
Future<File> exportPurchasesXlsx() async {
  await _ensureStoragePermission();
  final db = await DatabaseHelper.instance.db;

  final x = Excel.createExcel();
  final s = x['compras'];
  final si = x['compra_items'];

  s.appendRow([
    const TextCellValue('id'),
    const TextCellValue('folio'),
    const TextCellValue('supplier_id'),
    const TextCellValue('date'),
  ]);

  final purchases = await db.query('purchases', orderBy: 'date DESC');
  for (final r in purchases) {
    s.appendRow([_cv(r['id']), _cv(r['folio']), _cv(r['supplier_id']), _cv(r['date'])]);
  }

  si.appendRow([
    const TextCellValue('purchase_id'),
    const TextCellValue('product_sku'),
    const TextCellValue('quantity'),
    const TextCellValue('unit_cost'),
  ]);

  final items = await db.rawQuery('''
    SELECT pi.purchase_id, p.sku AS product_sku, pi.quantity, pi.unit_cost
    FROM purchase_items pi
    JOIN products p ON p.id = pi.product_id
    ORDER BY pi.purchase_id
  ''');

  for (final r in items) {
    si.appendRow([
      _cv(r['purchase_id']),
      _cv(r['product_sku']),
      _cv(r['quantity']),
      _cv(r['unit_cost']),
    ]);
  }

  final bytes = x.encode()!;
  final dir = await _downloadsDir();
  final file = File(p.join(dir.path, 'compras.xlsx'));
  return file..writeAsBytesSync(bytes, flush: true);
}

// ------------------------------------------------------------
// IMPORTACIONES
// ------------------------------------------------------------

Future<ImportReport> importProductsXlsx(Uint8List data) async {
  final x = Excel.decodeBytes(data);
  final sheet = x['productos'];
  if (sheet == null) return ImportReport(0, ['Hoja "productos" no encontrada']);

  final hdr = sheet.row(0).map((c) => c?.value.toString().trim().toLowerCase()).toList();
  int idx(String name) => hdr.indexOf(name);

  if (idx('sku') < 0) return ImportReport(0, ['Columna "sku" requerida']);

  final repo = ProductRepository();
  int ok = 0; final errs = <String>[];

  for (var r = 1; r < sheet.maxRows; r++) {
    final row = sheet.row(r);
    final sku = (row[idx('sku')]?.value ?? '').toString().trim();
    if (sku.isEmpty) { errs.add('Fila ${r + 1}: SKU vacío'); continue; }

    try {
      await repo.upsertBySku({
        'sku': sku,
        'name': idx('name') >= 0 ? row[idx('name')]?.value?.toString() ?? '' : '',
        'category': idx('category') >= 0 ? row[idx('category')]?.value?.toString() : null,
        'default_sale_price': idx('default_sale_price') >= 0 ? (row[idx('default_sale_price')]?.value as num?)?.toDouble() : 0.0,
        'last_purchase_price': idx('last_purchase_price') >= 0 ? (row[idx('last_purchase_price')]?.value as num?)?.toDouble() : 0.0,
        'stock': idx('stock') >= 0 ? (row[idx('stock')]?.value as num?)?.toInt() : 0,
      });
      ok++;
    } catch (e) {
      errs.add('Fila ${r + 1}: $e');
    }
  }

  return ImportReport(ok, errs);
}

Future<ImportReport> importClientsXlsx(Uint8List data) async {
  final db = await DatabaseHelper.instance.db;
  final x = Excel.decodeBytes(data);
  final sheet = x['clientes'];
  if (sheet == null) return ImportReport(0, ['Hoja "clientes" no encontrada']);

  final hdr = sheet.row(0).map((c) => c?.value.toString().trim().toLowerCase()).toList();
  int idx(String name) => hdr.indexOf(name);
  if (idx('phone') < 0) return ImportReport(0, ['Columna "phone" requerida']);

  int ok = 0; final errs = <String>[];
  for (var r = 1; r < sheet.maxRows; r++) {
    final row = sheet.row(r);
    final phone = (row[idx('phone')]?.value ?? '').toString().trim();
    if (phone.isEmpty) { errs.add('Fila ${r+1}: phone vacío'); continue; }

    await db.insert('customers', {
      'phone': phone,
      'name': idx('name') >= 0 ? row[idx('name')]?.value?.toString() : null,
      'address': idx('address') >= 0 ? row[idx('address')]?.value?.toString() : null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    ok++;
  }
  return ImportReport(ok, errs);
}

Future<ImportReport> importSuppliersXlsx(Uint8List data) async {
  final db = await DatabaseHelper.instance.db;
  final x = Excel.decodeBytes(data);
  final sheet = x['proveedores'];
  if (sheet == null) return ImportReport(0, ['Hoja "proveedores" no encontrada']);

  final hdr = sheet.row(0).map((c) => c?.value.toString().trim().toLowerCase()).toList();
  int idx(String name) => hdr.indexOf(name);
  if (idx('phone') < 0) return ImportReport(0, ['Columna "phone" requerida']);

  int ok = 0; final errs = <String>[];
  for (var r = 1; r < sheet.maxRows; r++) {
    final row = sheet.row(r);
    final phone = (row[idx('phone')]?.value ?? '').toString().trim();
    if (phone.isEmpty) { errs.add('Fila ${r+1}: phone vacío'); continue; }

    await db.insert('suppliers', {
      'phone': phone,
      'name': idx('name') >= 0 ? row[idx('name')]?.value?.toString() : null,
      'address': idx('address') >= 0 ? row[idx('address')]?.value?.toString() : null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    ok++;
  }
  return ImportReport(ok, errs);
}

Future<ImportReport> importSalesXlsx(Uint8List data) async {
  final db = await DatabaseHelper.instance.db;
  final x = Excel.decodeBytes(data);

  final s = x['ventas'];
  final si = x['venta_items'];
  if (s == null || si == null) {
    return ImportReport(0, ['Hojas "ventas" y/o "venta_items" no encontradas']);
  }

  final hdrS = s.row(0).map((c) => c?.value.toString().trim().toLowerCase()).toList();
  final hdrI = si.row(0).map((c) => c?.value.toString().trim().toLowerCase()).toList();
  int idxS(String n) => hdrS.indexOf(n);
  int idxI(String n) => hdrI.indexOf(n);

  int ok = 0; final errs = <String>[];
  final saleIdMap = <int, int>{};

  // Ventas
  for (var r = 1; r < s.maxRows; r++) {
    final row = s.row(r);
    if (row.every((c) => c == null)) continue;

    final idImp = int.tryParse((row[idxS('id')]?.value ?? '').toString());
    final saleId = await db.insert('sales', {
      'customer_phone': idxS('customer_phone') >= 0 ? row[idxS('customer_phone')]?.value?.toString() : null,
      'payment_method': idxS('payment_method') >= 0 ? row[idxS('payment_method')]?.value?.toString() : null,
      'place': idxS('place') >= 0 ? row[idxS('place')]?.value?.toString() : null,
      'shipping_cost': (idxS('shipping_cost') >= 0 ? (row[idxS('shipping_cost')]?.value as num?) : 0)?.toDouble() ?? 0.0,
      'discount': (idxS('discount') >= 0 ? (row[idxS('discount')]?.value as num?) : 0)?.toDouble() ?? 0.0,
      'date': idxS('date') >= 0 ? row[idxS('date')]?.value?.toString() : null,
    });

    if (idImp != null) saleIdMap[idImp] = saleId;
    ok++;
  }

  // Items
  for (var r = 1; r < si.maxRows; r++) {
    final row = si.row(r);
    if (row.every((c) => c == null)) continue;

    final saleImp = int.tryParse((row[idxI('sale_id')]?.value ?? '').toString());
    final sku = (row[idxI('product_sku')]?.value ?? '').toString().trim();
    if (saleImp == null || sku.isEmpty) { errs.add('venta_items fila ${r+1}: sale_id o SKU inválido'); continue; }

    final saleId = saleIdMap[saleImp];
    if (saleId == null) { errs.add('venta_items fila ${r+1}: sale_id no resuelto'); continue; }

    final prod = await ProductRepository().getBySku(sku);
    if (prod == null) { errs.add('venta_items fila ${r+1}: SKU $sku no existe'); continue; }

    await db.insert('sale_items', {
      'sale_id': saleId,
      'product_id': prod['id'],
      'quantity': (row[idxI('quantity')]?.value as num?)?.toInt() ?? 0,
      'unit_price': (row[idxI('unit_price')]?.value as num?)?.toDouble() ?? 0.0,
    });
  }

  return ImportReport(ok, errs);
}

Future<ImportReport> importPurchasesXlsx(Uint8List data) async {
  final db = await DatabaseHelper.instance.db;
  final x = Excel.decodeBytes(data);

  final s = x['compras'];
  final si = x['compra_items'];
  if (s == null || si == null) {
    return ImportReport(0, ['Hojas "compras" y/o "compra_items" no encontradas']);
  }

  final hdrS = s.row(0).map((c) => c?.value.toString().trim().toLowerCase()).toList();
  final hdrI = si.row(0).map((c) => c?.value.toString().trim().toLowerCase()).toList();
  int idxS(String n) => hdrS.indexOf(n);
  int idxI(String n) => hdrI.indexOf(n);

  int ok = 0; final errs = <String>[];
  final purchaseIdMap = <int, int>{};

  // Compras
  for (var r = 1; r < s.maxRows; r++) {
    final row = s.row(r);
    if (row.every((c) => c == null)) continue;

    final idImp = int.tryParse((row[idxS('id')]?.value ?? '').toString());
    final pId = await db.insert('purchases', {
      'folio': idxS('folio') >= 0 ? row[idxS('folio')]?.value?.toString() : null,
      'supplier_id': (idxS('supplier_id') >= 0 ? (row[idxS('supplier_id')]?.value as num?) : null)?.toInt(),
      'date': idxS('date') >= 0 ? row[idxS('date')]?.value?.toString() : null,
    });

    if (idImp != null) purchaseIdMap[idImp] = pId;
    ok++;
  }

  // Items
  for (var r = 1; r < si.maxRows; r++) {
    final row = si.row(r);
    if (row.every((c) => c == null)) continue;

    final pImp = int.tryParse((row[idxI('purchase_id')]?.value ?? '').toString());
    final sku = (row[idxI('product_sku')]?.value ?? '').toString().trim();
    if (pImp == null || sku.isEmpty) { errs.add('compra_items fila ${r+1}: purchase_id o SKU inválido'); continue; }

    final pId = purchaseIdMap[pImp];
    if (pId == null) { errs.add('compra_items fila ${r+1}: purchase_id no resuelto'); continue; }

    final prod = await ProductRepository().getBySku(sku);
    if (prod == null) { errs.add('compra_items fila ${r+1}: SKU $sku no existe'); continue; }

    final qty  = (row[idxI('quantity')]?.value as num?)?.toInt() ?? 0;
    final cost = (row[idxI('unit_cost')]?.value as num?)?.toDouble() ?? 0.0;

    await db.insert('purchase_items', {
      'purchase_id': pId,
      'product_id': prod['id'],
      'quantity': qty,
      'unit_cost': cost,
    });

    // Actualiza inventario y costo promedio
    await db.rawUpdate(
      'UPDATE products SET stock = stock + ?, last_purchase_price = ?, last_purchase_date = ? WHERE id = ?',
      [qty, cost, DateTime.now().toIso8601String(), prod['id']]
    );
  }

  return ImportReport(ok, errs);
}