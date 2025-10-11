import 'dart:typed_data';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../repositories/product_repository.dart';
import '../repositories/customer_repository.dart';
import '../repositories/supplier_repository.dart';
import '../repositories/sale_repository.dart';
import '../repositories/purchase_repository.dart';

CellValue _text(String? v) => v == null ? const TextCellValue('') : TextCellValue(v);
CellValue _num(num? v) => v == null ? const TextCellValue('') : DoubleCellValue(v.toDouble());

Future<String> _saveXlsxBytes(Uint8List bytes, String fileName) async {
  // Pedir permisos de escritura (seguro no rompe en Android 13+; si lo niegan, guardamos en documentos de app)
  await Permission.storage.request();

  try {
    final path = await FileSaver.instance.saveFile(
      name: fileName,
      bytes: bytes,
      ext: 'xlsx',
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    if (path != null && path.isNotEmpty) return path;
  } catch (_) { /* fallback abajo */ }

  final dir = await getApplicationDocumentsDirectory();
  final fallback = p.join(dir.path, '$fileName.xlsx');
  final f = File(fallback);
  await f.writeAsBytes(bytes, flush: true);
  return fallback;
}

// =========== EXPORTS ============

Future<String> exportProductsXlsx() async {
  final repo = ProductRepository();
  final rows = await repo.all();

  final excel = Excel.createExcel();
  final sh = excel['products'];
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
      _text(r['sku']?.toString()),
      _text(r['name']?.toString()),
      _text(r['category']?.toString()),
      _num(r['default_sale_price'] as num?),
      _num(r['last_purchase_price'] as num?),
      _text(r['last_purchase_date']?.toString()),
      _num(r['stock'] as num?),
    ]);
  }
  final bytes = Uint8List.fromList(excel.encode()!);
  return _saveXlsxBytes(bytes, 'popperscu_productos');
}

Future<String> exportClientsXlsx() async {
  final repo = CustomerRepository();
  final excel = Excel.createExcel();
  final sh = excel['customers'];
  // encabezados
  sh.appendRow([
    TextCellValue('phone'),
    TextCellValue('name'),
    TextCellValue('address'),
  ]);

  // dump
  // usamos rawQuery simple para no escribir otro repo
  final db = await DatabaseProvider.instance.database;
  final rows = await db.query('customers', orderBy: 'name ASC');
  for (final r in rows) {
    sh.appendRow([
      _text(r['phone']?.toString()),
      _text(r['name']?.toString()),
      _text(r['address']?.toString()),
    ]);
  }
  final bytes = Uint8List.fromList(excel.encode()!);
  return _saveXlsxBytes(bytes, 'popperscu_clientes');
}

Future<String> exportSuppliersXlsx() async {
  final db = await DatabaseProvider.instance.database;
  final rows = await db.query('suppliers', orderBy: 'name ASC');

  final excel = Excel.createExcel();
  final sh = excel['suppliers'];
  sh.appendRow([
    TextCellValue('phone'),
    TextCellValue('name'),
    TextCellValue('address'),
  ]);
  for (final r in rows) {
    sh.appendRow([
      _text(r['phone']?.toString()),
      _text(r['name']?.toString()),
      _text(r['address']?.toString()),
    ]);
  }
  final bytes = Uint8List.fromList(excel.encode()!);
  return _saveXlsxBytes(bytes, 'popperscu_proveedores');
}

Future<String> exportSalesXlsx() async {
  final repo = SaleRepository();
  final db = await DatabaseProvider.instance.database;

  // Encabezados de ventas
  final excel = Excel.createExcel();
  final shHead = excel['sales'];
  shHead.appendRow([
    TextCellValue('sale_id'),
    TextCellValue('date'),
    TextCellValue('customer_phone'),
    TextCellValue('payment_method'),
    TextCellValue('place'),
    TextCellValue('shipping_cost'),
    TextCellValue('discount'),
  ]);

  final shItems = excel['sale_items'];
  shItems.appendRow([
    TextCellValue('sale_id'),
    TextCellValue('product_sku'),
    TextCellValue('product_name'),
    TextCellValue('quantity'),
    TextCellValue('unit_price'),
  ]);

  final heads = await db.query('sales', orderBy: 'date DESC, id DESC');
  for (final h in heads) {
    final saleId = h['id'] as int;
    shHead.appendRow([
      _num(saleId),
      _text(h['date']?.toString()),
      _text(h['customer_phone']?.toString()),
      _text(h['payment_method']?.toString()),
      _text(h['place']?.toString()),
      _num(h['shipping_cost'] as num?),
      _num(h['discount'] as num?),
    ]);
    final items = await repo.itemsOf(saleId);
    for (final it in items) {
      shItems.appendRow([
        _num(saleId),
        _text(it['product_sku']?.toString()),
        _text(it['product_name']?.toString()),
        _num(it['quantity'] as num?),
        _num(it['unit_price'] as num?),
      ]);
    }
  }

  final bytes = Uint8List.fromList(excel.encode()!);
  return _saveXlsxBytes(bytes, 'popperscu_ventas');
}

Future<String> exportPurchasesXlsx() async {
  final repo = PurchaseRepository();
  final db = await DatabaseProvider.instance.database;

  final excel = Excel.createExcel();
  final shHead = excel['purchases'];
  shHead.appendRow([
    TextCellValue('purchase_id'),
    TextCellValue('folio'),
    TextCellValue('date'),
    TextCellValue('supplier_id'),
  ]);
  final shItems = excel['purchase_items'];
  shItems.appendRow([
    TextCellValue('purchase_id'),
    TextCellValue('product_sku'),
    TextCellValue('product_name'),
    TextCellValue('quantity'),
    TextCellValue('unit_cost'),
  ]);

  final heads = await db.query('purchases', orderBy: 'date DESC, id DESC');
  for (final h in heads) {
    final id = h['id'] as int;
    shHead.appendRow([
      _num(id), _text(h['folio']?.toString()), _text(h['date']?.toString()), _text(h['supplier_id']?.toString())
    ]);
    final items = await repo.itemsOf(id);
    for (final it in items) {
      shItems.appendRow([
        _num(id),
        _text(it['product_sku']?.toString()),
        _text(it['product_name']?.toString()),
        _num(it['quantity'] as num?),
        _num(it['unit_cost'] as num?),
      ]);
    }
  }

  final bytes = Uint8List.fromList(excel.encode()!);
  return _saveXlsxBytes(bytes, 'popperscu_compras');
}

// =========== IMPORTS ============

Future<void> _importFromPicker(Future<void> Function(Excel) fn) async {
  final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
  if (res == null || res.files.isEmpty) return;
  final bytes = res.files.first.bytes;
  if (bytes == null) throw Exception('No se pudo leer el archivo');
  final excel = Excel.decodeBytes(bytes);
  await fn(excel);
}

Future<void> importProductsXlsx(Uint8List bytes) async {
  final repo = ProductRepository();
  final excel = Excel.decodeBytes(bytes);
  final sh = excel['products'];
  if (sh.maxRows < 2) return;
  // fila 0 son headers
  for (int r = 1; r < sh.maxRows; r++) {
    final row = sh.row(r);
    String sku = (row[0]?.value?.toString() ?? '').trim();
    if (sku.isEmpty) continue; // SKU obligatorio
    final name = row.length > 1 ? row[1]?.value?.toString() : null;
    final category = row.length > 2 ? row[2]?.value?.toString() : null;
    final defaultPrice = row.length > 3 ? double.tryParse(row[3]?.value?.toString() ?? '') : null;
    final lastCost = row.length > 4 ? double.tryParse(row[4]?.value?.toString() ?? '') : null;
    final lastDate = row.length > 5 ? row[5]?.value?.toString() : null;
    final stock = row.length > 6 ? double.tryParse(row[6]?.value?.toString() ?? '') : null;

    await repo.insert({
      'sku': sku,
      'name': name ?? sku,
      'category': category,
      'default_sale_price': defaultPrice,
      'last_purchase_price': lastCost,
      'last_purchase_date': lastDate,
      'stock': stock,
    });
  }
}

Future<void> importClientsXlsx(Uint8List bytes) async {
  final excel = Excel.decodeBytes(bytes);
  final sh = excel['customers'];
  if (sh.maxRows < 2) return;
  final db = await DatabaseProvider.instance.database;
  await db.transaction((txn) async {
    for (int r = 1; r < sh.maxRows; r++) {
      final row = sh.row(r);
      final phone = (row[0]?.value?.toString() ?? '').trim();
      if (phone.isEmpty) continue;
      final name = row.length > 1 ? row[1]?.value?.toString() : '';
      final address = row.length > 2 ? row[2]?.value?.toString() : null;
      await txn.insert('customers', {
        'phone': phone, 'name': name, 'address': address
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}

Future<void> importSuppliersXlsx(Uint8List bytes) async {
  final excel = Excel.decodeBytes(bytes);
  final sh = excel['suppliers'];
  if (sh.maxRows < 2) return;
  final db = await DatabaseProvider.instance.database;
  await db.transaction((txn) async {
    for (int r = 1; r < sh.maxRows; r++) {
      final row = sh.row(r);
      final phone = (row[0]?.value?.toString() ?? '').trim();
      if (phone.isEmpty) continue;
      final name = row.length > 1 ? row[1]?.value?.toString() : '';
      final address = row.length > 2 ? row[2]?.value?.toString() : null;
      await txn.insert('suppliers', {
        'phone': phone, 'name': name, 'address': address
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}

Future<void> importSalesXlsx(Uint8List bytes) async {
  final excel = Excel.decodeBytes(bytes);
  final shS = excel['sales'];
  final shI = excel['sale_items'];
  if (shS.maxRows < 2 || shI.maxRows < 2) return;
  final db = await DatabaseProvider.instance.database;
  await db.transaction((txn) async {
    // Crear mapa sale_id -> nuevo id
    final idMap = <int,int>{};
    for (int r = 1; r < shS.maxRows; r++) {
      final row = shS.row(r);
      final oldId = int.tryParse(row[0]?.value?.toString() ?? '');
      final date = row[1]?.value?.toString() ?? '';
      final cust = row[2]?.value?.toString();
      final pay  = row[3]?.value?.toString();
      final place= row[4]?.value?.toString();
      final ship = double.tryParse(row[5]?.value?.toString() ?? '') ?? 0;
      final disc = double.tryParse(row[6]?.value?.toString() ?? '') ?? 0;
      if (oldId == null) continue;
      final newId = await txn.insert('sales', {
        'date': date, 'customer_phone': cust, 'payment_method': pay,
        'place': place, 'shipping_cost': ship, 'discount': disc
      });
      idMap[oldId] = newId;
    }
    for (int r = 1; r < shI.maxRows; r++) {
      final row = shI.row(r);
      final oldId = int.tryParse(row[0]?.value?.toString() ?? '');
      if (oldId == null) continue;
      final newId = idMap[oldId];
      if (newId == null) continue;
      final sku  = row[1]?.value?.toString();
      final name = row[2]?.value?.toString();
      final qty  = double.tryParse(row[3]?.value?.toString() ?? '') ?? 0;
      final price= double.tryParse(row[4]?.value?.toString() ?? '') ?? 0;
      if (sku == null || sku.trim().isEmpty) continue;
      // no tocamos stock al importar historial
      await txn.insert('sale_items', {
        'sale_id': newId,
        'product_sku': sku,
        'product_name': (name == null || name.isEmpty) ? sku : name,
        'quantity': qty,
        'unit_price': price,
      });
    }
  });
}

Future<void> importPurchasesXlsx(Uint8List bytes) async {
  final excel = Excel.decodeBytes(bytes);
  final shP = excel['purchases'];
  final shI = excel['purchase_items'];
  if (shP.maxRows < 2 || shI.maxRows < 2) return;
  final db = await DatabaseProvider.instance.database;
  await db.transaction((txn) async {
    final idMap = <int,int>{};
    for (int r = 1; r < shP.maxRows; r++) {
      final row = shP.row(r);
      final oldId = int.tryParse(row[0]?.value?.toString() ?? '');
      final folio = row[1]?.value?.toString();
      final date  = row[2]?.value?.toString();
      final supId = row[3]?.value?.toString();
      if (oldId == null) continue;
      final newId = await txn.insert('purchases', {
        'folio': folio, 'date': date, 'supplier_id': supId
      });
      idMap[oldId] = newId;
    }
    for (int r = 1; r < shI.maxRows; r++) {
      final row = shI.row(r);
      final oldId = int.tryParse(row[0]?.value?.toString() ?? '');
      if (oldId == null) continue;
      final newId = idMap[oldId];
      if (newId == null) continue;
      final sku  = row[1]?.value?.toString();
      final name = row[2]?.value?.toString();
      final qty  = double.tryParse(row[3]?.value?.toString() ?? '') ?? 0;
      final cost = double.tryParse(row[4]?.value?.toString() ?? '') ?? 0;
      if (sku == null || sku.trim().isEmpty) continue;
      await txn.insert('purchase_items', {
        'purchase_id': newId,
        'product_sku': sku,
        'product_name': (name == null || name.isEmpty) ? sku : name,
        'quantity': qty,
        'unit_cost': cost,
      });
      // no tocamos stock al importar historial
    }
  });
}