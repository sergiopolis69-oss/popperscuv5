import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

const _xlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

// --------- EXPORT ---------

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
  shSales.appendRow(
      ['id','customer_phone','payment_method','place','shipping_cost','discount','date']);
  for (final s in sales) {
    shSales.appendRow([
      s['id'], s['customer_phone'], s['payment_method'], s['place'],
      s['shipping_cost'], s['discount'], s['date']
    ]);
  }

  final shItems = excel['sale_items'];
  shItems.appendRow(['sale_id','sku','quantity','unit_price']);
  for (final it in items) {
    shItems.appendRow([it['sale_id'], it['sku'], it['quantity'], it['unit_price']]);
  }

  final bytes = Uint8List.fromList(excel.encode()!);
  await FileSaver.instance.saveFile(
    name: 'ventas',
    bytes: bytes,
    ext: 'xlsx',
    mimeType: _xlsxMime,
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
  shP.appendRow(['id','supplier_id','folio','date']);
  for (final p in purchases) {
    shP.appendRow([p['id'], p['supplier_id'], p['folio'], p['date']]);
  }

  final shI = excel['purchase_items'];
  shI.appendRow(['purchase_id','sku','quantity','unit_cost']);
  for (final it in items) {
    shI.appendRow([it['purchase_id'], it['sku'], it['quantity'], it['unit_cost']]);
  }

  final bytes = Uint8List.fromList(excel.encode()!);
  await FileSaver.instance.saveFile(
    name: 'compras',
    bytes: bytes,
    ext: 'xlsx',
    mimeType: _xlsxMime,
  );
}

// --------- IMPORT (usa file_picker para elegir el .xlsx) ---------

Future<void> _importWithResolver({
  required String sheetHeaderName,
  required Future<int> Function(List<Data?> row) insertHeader,
  required Future<void> Function(List<Data?> row, Map<int,int> idMap) insertItem,
}) async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
  );
  if (res == null || res.files.isEmpty) return;
  final path = res.files.single.path;
  if (path == null) return;

  final bytes = await File(path).readAsBytes();
  final excel = Excel.decodeBytes(bytes);

  // Cabeceras / headers (ventas o compras)
  final headerSheet = excel[sheetHeaderName];
  final itemsSheet  = excel['${sheetHeaderName.substring(0, sheetHeaderName.length)}_items']; // 'sales' -> 'sale_items', 'purchases' -> 'purchase_items'
  // Mejor explícito:
  // si sheetHeaderName == 'sales' -> itemsSheet = excel['sale_items']
  // si 'purchases' -> excel['purchase_items']
  final items = excel[sheetHeaderName == 'sales' ? 'sale_items' : 'purchase_items'];

  final headerRows = headerSheet.rows.skip(1); // salta encabezado
  final idMap = <int,int>{};
  for (final r in headerRows) {
    final newId = await insertHeader(r);
    // oldId está en la primera columna
    final oldId = (r[0]?.value as num).toInt();
    idMap[oldId] = newId;
  }

  final itemRows = items.rows.skip(1);
  for (final r in itemRows) {
    await insertItem(r, idMap);
  }
}

Future<void> importSalesXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final batch = db.batch();

  await _importWithResolver(
    sheetHeaderName: 'sales',
    insertHeader: (row) async {
      return await db.insert('sales', {
        'customer_phone': row[1]?.value?.toString(),
        'payment_method': row[2]?.value?.toString(),
        'place': row[3]?.value?.toString(),
        'shipping_cost': (row[4]?.value as num?)?.toDouble() ?? 0.0,
        'discount': (row[5]?.value as num?)?.toDouble() ?? 0.0,
        'date': row[6]?.value?.toString(),
      });
    },
    insertItem: (row, idMap) async {
      final oldSale = (row[0]?.value as num).toInt();
      final sku = row[1]?.value?.toString();
      final qty = (row[2]?.value as num?)?.toInt() ?? 0;
      final price = (row[3]?.value as num?)?.toDouble() ?? 0.0;
      if (sku == null || sku.isEmpty || qty <= 0) return;

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

      batch.insert('sale_items', {
        'sale_id': idMap[oldSale],
        'product_id': productId,
        'sku': sku,
        'quantity': qty,
        'unit_price': price,
      });
    },
  );

  await batch.commit(noResult: true);
}

Future<void> importPurchasesXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final batch = db.batch();

  await _importWithResolver(
    sheetHeaderName: 'purchases',
    insertHeader: (row) async {
      return await db.insert('purchases', {
        'supplier_id': (row[1]?.value as num?)?.toInt(),
        'folio': row[2]?.value?.toString(),
        'date': row[3]?.value?.toString(),
      });
    },
    insertItem: (row, idMap) async {
      final oldPur = (row[0]?.value as num).toInt();
      final sku = row[1]?.value?.toString();
      final qty = (row[2]?.value as num?)?.toInt() ?? 0;
      final cost = (row[3]?.value as num?)?.toDouble() ?? 0.0;
      if (sku == null || sku.isEmpty || qty <= 0) return;

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

      batch.insert('purchase_items', {
        'purchase_id': idMap[oldPur],
        'product_id': productId,
        'sku': sku,
        'quantity': qty,
        'unit_cost': cost,
      });
      batch.rawUpdate(
        'UPDATE products SET stock = stock + ?, last_purchase_price = ?, last_purchase_date = ? WHERE id = ?',
        [qty, cost, DateTime.now().toIso8601String(), productId],
      );
    },
  );

  await batch.commit(noResult: true);
}