import 'dart:typed_data';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

// Conversión segura a CellValue para excel 4.x
CellValue _cv(dynamic v) {
  if (v == null) return TextCellValue('');
  if (v is int) return IntCellValue(v);
  if (v is num) return DoubleCellValue(v.toDouble());
  return TextCellValue(v.toString());
}

// ===================== EXPORT =====================

Future<void> exportSalesXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.createExcel();

  final sales = await db.rawQuery('''
    SELECT id, customer_phone, payment_method, place, shipping_cost, discount, date
    FROM sales ORDER BY date DESC
  ''');

  final items = await db.rawQuery('''
    SELECT sale_id, sku, quantity, unit_price
    FROM sale_items
  ''');

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

  final shItems = excel['sale_items'];
  shItems.appendRow([
    TextCellValue('sale_id'),
    TextCellValue('sku'),
    TextCellValue('quantity'),
    TextCellValue('unit_price'),
  ]);
  for (final it in items) {
    shItems.appendRow([
      _cv(it['sale_id']),
      _cv(it['sku']),
      _cv(it['quantity']),
      _cv(it['unit_price']),
    ]);
  }

  final bytes = Uint8List.fromList(excel.encode()!);
  await FileSaver.instance.saveFile(
    name: 'ventas',
    bytes: bytes,
    ext: 'xlsx',
    mimeType: MimeType.microsoftExcel, // ✅ correcto para file_saver ^0.2.x
  );
}

Future<void> exportPurchasesXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.createExcel();

  final purchases = await db.rawQuery('''
    SELECT id, supplier_id, folio, date
    FROM purchases ORDER BY date DESC
  ''');

  final items = await db.rawQuery('''
    SELECT purchase_id, sku, quantity, unit_cost
    FROM purchase_items
  ''');

  final shP = excel['purchases'];
  shP.appendRow([
    TextCellValue('id'),
    TextCellValue('supplier_id'),
    TextCellValue('folio'),
    TextCellValue('date'),
  ]);
  for (final p in purchases) {
    shP.appendRow([
      _cv(p['id']),
      _cv(p['supplier_id']),
      _cv(p['folio']),
      _cv(p['date']),
    ]);
  }

  final shI = excel['purchase_items'];
  shI.appendRow([
    TextCellValue('purchase_id'),
    TextCellValue('sku'),
    TextCellValue('quantity'),
    TextCellValue('unit_cost'),
  ]);
  for (final it in items) {
    shI.appendRow([
      _cv(it['purchase_id']),
      _cv(it['sku']),
      _cv(it['quantity']),
      _cv(it['unit_cost']),
    ]);
  }

  final bytes = Uint8List.fromList(excel.encode()!);
  await FileSaver.instance.saveFile(
    name: 'compras',
    bytes: bytes,
    ext: 'xlsx',
    mimeType: MimeType.microsoftExcel,
  );
}

// ===================== IMPORT =====================
// Usa FilePicker internamente. No requiere parámetros.

Future<void> importSalesXlsx() async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
  );
  if (res == null || res.files.isEmpty) return;
  final path = res.files.single.path;
  if (path == null) return;

  final bytes = await File(path).readAsBytes();
  final excel = Excel.decodeBytes(bytes);

  final db = await DatabaseHelper.instance.db;

  final header = excel['sales'];
  final items  = excel['sale_items'];

  // Mapa oldId -> newId
  final idMap = <int, int>{};

  for (final r in header.rows.skip(1)) {
    final newId = await db.insert('sales', {
      'customer_phone': r[1]?.value?.toString(),
      'payment_method': r[2]?.value?.toString(),
      'place': r[3]?.value?.toString(),
      'shipping_cost': (r[4]?.value as num?)?.toDouble() ?? 0.0,
      'discount': (r[5]?.value as num?)?.toDouble() ?? 0.0,
      'date': r[6]?.value?.toString(),
    });
    final oldId = (r[0]?.value as num).toInt();
    idMap[oldId] = newId;
  }

  for (final r in items.rows.skip(1)) {
    final oldSale = (r[0]?.value as num).toInt();
    final sku = r[1]?.value?.toString();
    final qty = (r[2]?.value as num?)?.toInt() ?? 0;
    final price = (r[3]?.value as num?)?.toDouble() ?? 0.0;
    if (sku == null || sku.isEmpty || qty <= 0) continue;

    final prod = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
    int productId;
    if (prod.isEmpty) {
      productId = await db.insert('products', {
        'sku': sku,
        'name': 'SKU $sku',
        'default_sale_price': price,
        'last_purchase_price': 0.0,
        'stock': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      if (productId == 0) {
        final again = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
        productId = again.first['id'] as int;
      }
    } else {
      productId = prod.first['id'] as int;
    }

    await db.insert('sale_items', {
      'sale_id': idMap[oldSale],
      'product_id': productId,
      'sku': sku,
      'quantity': qty,
      'unit_price': price,
    });
  }
}

Future<void> importPurchasesXlsx() async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
  );
  if (res == null || res.files.isEmpty) return;
  final path = res.files.single.path;
  if (path == null) return;

  final bytes = await File(path).readAsBytes();
  final excel = Excel.decodeBytes(bytes);

  final db = await DatabaseHelper.instance.db;

  final header = excel['purchases'];
  final items  = excel['purchase_items'];

  final idMap = <int, int>{};

  for (final r in header.rows.skip(1)) {
    final newId = await db.insert('purchases', {
      'supplier_id': (r[1]?.value as num?)?.toInt(),
      'folio': r[2]?.value?.toString(),
      'date': r[3]?.value?.toString(),
    });
    final oldId = (r[0]?.value as num).toInt();
    idMap[oldId] = newId;
  }

  for (final r in items.rows.skip(1)) {
    final oldPur = (r[0]?.value as num).toInt();
    final sku = r[1]?.value?.toString();
    final qty = (r[2]?.value as num?)?.toInt() ?? 0;
    final cost = (r[3]?.value as num?)?.toDouble() ?? 0.0;
    if (sku == null || sku.isEmpty || qty <= 0) continue;

    final prod = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
    int productId;
    if (prod.isEmpty) {
      productId = await db.insert('products', {
        'sku': sku,
        'name': 'SKU $sku',
        'last_purchase_price': cost,
        'default_sale_price': 0.0,
        'stock': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      if (productId == 0) {
        final again = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
        productId = again.first['id'] as int;
      }
    } else {
      productId = prod.first['id'] as int;
    }

    await db.insert('purchase_items', {
      'purchase_id': idMap[oldPur],
      'product_id': productId,
      'sku': sku,
      'quantity': qty,
      'unit_cost': cost,
    });

    await db.rawUpdate(
      'UPDATE products SET stock = stock + ?, last_purchase_price = ?, last_purchase_date = ? WHERE id = ?',
      [qty, cost, DateTime.now().toIso8601String(), productId],
    );
  }
}