import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database.dart';

/// Helpers para celdas tipo Excel 4.x
CellValue _cv(dynamic v) {
  if (v == null) return TextCellValue('');
  if (v is num) return DoubleCellValue(v.toDouble());
  return TextCellValue(v.toString());
}

Future<Database> _db() async => DatabaseHelper.instance.db;

/// ====== EXPORT ======

Future<void> exportAllToXlsx() async {
  final db = await _db();
  final excel = Excel.createExcel();

  // --- PRODUCTS ---
  final shProd = excel['products'];
  shProd.appendRow([
    TextCellValue('sku'),
    TextCellValue('name'),
    TextCellValue('category'),
    TextCellValue('default_sale_price'),
    TextCellValue('last_purchase_price'),
    TextCellValue('stock'),
  ]);

  final prows = await db.query('products', orderBy: 'name ASC');
  for (final p in prows) {
    shProd.appendRow([
      _cv(p['sku']),
      _cv(p['name']),
      _cv(p['category']),
      _cv(p['default_sale_price']),
      _cv(p['last_purchase_price']),
      _cv(p['stock']),
    ]);
  }

  // --- CUSTOMERS ---
  final shCust = excel['customers'];
  shCust.appendRow([
    TextCellValue('phone'), // id
    TextCellValue('name'),
    TextCellValue('address'),
  ]);
  final crows = await db.query('customers', orderBy: 'name ASC');
  for (final c in crows) {
    shCust.appendRow([
      _cv(c['phone']),
      _cv(c['name']),
      _cv(c['address']),
    ]);
  }

  // --- SUPPLIERS ---
  final shSupp = excel['suppliers'];
  shSupp.appendRow([
    TextCellValue('phone'), // id
    TextCellValue('name'),
    TextCellValue('address'),
  ]);
  final srows = await db.query('suppliers', orderBy: 'name ASC');
  for (final s in srows) {
    shSupp.appendRow([
      _cv(s['phone']),
      _cv(s['name']),
      _cv(s['address']),
    ]);
  }

  // --- SALES (encabezado) ---
  final shSales = excel['sales'];
  shSales.appendRow([
    TextCellValue('id'),
    TextCellValue('customer_phone'),
    TextCellValue('payment_method'),
    TextCellValue('place'),
    TextCellValue('shipping_cost'),
    TextCellValue('discount'),
    TextCellValue('date'),
  ]);
  final sales = await db.query('sales', orderBy: 'date ASC');
  for (final s in sales) {
    shSales.appendRow([
      _cv(s['id']),
      _cv(s['customer_phone']),
      _cv(s['payment_method']),
      _cv(s['place']),
      _cv(s['shipping_cost']),
      _cv(s['discount']),
      _cv(s['date']),
    ]);
  }

  // --- SALE ITEMS (detalle con SKU SIEMPRE) ---
  final shSaleItems = excel['sale_items'];
  shSaleItems.appendRow([
    TextCellValue('sale_id'),
    TextCellValue('sku'),
    TextCellValue('quantity'),
    TextCellValue('unit_price'),
  ]);
  final sitems = await db.query('sale_items', orderBy: 'sale_id ASC');
  for (final it in sitems) {
    shSaleItems.appendRow([
      _cv(it['sale_id']),
      _cv(it['sku']),
      _cv(it['quantity']),
      _cv(it['unit_price']),
    ]);
  }

  // --- PURCHASES (encabezado) ---
  final shPurch = excel['purchases'];
  shPurch.appendRow([
    TextCellValue('id'),
    TextCellValue('supplier_phone'), // usamos phone como id
    TextCellValue('folio'),
    TextCellValue('date'),
  ]);
  final purchases = await db.query('purchases', orderBy: 'date ASC');
  for (final p in purchases) {
    shPurch.appendRow([
      _cv(p['id']),
      _cv(p['supplier_phone']),
      _cv(p['folio']),
      _cv(p['date']),
    ]);
  }

  // --- PURCHASE ITEMS (detalle con SKU SIEMPRE) ---
  final shPurchItems = excel['purchase_items'];
  shPurchItems.appendRow([
    TextCellValue('purchase_id'),
    TextCellValue('sku'),
    TextCellValue('quantity'),
    TextCellValue('unit_cost'),
  ]);
  final pitems = await db.query('purchase_items', orderBy: 'purchase_id ASC');
  for (final it in pitems) {
    shPurchItems.appendRow([
      _cv(it['purchase_id']),
      _cv(it['sku']),
      _cv(it['quantity']),
      _cv(it['unit_cost']),
    ]);
  }

  // Guardar en XLSX con FileSaver (SAF) - escribe en Descargas/Navegador del sistema
  final bytes = excel.encode()!;
  final u8 = Uint8List.fromList(bytes);
  final ts = DateTime.now().toIso8601String().replaceAll(':', '').replaceAll('.', '');
  await FileSaver.instance.saveFile(
    name: 'backup_$ts',
    bytes: u8,
    ext: 'xlsx',
    mimeType: MimeType.other, // enum; evita el problema de tipos
  );
}

/// ====== IMPORT ======
/// Cada import recibe un archivo XLSX y hace upsert.
/// Se asume encabezado en la primer fila.

Future<void> importProductsXlsx(File file) async {
  final db = await _db();
  final bytes = await file.readAsBytes();
  final excel = Excel.decodeBytes(bytes);
  final sh = excel['products'];
  await db.transaction((txn) async {
    for (int r = 1; r < sh.maxRows; r++) {
      final row = sh.row(r);
      if (row.isEmpty) continue;
      final sku = row[0]?.value?.toString().trim();
      if (sku == null || sku.isEmpty) continue;
      final name = row.length > 1 ? row[1]?.value?.toString() ?? '' : '';
      final category = row.length > 2 ? row[2]?.value?.toString() ?? '' : '';
      final sale = row.length > 3 ? (row[3]?.value is num ? (row[3]!.value as num).toDouble() : double.tryParse(row[3]?.value?.toString() ?? '0') ?? 0.0 : 0.0;
      final cost = row.length > 4 ? (row[4]?.value is num ? (row[4]!.value as num).toDouble() : double.tryParse(row[4]?.value?.toString() ?? '0') ?? 0.0 : 0.0;
      final stock = row.length > 5 ? (row[5]?.value is num ? (row[5]!.value as num).toInt() : int.tryParse(row[5]?.value?.toString() ?? '0') ?? 0 : 0;

      await txn.insert('products', {
        'sku': sku,
        'name': name,
        'category': category,
        'default_sale_price': sale,
        'last_purchase_price': cost,
        'stock': stock,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}

Future<void> importCustomersXlsx(File file) async {
  final db = await _db();
  final bytes = await file.readAsBytes();
  final excel = Excel.decodeBytes(bytes);
  final sh = excel['customers'];
  await db.transaction((txn) async {
    for (int r = 1; r < sh.maxRows; r++) {
      final row = sh.row(r);
      if (row.isEmpty) continue;
      final phone = row[0]?.value?.toString().trim();
      if (phone == null || phone.isEmpty) continue;
      final name = row.length > 1 ? row[1]?.value?.toString() ?? '' : '';
      final address = row.length > 2 ? row[2]?.value?.toString() ?? '' : '';
      await txn.insert('customers', {
        'phone': phone,
        'name': name,
        'address': address,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}

Future<void> importSuppliersXlsx(File file) async {
  final db = await _db();
  final bytes = await file.readAsBytes();
  final excel = Excel.decodeBytes(bytes);
  final sh = excel['suppliers'];
  await db.transaction((txn) async {
    for (int r = 1; r < sh.maxRows; r++) {
      final row = sh.row(r);
      if (row.isEmpty) continue;
      final phone = row[0]?.value?.toString().trim();
      if (phone == null || phone.isEmpty) continue;
      final name = row.length > 1 ? row[1]?.value?.toString() ?? '' : '';
      final address = row.length > 2 ? row[2]?.value?.toString() ?? '' : '';
      await txn.insert('suppliers', {
        'phone': phone,
        'name': name,
        'address': address,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}

Future<void> importSalesXlsx(File file) async {
  final db = await _db();
  final bytes = await file.readAsBytes();
  final excel = Excel.decodeBytes(bytes);

  // sales
  final shSales = excel['sales'];
  // sale_items
  final shItems = excel['sale_items'];

  await db.transaction((txn) async {
    // encabezado desde fila 1
    for (int r = 1; r < shSales.maxRows; r++) {
      final row = shSales.row(r);
      if (row.isEmpty) continue;
      final id = int.tryParse(row[0]?.value?.toString() ?? '');
      if (id == null) continue;
      await txn.insert('sales', {
        'id': id,
        'customer_phone': row[1]?.value?.toString() ?? '',
        'payment_method': row[2]?.value?.toString() ?? '',
        'place': row[3]?.value?.toString() ?? '',
        'shipping_cost': double.tryParse(row[4]?.value?.toString() ?? '') ?? 0.0,
        'discount': double.tryParse(row[5]?.value?.toString() ?? '') ?? 0.0,
        'date': row[6]?.value?.toString() ?? '',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    for (int r = 1; r < shItems.maxRows; r++) {
      final row = shItems.row(r);
      if (row.isEmpty) continue;
      final saleId = int.tryParse(row[0]?.value?.toString() ?? '');
      final sku = row[1]?.value?.toString() ?? '';
      if (saleId == null || sku.isEmpty) continue;
      await txn.insert('sale_items', {
        'sale_id': saleId,
        'sku': sku,
        'quantity': int.tryParse(row[2]?.value?.toString() ?? '') ?? 0,
        'unit_price': double.tryParse(row[3]?.value?.toString() ?? '') ?? 0.0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}

Future<void> importPurchasesXlsx(File file) async {
  final db = await _db();
  final bytes = await file.readAsBytes();
  final excel = Excel.decodeBytes(bytes);

  final shP = excel['purchases'];
  final shI = excel['purchase_items'];

  await db.transaction((txn) async {
    for (int r = 1; r < shP.maxRows; r++) {
      final row = shP.row(r);
      if (row.isEmpty) continue;
      final id = int.tryParse(row[0]?.value?.toString() ?? '');
      if (id == null) continue;
      await txn.insert('purchases', {
        'id': id,
        'supplier_phone': row[1]?.value?.toString() ?? '',
        'folio': row[2]?.value?.toString() ?? '',
        'date': row[3]?.value?.toString() ?? '',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    for (int r = 1; r < shI.maxRows; r++) {
      final row = shI.row(r);
      if (row.isEmpty) continue;
      final pid = int.tryParse(row[0]?.value?.toString() ?? '');
      final sku = row[1]?.value?.toString() ?? '';
      if (pid == null || sku.isEmpty) continue;
      await txn.insert('purchase_items', {
        'purchase_id': pid,
        'sku': sku,
        'quantity': int.tryParse(row[2]?.value?.toString() ?? '') ?? 0,
        'unit_cost': double.tryParse(row[3]?.value?.toString() ?? '') ?? 0.0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}