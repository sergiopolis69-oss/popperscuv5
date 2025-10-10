import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database.dart';

/// ========= Helpers =========

Future<Database> _db() async => DatabaseHelper.instance.db;

/// Convierte a CellValue para Excel 4.x
CellValue _cv(dynamic v) {
  if (v == null) return const TextCellValue('');
  if (v is num) return DoubleCellValue(v.toDouble());
  return TextCellValue(v.toString());
}

/// Acceso seguro a la celda (puede no existir)
dynamic _val(List<Data?> row, int i) {
  if (i < 0 || i >= row.length) return null;
  return row[i]?.value;
}

String _str(List<Data?> row, int i) {
  final v = _val(row, i);
  return v == null ? '' : v.toString();
}

double _dbl(List<Data?> row, int i) {
  final v = _val(row, i);
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0.0;
}

int _int(List<Data?> row, int i) {
  final v = _val(row, i);
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

/// ========= EXPORT =========

Future<void> exportAllToXlsx() async {
  final db = await _db();
  final excel = Excel.createExcel();

  // PRODUCTS
  final shProd = excel['products'];
  shProd.appendRow(const [
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

  // CUSTOMERS
  final shCust = excel['customers'];
  shCust.appendRow(const [
    TextCellValue('phone'),
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

  // SUPPLIERS
  final shSupp = excel['suppliers'];
  shSupp.appendRow(const [
    TextCellValue('phone'),
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

  // SALES (header)
  final shSales = excel['sales'];
  shSales.appendRow(const [
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

  // SALE ITEMS (detalle con SKU)
  final shSaleItems = excel['sale_items'];
  shSaleItems.appendRow(const [
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

  // PURCHASES (header)
  final shPurch = excel['purchases'];
  shPurch.appendRow(const [
    TextCellValue('id'),
    TextCellValue('supplier_phone'),
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

  // PURCHASE ITEMS (detalle con SKU)
  final shPurchItems = excel['purchase_items'];
  shPurchItems.appendRow(const [
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

  // Guardar (diálogo del sistema). No usamos downloads_path_provider_28.
  final bytes = excel.encode()!;
  final u8 = Uint8List.fromList(bytes);
  final ts = DateTime.now().toIso8601String().replaceAll(':', '').replaceAll('.', '');
  await FileSaver.instance.saveFile(
    name: 'backup_$ts',
    bytes: u8,
    ext: 'xlsx',
    mimeType: MimeType.other, // seguro con FileSaver 0.2.x
  );
}

/// ========= IMPORT =========
/// Cada función hace upsert y asume encabezado en fila 0.

Future<void> importProductsXlsx(File file) async {
  final db = await _db();
  final bytes = await file.readAsBytes();
  final excel = Excel.decodeBytes(bytes);
  final sh = excel['products'];

  await db.transaction((txn) async {
    for (int r = 1; r < sh.maxRows; r++) {
      final row = sh.row(r);
      if (row.isEmpty) continue;

      final sku = _str(row, 0).trim();
      if (sku.isEmpty) continue;

      final name  = _str(row, 1);
      final cat   = _str(row, 2);
      final sale  = _dbl(row, 3);
      final cost  = _dbl(row, 4);
      final stock = _int(row, 5);

      await txn.insert('products', {
        'sku': sku,
        'name': name,
        'category': cat,
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

      final phone = _str(row, 0).trim();
      if (phone.isEmpty) continue;

      final name = _str(row, 1);
      final addr = _str(row, 2);

      await txn.insert('customers', {
        'phone': phone,
        'name': name,
        'address': addr,
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

      final phone = _str(row, 0).trim();
      if (phone.isEmpty) continue;

      final name = _str(row, 1);
      final addr = _str(row, 2);

      await txn.insert('suppliers', {
        'phone': phone,
        'name': name,
        'address': addr,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}

Future<void> importSalesXlsx(File file) async {
  final db = await _db();
  final bytes = await file.readAsBytes();
  final excel = Excel.decodeBytes(bytes);

  final shSales = excel['sales'];
  final shItems = excel['sale_items'];

  await db.transaction((txn) async {
    for (int r = 1; r < shSales.maxRows; r++) {
      final row = shSales.row(r);
      if (row.isEmpty) continue;

      final id = int.tryParse(_str(row, 0));
      if (id == null) continue;

      await txn.insert('sales', {
        'id': id,
        'customer_phone': _str(row, 1),
        'payment_method': _str(row, 2),
        'place': _str(row, 3),
        'shipping_cost': _dbl(row, 4),
        'discount': _dbl(row, 5),
        'date': _str(row, 6),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    for (int r = 1; r < shItems.maxRows; r++) {
      final row = shItems.row(r);
      if (row.isEmpty) continue;

      final saleId = int.tryParse(_str(row, 0));
      final sku    = _str(row, 1).trim();

      if (saleId == null || sku.isEmpty) continue;

      await txn.insert('sale_items', {
        'sale_id': saleId,
        'sku': sku,
        'quantity': _int(row, 2),
        'unit_price': _dbl(row, 3),
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

      final id = int.tryParse(_str(row, 0));
      if (id == null) continue;

      await txn.insert('purchases', {
        'id': id,
        'supplier_phone': _str(row, 1),
        'folio': _str(row, 2),
        'date': _str(row, 3),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    for (int r = 1; r < shI.maxRows; r++) {
      final row = shI.row(r);
      if (row.isEmpty) continue;

      final pid = int.tryParse(_str(row, 0));
      final sku = _str(row, 1).trim();
      if (pid == null || sku.isEmpty) continue;

      await txn.insert('purchase_items', {
        'purchase_id': pid,
        'sku': sku,
        'quantity': _int(row, 2),
        'unit_cost': _dbl(row, 3),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}