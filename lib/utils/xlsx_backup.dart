import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db.dart';
import '../repositories/product_repository.dart';

String _ts() => DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

Future<String> _saveExcelToDownloads(Excel excel, String baseName) async {
  final bytes = excel.encode();
  if (bytes == null) { throw Exception('No se pudo generar XLSX'); }
  final data = Uint8List.fromList(bytes);
  final savedPath = await FileSaver.instance.saveFile(
    name: baseName,
    bytes: data,
    ext: 'xlsx',
    mimeType: MimeType.other, // visible en Descargas
  );
  return savedPath;
}

CellValue _txt(Object? v) => TextCellValue(v?.toString() ?? '');
CellValue _num(num? v) => v == null ? const TextCellValue('') : DoubleCellValue(v.toDouble());

// ---------------- EXPORT ----------------

Future<String> exportProductsXlsx() async {
  final db = await openAppDb();
  final excel = Excel.createExcel();
  final sh = excel['productos'];
  sh.appendRow([
    _txt('sku'), _txt('name'), _txt('category'),
    _txt('default_sale_price'), _txt('last_purchase_price'),
    _txt('last_purchase_date'), _txt('stock'),
  ]);

  final rows = await db.query('products', orderBy: 'name ASC');
  for (final r in rows) {
    sh.appendRow([
      _txt(r['sku']), _txt(r['name']), _txt(r['category']),
      _num(r['default_sale_price'] as num?), _num(r['last_purchase_price'] as num?),
      _txt(r['last_purchase_date']), _num(r['stock'] as num?),
    ]);
  }
  return _saveExcelToDownloads(excel, 'productos_${_ts()}');
}

Future<String> exportClientsXlsx() async {
  final db = await openAppDb();
  final excel = Excel.createExcel();
  final sh = excel['clientes'];
  sh.appendRow([_txt('phone_id'), _txt('name'), _txt('address')]);
  final rows = await db.query('customers', orderBy: 'name ASC');
  for (final r in rows) {
    sh.appendRow([_txt(r['phone']), _txt(r['name']), _txt(r['address'])]);
  }
  return _saveExcelToDownloads(excel, 'clientes_${_ts()}');
}

Future<String> exportSuppliersXlsx() async {
  final db = await openAppDb();
  final excel = Excel.createExcel();
  final sh = excel['proveedores'];
  sh.appendRow([_txt('id'), _txt('name'), _txt('phone'), _txt('address')]);
  final rows = await db.query('suppliers', orderBy: 'name ASC');
  for (final r in rows) {
    sh.appendRow([_txt(r['id']), _txt(r['name']), _txt(r['phone']), _txt(r['address'])]);
  }
  return _saveExcelToDownloads(excel, 'proveedores_${_ts()}');
}

Future<String> exportSalesXlsx() async {
  final db = await openAppDb();
  final excel = Excel.createExcel();
  final shS = excel['ventas'];
  final shI = excel['ventas_items'];
  shS.appendRow([
    _txt('sale_id'), _txt('date'), _txt('customer_phone'),
    _txt('payment_method'), _txt('place'), _txt('shipping_cost'), _txt('discount'),
  ]);
  shI.appendRow([_txt('sale_id'), _txt('product_sku'), _txt('product_name'), _txt('quantity'), _txt('unit_price')]);

  final sales = await db.query('sales', orderBy: 'date ASC');
  for (final s in sales) {
    shS.appendRow([
      _txt(s['id']), _txt(s['date']), _txt(s['customer_phone']),
      _txt(s['payment_method']), _txt(s['place']),
      _num(s['shipping_cost'] as num?), _num(s['discount'] as num?),
    ]);
    final items = await db.query('sale_items', where: 'sale_id = ?', whereArgs: [s['id']]);
    for (final it in items) {
      shI.appendRow([
        _txt(it['sale_id']), _txt(it['product_sku']), _txt(it['product_name']),
        _num(it['quantity'] as num?), _num(it['unit_price'] as num?),
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
  shP.appendRow([_txt('purchase_id'), _txt('folio'), _txt('date'), _txt('supplier_id')]);
  shI.appendRow([_txt('purchase_id'), _txt('product_sku'), _txt('product_name'), _txt('quantity'), _txt('unit_cost')]);

  final purchases = await db.query('purchases', orderBy: 'date ASC');
  for (final p in purchases) {
    shP.appendRow([
      _txt(p['id']), _txt(p['folio']), _txt(p['date']), _txt(p['supplier_id']),
    ]);
    final items = await db.query('purchase_items', where: 'purchase_id = ?', whereArgs: [p['id']]);
    for (final it in items) {
      shI.appendRow([
        _txt(it['purchase_id']), _txt(it['product_sku']), _txt(it['product_name']),
        _num(it['quantity'] as num?), _num(it['unit_cost'] as num?),
      ]);
    }
  }
  return _saveExcelToDownloads(excel, 'compras_${_ts()}');
}

// ---------------- IMPORT ----------------

Future<void> importProductsXlsx(Uint8List bytes) async {
  final db = await openAppDb();
  final ex = Excel.decodeBytes(bytes);
  final sh = ex['productos'];
  if (sh.maxRows == 0) throw Exception('Hoja "productos" vacía o inexistente');

  for (var r = 1; r < sh.maxRows; r++) {
    final row = sh.row(r);
    final sku = row[0]?.value?.toString().trim() ?? '';
    if (sku.isEmpty) continue;
    final name = row[1]?.value?.toString() ?? '';
    final cat  = (row[2]?.value?.toString().trim().isEmpty ?? true) ? 'general' : row[2]!.value.toString().trim();
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
  if (sh.maxRows == 0) throw Exception('Hoja "clientes" vacía o inexistente');

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
  if (sh.maxRows == 0) throw Exception('Hoja "proveedores" vacía o inexistente');

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
  final shS = ex['ventas'];
  final shI = ex['ventas_items'];
  if (shS.maxRows == 0) throw Exception('Hoja "ventas" vacía o inexistente');
  if (shI.maxRows == 0) throw Exception('Hoja "ventas_items" vacía o inexistente');

  for (var r = 1; r < shS.maxRows; r++) {
    final row = shS.row(r);
    final idStr = row[0]?.value?.toString();
    final id = int.tryParse(idStr ?? '');
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

  final prodRepo = ProductRepository();
  for (var r = 1; r < shI.maxRows; r++) {
    final row = shI.row(r);
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
  if (shP.maxRows == 0) throw Exception('Hoja "compras" vacía o inexistente');
  if (shI.maxRows == 0) throw Exception('Hoja "compras_items" vacía o inexistente');

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