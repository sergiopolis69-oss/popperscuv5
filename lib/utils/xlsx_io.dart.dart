import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:sqflite/sqflite.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:downloads_path_provider_28/downloads_path_provider_28.dart';
import 'package:path/path.dart' as p;
import '../data/database.dart';
import '../repositories/product_repository.dart';

Future<Directory> _downloadsDir() async {
  try {
    final dir = await DownloadsPathProvider.downloadsDirectory;
    if (dir != null) return dir;
  } catch (_) {}
  // fallback a documentos
  final docs = await getDatabasesPath();
  return Directory(docs);
}

// ----------------- EXPORT -----------------

Future<File> exportProductsXlsx() async {
  await Permission.storage.request();
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('products', orderBy: 'name COLLATE NOCASE');
  final x = Excel.createExcel();
  final s = x['productos'];
  s.appendRow(['sku','name','category','default_sale_price','last_purchase_price','stock']);
  for (final r in rows) {
    s.appendRow([
      r['sku'],
      r['name'],
      r['category'],
      (r['default_sale_price'] as num?)?.toDouble() ?? 0,
      (r['last_purchase_price'] as num?)?.toDouble() ?? 0,
      (r['stock'] as num?)?.toInt() ?? 0,
    ]);
  }
  final bytes = x.encode()!;
  final dir = await _downloadsDir();
  final file = File(p.join(dir.path, 'productos.xlsx'));
  return file..writeAsBytesSync(bytes, flush: true);
}

Future<File> exportClientsXlsx() async {
  await Permission.storage.request();
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('customers', orderBy: 'name COLLATE NOCASE');
  final x = Excel.createExcel();
  final s = x['clientes'];
  s.appendRow(['phone','name','address']);
  for (final r in rows) {
    s.appendRow([r['phone'], r['name'], r['address']]);
  }
  final bytes = x.encode()!;
  final dir = await _downloadsDir();
  final file = File(p.join(dir.path, 'clientes.xlsx'));
  return file..writeAsBytesSync(bytes, flush: true);
}

Future<File> exportSuppliersXlsx() async {
  await Permission.storage.request();
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('suppliers', orderBy: 'name COLLATE NOCASE');
  final x = Excel.createExcel();
  final s = x['proveedores'];
  s.appendRow(['phone','name','address']);
  for (final r in rows) {
    s.appendRow([r['phone'], r['name'], r['address']]);
  }
  final bytes = x.encode()!;
  final dir = await _downloadsDir();
  final file = File(p.join(dir.path, 'proveedores.xlsx'));
  return file..writeAsBytesSync(bytes, flush: true);
}

/// Ventas: hoja `ventas` (id, customer_phone, payment_method, place, shipping_cost, discount, date)
/// y hoja `venta_items` (sale_id, product_sku, quantity, unit_price)
Future<File> exportSalesXlsx() async {
  await Permission.storage.request();
  final db = await DatabaseHelper.instance.db;
  final x = Excel.createExcel();
  final s = x['ventas'];
  final si = x['venta_items'];

  final sales = await db.query('sales', orderBy: 'date DESC');
  s.appendRow(['id','customer_phone','payment_method','place','shipping_cost','discount','date']);
  for (final r in sales) {
    s.appendRow([r['id'], r['customer_phone'], r['payment_method'], r['place'],
      r['shipping_cost'], r['discount'], r['date']]);
  }

  final items = await db.rawQuery('''
    SELECT si.sale_id, p.sku AS product_sku, si.quantity, si.unit_price
    FROM sale_items si
    JOIN products p ON p.id = si.product_id
    ORDER BY si.sale_id
  ''');
  si.appendRow(['sale_id','product_sku','quantity','unit_price']);
  for (final r in items) {
    si.appendRow([r['sale_id'], r['product_sku'], r['quantity'], r['unit_price']]);
  }

  final bytes = x.encode()!;
  final dir = await _downloadsDir();
  final file = File(p.join(dir.path, 'ventas.xlsx'));
  return file..writeAsBytesSync(bytes, flush: true);
}

/// Compras: hoja `compras` (id, folio, supplier_id, date)
/// y hoja `compra_items` (purchase_id, product_sku, quantity, unit_cost)
Future<File> exportPurchasesXlsx() async {
  await Permission.storage.request();
  final db = await DatabaseHelper.instance.db;
  final x = Excel.createExcel();
  final s = x['compras'];
  final si = x['compra_items'];

  final rows = await db.query('purchases', orderBy: 'date DESC');
  s.appendRow(['id','folio','supplier_id','date']);
  for (final r in rows) {
    s.appendRow([r['id'], r['folio'], r['supplier_id'], r['date']]);
  }

  final items = await db.rawQuery('''
    SELECT pi.purchase_id, p.sku AS product_sku, pi.quantity, pi.unit_cost
    FROM purchase_items pi
    JOIN products p ON p.id = pi.product_id
    ORDER BY pi.purchase_id
  ''');
  si.appendRow(['purchase_id','product_sku','quantity','unit_cost']);
  for (final r in items) {
    si.appendRow([r['purchase_id'], r['product_sku'], r['quantity'], r['unit_cost']]);
  }

  final bytes = x.encode()!;
  final dir = await _downloadsDir();
  final file = File(p.join(dir.path, 'compras.xlsx'));
  return file..writeAsBytesSync(bytes, flush: true);
}

// ----------------- IMPORT -----------------

class ImportReport {
  final int ok;
  final List<String> errors;
  ImportReport(this.ok, this.errors);
}

Future<ImportReport> importProductsXlsx(Uint8List data) async {
  final db = await DatabaseHelper.instance.db;
  final repo = ProductRepository();
  final x = Excel.decodeBytes(data);
  final sheet = x['productos'];
  if (sheet == null) return ImportReport(0, ['Hoja "productos" no encontrada']);

  final header = sheet.row(0).map((c)=>c?.value.toString().trim().toLowerCase()).toList();
  final idxSku = header.indexOf('sku');
  if (idxSku < 0) return ImportReport(0, ['Columna "sku" requerida']);
  int ok = 0; final errs = <String>[];

  for (var r = 1; r < sheet.maxRows; r++) {
    final row = sheet.row(r);
    final sku = (row[idxSku]?.value ?? '').toString().trim();
    if (sku.isEmpty) { errs.add('Fila ${r+1}: SKU vacío'); continue; }

    try {
      await repo.upsertBySku({
        'sku': sku,
        'name': row[header.indexOf('name')]?.value?.toString() ?? '',
        'category': header.contains('category') ? row[header.indexOf('category')]?.value?.toString() : null,
        'default_sale_price': header.contains('default_sale_price') ? (row[header.indexOf('default_sale_price')]?.value as num?)?.toDouble() : 0.0,
        'last_purchase_price': header.contains('last_purchase_price') ? (row[header.indexOf('last_purchase_price')]?.value as num?)?.toDouble() : 0.0,
        'stock': header.contains('stock') ? (row[header.indexOf('stock')]?.value as num?)?.toInt() : 0,
      });
      ok++;
    } catch (e) {
      errs.add('Fila ${r+1}: $e');
    }
  }
  return ImportReport(ok, errs);
}

Future<ImportReport> importClientsXlsx(Uint8List data) async {
  final db = await DatabaseHelper.instance.db;
  final x = Excel.decodeBytes(data);
  final sheet = x['clientes'];
  if (sheet == null) return ImportReport(0, ['Hoja "clientes" no encontrada']);
  final header = sheet.row(0).map((c)=>c?.value.toString().trim().toLowerCase()).toList();
  final idxPhone = header.indexOf('phone');
  if (idxPhone < 0) return ImportReport(0, ['Columna "phone" requerida']);

  int ok = 0; final errs = <String>[];
  for (var r=1; r<sheet.maxRows; r++) {
    final row = sheet.row(r);
    final phone = (row[idxPhone]?.value ?? '').toString().trim();
    if (phone.isEmpty) { errs.add('Fila ${r+1}: phone vacío'); continue; }
    final dataRow = {
      'phone': phone,
      'name': header.contains('name') ? row[header.indexOf('name')]?.value?.toString() : null,
      'address': header.contains('address') ? row[header.indexOf('address')]?.value?.toString() : null,
    };
    await db.insert('customers', dataRow, conflictAlgorithm: ConflictAlgorithm.replace);
    ok++;
  }
  return ImportReport(ok, errs);
}

Future<ImportReport> importSuppliersXlsx(Uint8List data) async {
  final db = await DatabaseHelper.instance.db;
  final x = Excel.decodeBytes(data);
  final sheet = x['proveedores'];
  if (sheet == null) return ImportReport(0, ['Hoja "proveedores" no encontrada']);
  final header = sheet.row(0).map((c)=>c?.value.toString().trim().toLowerCase()).toList();
  final idxPhone = header.indexOf('phone');
  if (idxPhone < 0) return ImportReport(0, ['Columna "phone" requerida']);

  int ok = 0; final errs = <String>[];
  for (var r=1; r<sheet.maxRows; r++) {
    final row = sheet.row(r);
    final phone = (row[idxPhone]?.value ?? '').toString().trim();
    if (phone.isEmpty) { errs.add('Fila ${r+1}: phone vacío'); continue; }
    final dataRow = {
      'phone': phone,
      'name': header.contains('name') ? row[header.indexOf('name')]?.value?.toString() : null,
      'address': header.contains('address') ? row[header.indexOf('address')]?.value?.toString() : null,
    };
    await db.insert('suppliers', dataRow, conflictAlgorithm: ConflictAlgorithm.replace);
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

  final hdrS = s.row(0).map((c)=>c?.value.toString().trim().toLowerCase()).toList();
  final hdrI = si.row(0).map((c)=>c?.value.toString().trim().toLowerCase()).toList();
  int ok = 0; final errs = <String>[];

  // Primero insertamos ventas
  final saleIdMap = <int,int>{}; // sale_id_import -> sale_id_new
  for (var r=1; r<s.maxRows; r++) {
    final row = s.row(r);
    if (row.every((c)=>c==null)) continue;
    final idImp = int.tryParse((row[hdrS.indexOf('id')]?.value ?? '').toString());
    final dataRow = {
      'customer_phone': hdrS.contains('customer_phone') ? row[hdrS.indexOf('customer_phone')]?.value?.toString() : null,
      'payment_method': hdrS.contains('payment_method') ? row[hdrS.indexOf('payment_method')]?.value?.toString() : null,
      'place': hdrS.contains('place') ? row[hdrS.indexOf('place')]?.value?.toString() : null,
      'shipping_cost': (hdrS.contains('shipping_cost') ? (row[hdrS.indexOf('shipping_cost')]?.value as num?) : 0)?.toDouble() ?? 0.0,
      'discount': (hdrS.contains('discount') ? (row[hdrS.indexOf('discount')]?.value as num?) : 0)?.toDouble() ?? 0.0,
      'date': hdrS.contains('date') ? row[hdrS.indexOf('date')]?.value?.toString() : null,
    };
    final newId = await db.insert('sales', dataRow);
    if (idImp != null) saleIdMap[idImp] = newId;
    ok++;
  }

  // Luego items resolviendo product_id por sku
  for (var r=1; r<si.maxRows; r++) {
    final row = si.row(r);
    if (row.every((c)=>c==null)) continue;
    final saleImp = int.tryParse((row[hdrI.indexOf('sale_id')]?.value ?? '').toString());
    final sku = (row[hdrI.indexOf('product_sku')]?.value ?? '').toString().trim();
    if (saleImp == null || sku.isEmpty) { errs.add('venta_items fila ${r+1}: sale_id o SKU inválido'); continue; }
    final saleId = saleIdMap[saleImp];
    if (saleId == null) { errs.add('venta_items fila ${r+1}: sale_id no resuelto'); continue; }
    final prod = await ProductRepository().getBySku(sku);
    if (prod == null) { errs.add('venta_items fila ${r+1}: SKU $sku no existe'); continue; }
    await db.insert('sale_items', {
      'sale_id': saleId,
      'product_id': prod['id'],
      'quantity': (row[hdrI.indexOf('quantity')]?.value as num?)?.toInt() ?? 0,
      'unit_price': (row[hdrI.indexOf('unit_price')]?.value as num?)?.toDouble() ?? 0.0,
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

  final hdrS = s.row(0).map((c)=>c?.value.toString().trim().toLowerCase()).toList();
  final hdrI = si.row(0).map((c)=>c?.value.toString().trim().toLowerCase()).toList();
  int ok = 0; final errs = <String>[];

  final purchaseIdMap = <int,int>{};

  for (var r=1; r<s.maxRows; r++) {
    final row = s.row(r);
    if (row.every((c)=>c==null)) continue;
    final idImp = int.tryParse((row[hdrS.indexOf('id')]?.value ?? '').toString());
    final dataRow = {
      'folio': hdrS.contains('folio') ? row[hdrS.indexOf('folio')]?.value?.toString() : null,
      'supplier_id': (hdrS.contains('supplier_id') ? (row[hdrS.indexOf('supplier_id')]?.value as num?) : null)?.toInt(),
      'date': hdrS.contains('date') ? row[hdrS.indexOf('date')]?.value?.toString() : null,
    };
    final newId = await db.insert('purchases', dataRow);
    if (idImp != null) purchaseIdMap[idImp] = newId;
    ok++;
  }

  for (var r=1; r<si.maxRows; r++) {
    final row = si.row(r);
    if (row.every((c)=>c==null)) continue;
    final pImp = int.tryParse((row[hdrI.indexOf('purchase_id')]?.value ?? '').toString());
    final sku = (row[hdrI.indexOf('product_sku')]?.value ?? '').toString().trim();
    if (pImp == null || sku.isEmpty) { errs.add('compra_items fila ${r+1}: purchase_id o SKU inválido'); continue; }
    final pId = purchaseIdMap[pImp];
    if (pId == null) { errs.add('compra_items fila ${r+1}: purchase_id no resuelto'); continue; }
    final prod = await ProductRepository().getBySku(sku);
    if (prod == null) { errs.add('compra_items fila ${r+1}: SKU $sku no existe'); continue; }

    await db.insert('purchase_items', {
      'purchase_id': pId,
      'product_id': prod['id'],
      'quantity': (row[hdrI.indexOf('quantity')]?.value as num?)?.toInt() ?? 0,
      'unit_cost': (row[hdrI.indexOf('unit_cost')]?.value as num?)?.toDouble() ?? 0.0,
    });

    // Actualiza inventario y costo
    await db.rawUpdate(
      'UPDATE products SET stock = stock + ?, last_purchase_price = ?, last_purchase_date = ? WHERE id = ?',
      [(row[hdrI.indexOf('quantity')]?.value as num?)?.toInt() ?? 0,
       (row[hdrI.indexOf('unit_cost')]?.value as num?)?.toDouble() ?? 0.0,
       DateTime.now().toIso8601String(),
       prod['id']]
    );
  }

  return ImportReport(ok, errs);
}