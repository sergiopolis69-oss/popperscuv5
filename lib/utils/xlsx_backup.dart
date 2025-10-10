import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter/painting.dart' show TextSpan; // para toPlainText()
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database.dart';

/* ───────────────── Helpers ───────────────── */

/// Convierte cualquier celda a String plano (maneja TextSpan de Google Sheets)
String? _cellText(Data? cell) {
  if (cell == null) return null;
  final v = cell.value;
  if (v is TextCellValue) {
    final inner = v.value;
    if (inner is String) return inner.trim();
    if (inner is TextSpan) return inner.toPlainText().trim();
    return inner?.toString().trim();
  }
  if (v is IntCellValue) return v.value.toString();
  if (v is DoubleCellValue) return v.value.toString();
  if (v is BoolCellValue) return v.value ? 'true' : 'false';
  return v?.toString();
}

double _cellDouble(Data? cell) {
  final t = _cellText(cell);
  if (t == null || t.isEmpty) return 0.0;
  // tolerante a comas
  return double.tryParse(t.replaceAll(',', '.')) ?? 0.0;
}

int _cellInt(Data? cell) {
  final t = _cellText(cell);
  if (t == null || t.isEmpty) return 0;
  return int.tryParse(t) ?? _cellDouble(cell).round();
}

CellValue? _cv(dynamic v) {
  if (v == null) return null;
  if (v is num) return DoubleCellValue(v.toDouble());
  if (v is bool) return BoolCellValue(v);
  return TextCellValue(v.toString());
}

Future<void> _ensureStoragePerms() async {
  final res = await [
    Permission.storage,
    Permission.manageExternalStorage,
  ].request();
  final ok = (res[Permission.manageExternalStorage]?.isGranted ?? false) ||
      (res[Permission.storage]?.isGranted ?? false);
  if (!ok) throw Exception('Permiso de almacenamiento denegado');
}

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

Future<String> _saveExcelToDownloads(Excel excel, String filename) async {
  await _ensureStoragePerms();
  final bytes = excel.save();
  if (bytes == null) throw Exception('No se pudo generar XLSX');
  final file = File('${_publicDownloadsDir().path}/$filename.xlsx');
  await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
  return file.path;
}

/* ───────────────── EXPORTS ───────────────── */

Future<String> exportClientsXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('customers', orderBy: 'name COLLATE NOCASE ASC');
  final excel = Excel.createExcel();
  final sh = excel['clientes'];
  sh.appendRow([TextCellValue('phone_id'), TextCellValue('name'), TextCellValue('address')]);
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
  sh.appendRow([TextCellValue('id'), TextCellValue('name'), TextCellValue('phone'), TextCellValue('address')]);
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

/// Exporta ventas (encabezado) y renglones (items) con SKU.
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

  final shItems = excel['ventas_items'];
  shItems.appendRow([
    TextCellValue('sale_id'),
    TextCellValue('product_sku'),
    TextCellValue('product_name'),
    TextCellValue('quantity'),
    TextCellValue('unit_price'),
  ]);
  final items = await db.rawQuery('''
    SELECT si.sale_id, p.sku AS product_sku, p.name AS product_name,
           si.quantity, si.unit_price
    FROM sale_items si
    JOIN products p ON p.id = si.product_id
    ORDER BY si.sale_id DESC, si.id ASC
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

/// Exporta compras (encabezado) y renglones (items) con SKU.
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

  final shI = excel['compras_items'];
  shI.appendRow([
    TextCellValue('purchase_id'),
    TextCellValue('product_sku'),
    TextCellValue('product_name'),
    TextCellValue('quantity'),
    TextCellValue('unit_cost'),
  ]);
  final items = await db.rawQuery('''
    SELECT pi.purchase_id, p.sku AS product_sku, p.name AS product_name,
           pi.quantity, pi.unit_cost
    FROM purchase_items pi
    JOIN products p ON p.id = pi.product_id
    ORDER BY pi.purchase_id DESC, pi.id ASC
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

/* ───────────────── IMPORTS ───────────────── */

Future<void> importClientsXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.decodeBytes(bytes);
  final sh = excel['clientes'];
  if (sh.maxRows <= 1) return;
  final batch = db.batch();
  for (var r = 1; r < sh.maxRows; r++) {
    final row = sh.row(r);
    final phone = _cellText(row[0]);
    if (phone == null || phone.isEmpty) continue;
    batch.insert('customers', {
      'phone': phone,
      'name': _cellText(row[1]) ?? '',
      'address': _cellText(row[2]) ?? '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

Future<void> importSuppliersXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.decodeBytes(bytes);
  final sh = excel['proveedores'];
  if (sh.maxRows <= 1) return;
  final batch = db.batch();
  for (var r = 1; r < sh.maxRows; r++) {
    final row = sh.row(r);
    final id = _cellText(row[0]);
    if (id == null || id.isEmpty) continue;
    batch.insert('suppliers', {
      'id': id,
      'name': _cellText(row[1]) ?? '',
      'phone': _cellText(row[2]) ?? '',
      'address': _cellText(row[3]) ?? '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

Future<void> importProductsXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.decodeBytes(bytes);
  final sh = excel['productos'];
  if (sh.maxRows <= 1) return;
  final batch = db.batch();
  for (var r = 1; r < sh.maxRows; r++) {
    final row = sh.row(r);
    final sku = _cellText(row[1]);
    if (sku == null || sku.isEmpty) continue;
    batch.insert('products', {
      'id': _cellInt(row[0]) == 0 ? null : _cellInt(row[0]),
      'sku': sku,
      'name': _cellText(row[2]) ?? '',
      'category': _cellText(row[3]) ?? '',
      'default_sale_price': _cellDouble(row[4]),
      'last_purchase_price': _cellDouble(row[5]),
      'last_purchase_date': _cellText(row[6]) ?? '',
      'stock': _cellInt(row[7]),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

/// Importa encabezados + items de ventas.
/// Hojas esperadas: 'ventas' y 'ventas_items'
Future<void> importSalesXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.decodeBytes(bytes);

  final shH = excel['ventas'];
  final shI = excel['ventas_items'];
  if (shH.maxRows <= 1) return;

  await db.transaction((txn) async {
    // Encabezados
    for (var r = 1; r < shH.maxRows; r++) {
      final row = shH.row(r);
      final saleId = _cellInt(row[0]);
      if (saleId == 0) continue;
      await txn.insert('sales', {
        'id': saleId,
        'date': _cellText(row[1]) ?? '',
        'customer_phone': _cellText(row[2]) ?? '',
        'payment_method': _cellText(row[3]) ?? '',
        'place': _cellText(row[4]) ?? '',
        'shipping_cost': _cellDouble(row[5]),
        'discount': _cellDouble(row[6]),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // borra items previos para evitar duplicados
      await txn.delete('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
    }

    // Items (si existen)
    if (shI.maxRows > 1) {
      for (var r = 1; r < shI.maxRows; r++) {
        final row = shI.row(r);
        final saleId = _cellInt(row[0]);
        final sku = _cellText(row[1]) ?? '';
        if (saleId == 0 || sku.isEmpty) continue;

        final prod = await txn.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
        if (prod.isEmpty) continue; // seguridad
        final productId = prod.first['id'] as int;

        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': productId,
          'quantity': _cellInt(row[3]),
          'unit_price': _cellDouble(row[4]),
        });
      }
    }
  });
}

/// Importa encabezados + items de compras.
/// Hojas esperadas: 'compras' y 'compras_items'
Future<void> importPurchasesXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.decodeBytes(bytes);

  final shH = excel['compras'];
  final shI = excel['compras_items'];
  if (shH.maxRows <= 1) return;

  await db.transaction((txn) async {
    // Encabezados
    for (var r = 1; r < shH.maxRows; r++) {
      final row = shH.row(r);
      final purId = _cellInt(row[0]);
      if (purId == 0) continue;
      await txn.insert('purchases', {
        'id': purId,
        'folio': _cellText(row[1]) ?? '',
        'date': _cellText(row[2]) ?? '',
        'supplier_id': _cellText(row[3]) ?? '',
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.delete('purchase_items', where: 'purchase_id = ?', whereArgs: [purId]);
    }

    // Items
    if (shI.maxRows > 1) {
      for (var r = 1; r < shI.maxRows; r++) {
        final row = shI.row(r);
        final purId = _cellInt(row[0]);
        final sku = _cellText(row[1]) ?? '';
        if (purId == 0 || sku.isEmpty) continue;

        final prod = await txn.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
        if (prod.isEmpty) continue;
        final productId = prod.first['id'] as int;

        await txn.insert('purchase_items', {
          'purchase_id': purId,
          'product_id': productId,
          'quantity': _cellInt(row[3]),
          'unit_cost': _cellDouble(row[4]),
        });
      }
    }
  });
}