import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:sqflite/sqflite.dart';
import 'package:downloads_path_provider_28/downloads_path_provider_28.dart';
import '../data/database.dart';

Future<String> _downloadsPath() async {
  final dir = await DownloadsPathProvider.downloadsDirectory;
  return dir?.path ?? '/storage/emulated/0/Download';
}

// ------------------ EXPORT ------------------

Future<void> exportSalesXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.createExcel();

  final sales = await db.rawQuery('SELECT id, customer_phone, payment_method, place, shipping_cost, discount, date FROM sales ORDER BY date DESC');
  final items = await db.rawQuery('SELECT sale_id, sku, quantity, unit_price FROM sale_items');

  final shSales = excel['sales'];
  shSales.appendRow(['id','customer_phone','payment_method','place','shipping_cost','discount','date']);
  for (final s in sales) {
    shSales.appendRow([s['id'], s['customer_phone'], s['payment_method'], s['place'], s['shipping_cost'], s['discount'], s['date']]);
  }

  final shItems = excel['sale_items'];
  shItems.appendRow(['sale_id','sku','quantity','unit_price']);
  for (final it in items) {
    shItems.appendRow([it['sale_id'], it['sku'], it['quantity'], it['unit_price']]);
  }

  final bytes = Uint8List.fromList(excel.encode()!);
  final path = await _downloadsPath();
  final file = File('$path/ventas.xlsx');
  await file.writeAsBytes(bytes, flush: true);
}

Future<void> exportPurchasesXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.createExcel();

  final purchases = await db.rawQuery('SELECT id, supplier_id, folio, date FROM purchases ORDER BY date DESC');
  final items = await db.rawQuery('SELECT purchase_id, sku, quantity, unit_cost FROM purchase_items');

  final shP = excel['purchases'];
  shP.appendRow(['id','supplier_id','folio','date']);
  for (final p in purchases) {
    shP.appendRow([p['id'], p['supplier_id'], p['folio'], p['date']]);
  }

  final shI = excel['purchase_items'];
  shI.appendRow(['purchase_id','sku','quantity','unit_cost']);
  for (final it in items) {
    shI.appendRow([ it['purchase_id'], it['sku'], it['quantity'], it['unit_cost'] ]);
  }

  final bytes = Uint8List.fromList(excel.encode()!);
  final path = await _downloadsPath();
  final file = File('$path/compras.xlsx');
  await file.writeAsBytes(bytes, flush: true);
}

// ------------------ IMPORT ------------------

Future<void> importSalesXlsx(File file) async {
  final bytes = await file.readAsBytes();
  final excel = Excel.decodeBytes(bytes);
  final db = await DatabaseHelper.instance.db;
  final batch = db.batch();

  final sales = excel['sales'].rows.skip(1);
  final items = excel['sale_items'].rows.skip(1);

  final Map<int,int> idMap = {};
  for (final r in sales) {
    final oldId = (r[0]?.value as num).toInt();
    final newId = await db.insert('sales', {
      'customer_phone': r[1]?.value?.toString(),
      'payment_method': r[2]?.value?.toString(),
      'place': r[3]?.value?.toString(),
      'shipping_cost': (r[4]?.value as num?)?.toDouble() ?? 0.0,
      'discount': (r[5]?.value as num?)?.toDouble() ?? 0.0,
      'date': r[6]?.value?.toString(),
    });
    idMap[oldId] = newId;
  }

  for (final r in items) {
    final oldSale = (r[0]?.value as num).toInt();
    final sku = r[1]?.value?.toString();
    final qty = (r[2]?.value as num?)?.toInt() ?? 0;
    final price = (r[3]?.value as num?)?.toDouble() ?? 0.0;
    if (sku == null || sku.isEmpty || qty<=0) continue;

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
  }
  await batch.commit(noResult: true);
}

Future<void> importPurchasesXlsx(File file) async {
  final bytes = await file.readAsBytes();
  final excel = Excel.decodeBytes(bytes);
  final db = await DatabaseHelper.instance.db;
  final batch = db.batch();

  final purchases = excel['purchases'].rows.skip(1);
  final items = excel['purchase_items'].rows.skip(1);

  final Map<int,int> idMap = {};
  for (final r in purchases) {
    final oldId = (r[0]?.value as num).toInt();
    final newId = await db.insert('purchases', {
      'supplier_id': (r[1]?.value as num?)?.toInt(),
      'folio': r[2]?.value?.toString(),
      'date': r[3]?.value?.toString(),
    });
    idMap[oldId] = newId;
  }

  for (final r in items) {
    final oldPur = (r[0]?.value as num).toInt();
    final sku = r[1]?.value?.toString();
    final qty = (r[2]?.value as num?)?.toInt() ?? 0;
    final cost = (r[3]?.value as num?)?.toDouble() ?? 0.0;
    if (sku == null || sku.isEmpty || qty<=0) continue;

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
    batch.rawUpdate('UPDATE products SET stock = stock + ?, last_purchase_price = ?, last_purchase_date = ? WHERE id = ?',
      [qty, cost, DateTime.now().toIso8601String(), productId]);
  }
  await batch.commit(noResult: true);
}