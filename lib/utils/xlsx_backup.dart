import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db.dart';
import '../repositories/product_repository.dart';

/// ---------- Helpers comunes ----------

String _ts() => DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

Future<String> _saveExcelToDownloads(Excel excel, String baseName) async {
  final bytes = excel.encode();
  if (bytes == null) throw Exception('No se pudo generar XLSX');
  final data = Uint8List.fromList(bytes);

  // FileSaver usa MediaStore en Android => guarda en Descargas visibles
  final savedPath = await FileSaver.instance.saveFile(
    name: baseName,
    bytes: data,
    ext: 'xlsx',
    mimeType: MimeType.other, // no existe MimeType.xlsx
  );
  // En Android retorna p.ej. "productos_20251010_2359.xlsx"
  return savedPath;
}

List<CellValue?> _rowStr(Iterable values) =>
    values.map<CellValue?>((v) => TextCellValue(v?.toString() ?? '')).toList();

List<CellValue?> _rowNum(Iterable<num?> values) =>
    values.map<CellValue?>((v) => v == null ? null : DoubleCellValue(v.toDouble())).toList();

Future<void> showImportFilePicker(
  BuildContext context,
  String label,
  Future<void> Function(Uint8List) handler,
) async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    withData: true,
  );
  if (res == null || res.files.isEmpty) return;
  final bytes = res.files.first.bytes;
  if (bytes == null) throw Exception('No se pudo leer el archivo seleccionado');
  await handler(bytes);
}

/// ---------- EXPORTACIONES ----------

Future<String> exportProductsXlsx() async {
  final db = await openAppDb();
  final excel = Excel.createExcel();

  final sh = excel['productos'];
  sh.appendRow(_rowStr(['sku','name','category',
    'default_sale_price','last_purchase_price','last_purchase_date','stock']));

  final rows = await db.query('products', orderBy: 'name ASC');
  for (final r in rows) {
    sh.appendRow([
      TextCellValue((r['sku'] ?? '').toString()),
      TextCellValue((r['name'] ?? '').toString()),
      TextCellValue((r['category'] ?? '').toString()),
      DoubleCellValue(((r['default_sale_price'] as num?) ?? 0).toDouble()),
      DoubleCellValue(((r['last_purchase_price'] as num?) ?? 0).toDouble()),
      TextCellValue((r['last_purchase_date'] ?? '').toString()),
      DoubleCellValue(((r['stock'] as num?) ?? 0).toDouble()),
    ]);
  }
  return _saveExcelToDownloads(excel, 'productos_${_ts()}');
}

Future<String> exportClientsXlsx() async {
  final db = await openAppDb();
  final excel = Excel.createExcel();
  final sh = excel['clientes'];
  sh.appendRow(_rowStr(['phone_id','name','address']));

  final rows = await db.query('customers', orderBy: 'name ASC');
  for (final r in rows) {
    sh.appendRow([
      TextCellValue((r['phone'] ?? '').toString()),
      TextCellValue((r['name'] ?? '').toString()),
      TextCellValue((r['address'] ?? '').toString()),
    ]);
  }
  return _saveExcelToDownloads(excel, 'clientes_${_ts()}');
}

Future<String> exportSuppliersXlsx() async {
  final db = await openAppDb();
  final excel = Excel.createExcel();
  final sh = excel['proveedores'];
  sh.appendRow(_rowStr(['id','name','phone','address']));

  final rows = await db.query('suppliers', orderBy: 'name ASC');
  for (final r in rows) {
    sh.appendRow([
      TextCellValue((r['id'] ?? '').toString()),
      TextCellValue((r['name'] ?? '').toString()),
      TextCellValue((r['phone'] ?? '').toString()),
      TextCellValue((r['address'] ?? '').toString()),
    ]);
  }
  return _saveExcelToDownloads(excel, 'proveedores_${_ts()}');
}

Future<String> exportSalesXlsx() async {
  final db = await openAppDb();
  final excel = Excel.createExcel();
  final shSales = excel['ventas'];
  final shItems = excel['ventas_items'];

  shSales.appendRow(_rowStr([
    'sale_id','date','customer_phone','payment_method','place','shipping_cost','discount'
  ]));
  shItems.appendRow(_rowStr(['sale_id','product_sku','product_name','quantity','unit_price']));

  final sales = await db.query('sales', orderBy: 'date ASC');
  for (final s in sales) {
    shSales.appendRow([
      TextCellValue((s['id'] ?? '').toString()),
      TextCellValue((s['date'] ?? '').toString()),
      TextCellValue((s['customer_phone'] ?? '').toString()),
      TextCellValue((s['payment_method'] ?? '').toString()),
      TextCellValue((s['place'] ?? '').toString()),
      DoubleCellValue(((s['shipping_cost'] as num?) ?? 0).toDouble()),
      DoubleCellValue(((s['discount'] as num?) ?? 0).toDouble()),
    ]);

    final items = await db.query('sale_items',
      where: 'sale_id = ?', whereArgs: [s['id']]);
    for (final it in items) {
      shItems.appendRow([
        TextCellValue((it['sale_id'] ?? '').toString()),
        TextCellValue((it['product_sku'] ?? '').toString()),
        TextCellValue((it['product_name'] ?? '').toString()),
        DoubleCellValue(((it['quantity'] as num?) ?? 0).toDouble()),
        DoubleCellValue(((it['unit_price'] as num?) ?? 0).toDouble()),
      ]);
    }
  }
  return _saveExcelToDownloads(excel, 'ventas_${_ts()}');
}

Future<String> exportPurchasesXlsx() async {
  final db = await openAppDb();
  final excel = Excel.createExcel();
  final shP = excel['compras'];
  final shI = excel['compras_items'];

  shP.appendRow(_rowStr(['purchase_id','folio','date','supplier_id']));
  shI.appendRow(_rowStr(['purchase_id','product_sku','product_name','quantity','unit_cost']));

  final purchases = await db.query('purchases', orderBy: 'date ASC');
  for (final p in purchases) {
    shP.appendRow([
      TextCellValue((p['id'] ?? '').toString()),
      TextCellValue((p['folio'] ?? '').toString()),
      TextCellValue((p['date'] ?? '').toString()),
      TextCellValue((p['supplier_id'] ?? '').toString()),
    ]);

    final items = await db.query('purchase_items',
      where: 'purchase_id = ?', whereArgs: [p['id']]);
    for (final it in items) {
      shI.appendRow([
        TextCellValue((it['purchase_id'] ?? '').toString()),
        TextCellValue((it['product_sku'] ?? '').toString()),
        TextCellValue((it['product_name'] ?? '').toString()),
        DoubleCellValue(((it['quantity'] as num?) ?? 0).toDouble()),
        DoubleCellValue(((it['unit_cost'] as num?) ?? 0).toDouble()),
      ]);
    }
  }
  return _saveExcelToDownloads(excel, 'compras_${_ts()}');
}

/// ---------- IMPORTACIONES ----------
/// Nota: usa el SKU para enlazar productos.

Future<void> importProductsXlsx(Uint8List bytes) async {
  final db = await openAppDb();
  final ex = Excel.decodeBytes(bytes);
  final sh = ex['productos'];
  // Espera encabezados: sku, name, category, default_sale_price, last_purchase_price, last_purchase_date, stock
  for (var r = 1; r < sh.maxRows; r++) {
    final row = sh.row(r);
    final sku = row[0]?.value?.toString().trim() ?? '';
    if (sku.isEmpty) continue;
    final name = row[1]?.value?.toString().trim() ?? '';
    final cat  = row[2]?.value?.toString().trim().isEmpty == true ? 'general' : row[2]!.value.toString().trim();
    final dsp  = double.tryParse(row[3]?.value?.toString() ?? '0') ?? 0;
    final lpp  = double.tryParse(row[4]?.value?.toString() ?? '0') ?? 0;
    final lpd  = row[5]?.value?.toString() ?? '';
    final stk  = double.tryParse(row[6]?.value?.toString() ?? '0') ?? 0;

    await db.insert('products', {
      'sku': sku,
      'name': name,
      'category': cat,
      'default_sale_price': dsp,
      'last_purchase_price': lpp,
      'last_purchase_date': lpd,
      'stock': stk,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<void> importClientsXlsx(Uint8List bytes) async {
  final db = await openAppDb();
  final ex = Excel.decodeBytes(bytes);
  final sh = ex['clientes'];
  for (var r = 1; r < sh.maxRows; r++) {
    final row = sh.row(r);
    final phone = row[0]?.value?.toString().trim() ?? '';
    if (phone.isEmpty) continue;
    await db.insert('customers', {
      'phone': phone,
      'name': row[1]?.value?.toString() ?? '',
      'address': row[2]?.value?.toString() ?? '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<void> importSuppliersXlsx(Uint8List bytes) async {
  final db = await openAppDb();
  final ex = Excel.decodeBytes(bytes);
  final sh = ex['proveedores'];
  for (var r = 1; r < sh.maxRows; r++) {
    final row = sh.row(r);
    final id = row[0]?.value?.toString().trim() ?? '';
    if (id.isEmpty) continue;
    await db.insert('suppliers', {
      'id': id,
      'name': row[1]?.value?.toString() ?? '',
      'phone': row[2]?.value?.toString() ?? '',
      'address': row[3]?.value?.toString() ?? '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<void> importSalesXlsx(Uint8List bytes) async {
  final db = await openAppDb();
  final ex = Excel.decodeBytes(bytes);
  final shSales = ex['ventas'];
  final shItems = ex['ventas_items'];

  // Primero ventas
  for (var r = 1; r < shSales.maxRows; r++) {
    final row = shSales.row(r);
    final idStr = row[0]?.value?.toString();
    if (idStr == null || idStr.isEmpty) continue;
    final id = int.tryParse(idStr);
    if (id == null) continue;

    await db.insert('sales', {
      'id': id,
      'date': row[1]?.value?.toString() ?? '',
      'customer_phone': row[2]?.value?.toString(),
      'payment_method': row[3]?.value?.toString() ?? 'efectivo',
      'place': row[4]?.value?.toString() ?? '',
      'shipping_cost': double.tryParse(row[5]?.value?.toString() ?? '0') ?? 0,
      'discount': double.tryParse(row[6]?.value?.toString() ?? '0') ?? 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Luego items (solo si el SKU existe)
  final prodRepo = ProductRepository();
  for (var r = 1; r < shItems.maxRows; r++) {
    final row = shItems.row(r);
    final saleId = int.tryParse(row[0]?.value?.toString() ?? '');
    final sku = row[1]?.value?.toString().trim() ?? '';
    if (saleId == null || sku.isEmpty) continue;

    final prod = await prodRepo.findBySku(sku);
    if (prod == null) continue;

    await db.insert('sale_items', {
      'sale_id': saleId,
      'product_sku': sku,
      'product_name': row[2]?.value?.toString() ?? (prod['name'] ?? ''),
      'quantity': double.tryParse(row[3]?.value?.toString() ?? '0') ?? 0,
      'unit_price': double.tryParse(row[4]?.value?.toString() ?? '0') ?? 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<void> importPurchasesXlsx(Uint8List bytes) async {
  final db = await openAppDb();
  final ex = Excel.decodeBytes(bytes);
  final shP = ex['compras'];
  final shI = ex['compras_items'];

  for (var r = 1; r < shP.maxRows; r++) {
    final row = shP.row(r);
    final id = int.tryParse(row[0]?.value?.toString() ?? '');
    if (id == null) continue;
    await db.insert('purchases', {
      'id': id,
      'folio': row[1]?.value?.toString() ?? '',
      'date': row[2]?.value?.toString() ?? '',
      'supplier_id': row[3]?.value?.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  final prodRepo = ProductRepository();
  for (var r = 1; r < shI.maxRows; r++) {
    final row = shI.row(r);
    final purchaseId = int.tryParse(row[0]?.value?.toString() ?? '');
    final sku = row[1]?.value?.toString().trim() ?? '';
    if (purchaseId == null || sku.isEmpty) continue;

    final prod = await prodRepo.findBySku(sku);
    if (prod == null) continue;

    await db.insert('purchase_items', {
      'purchase_id': purchaseId,
      'product_sku': sku,
      'product_name': row[2]?.value?.toString() ?? (prod['name'] ?? ''),
      'quantity': double.tryParse(row[3]?.value?.toString() ?? '0') ?? 0,
      'unit_cost': double.tryParse(row[4]?.value?.toString() ?? '0') ?? 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}