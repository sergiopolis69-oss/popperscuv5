import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart' as ex;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:popperscuv5/data/database.dart' as appdb;

/// ===== Helpers para leer celdas (Excel 4.x) =====
String _asString(ex.Data? d) {
  if (d is ex.TextCellValue) {
    final v = (d as ex.TextCellValue).value;
    return v.text ?? '';
  }
  if (d is ex.DoubleCellValue) {
    final v = (d as ex.DoubleCellValue).value;
    return v.toString();
  }
  if (d is ex.IntCellValue) {
    final v = (d as ex.IntCellValue).value;
    return v.toString();
  }
  if (d is ex.DateCellValue) {
    final v = (d as ex.DateCellValue);
    // excel 4.0.6: sólo year/month/day
    final dt = DateTime(v.year, v.month, v.day);
    return dt.toIso8601String();
  }
  return (d?.value ?? '').toString();
}

double _asDouble(ex.Data? d) {
  if (d is ex.DoubleCellValue) {
    final v = (d as ex.DoubleCellValue).value;
    return v;
  }
  if (d is ex.IntCellValue) {
    final v = (d as ex.IntCellValue).value;
    return v.toDouble();
  }
  if (d is ex.TextCellValue) {
    final v = (d as ex.TextCellValue).value;
    final s = (v.text ?? '').replaceAll(',', '.');
    return double.tryParse(s) ?? 0.0;
  }
  return double.tryParse('${d?.value ?? ''}') ?? 0.0;
}

int _asInt(ex.Data? d) {
  if (d is ex.IntCellValue) {
    final v = (d as ex.IntCellValue).value;
    return v;
  }
  if (d is ex.DoubleCellValue) {
    final v = (d as ex.DoubleCellValue).value;
    return v.round();
  }
  if (d is ex.TextCellValue) {
    final v = (d as ex.TextCellValue).value;
    return int.tryParse(v.text ?? '') ?? 0;
  }
  return int.tryParse('${d?.value ?? ''}') ?? 0;
}

DateTime? _asDate(ex.Data? d) {
  if (d is ex.DateCellValue) {
    final v = (d as ex.DateCellValue);
    // excel 4.0.6: sólo year/month/day
    return DateTime(v.year, v.month, v.day);
  }
  if (d is ex.TextCellValue) {
    final v = (d as ex.TextCellValue).value;
    return DateTime.tryParse(v.text ?? '');
  }
  return null;
}

ex.Sheet _sheet(ex.Excel book, String name) => book.sheets[name] ?? book[name];

Future<File> _writeToDownloads(String filename, List<int> bytes) async {
  final dir = Directory('/storage/emulated/0/Download');
  final file = File(p.join(dir.path, filename));
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

/// ======================= EXPORT =======================

Future<void> exportProductsXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final rows = await db.query('products', orderBy: 'name COLLATE NOCASE');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'productos');
  sh.appendRow(['sku','name','category','default_sale_price','last_purchase_price','stock']
      .map((e) => ex.TextCellValue(e)).toList());
  for (final r in rows) {
    sh.appendRow([
      ex.TextCellValue((r['sku'] ?? '').toString()),
      ex.TextCellValue((r['name'] ?? '').toString()),
      ex.TextCellValue((r['category'] ?? '').toString()),
      ex.DoubleCellValue((r['default_sale_price'] as num?)?.toDouble() ?? 0),
      ex.DoubleCellValue((r['last_purchase_price'] as num?)?.toDouble() ?? 0),
      ex.IntCellValue((r['stock'] as num?)?.toInt() ?? 0),
    ]);
  }
  final bytes = book.save()!;
  await _writeToDownloads('products.xlsx', bytes);
}

Future<void> exportClientsXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final rows = await db.query('customers', orderBy: 'name COLLATE NOCASE');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'clientes');
  sh.appendRow(['phone','name','address'].map((e) => ex.TextCellValue(e)).toList());
  for (final r in rows) {
    sh.appendRow([
      ex.TextCellValue((r['phone'] ?? '').toString()),
      ex.TextCellValue((r['name'] ?? '').toString()),
      ex.TextCellValue((r['address'] ?? '').toString()),
    ]);
  }
  final bytes = book.save()!;
  await _writeToDownloads('clients.xlsx', bytes);
}

Future<void> exportSuppliersXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final rows = await db.query('suppliers', orderBy: 'name COLLATE NOCASE');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'proveedores');
  sh.appendRow(['phone','name','address'].map((e) => ex.TextCellValue(e)).toList());
  for (final r in rows) {
    sh.appendRow([
      ex.TextCellValue((r['phone'] ?? '').toString()),
      ex.TextCellValue((r['name'] ?? '').toString()),
      ex.TextCellValue((r['address'] ?? '').toString()),
    ]);
  }
  final bytes = book.save()!;
  await _writeToDownloads('suppliers.xlsx', bytes);
}

Future<void> exportSalesXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;

  final hdrSales = ['id','customer_phone','payment_method','place','shipping_cost','discount','date'];
  final hdrItems = ['sale_id','product_sku','quantity','unit_price'];

  final book = ex.Excel.createExcel();
  final s = _sheet(book, 'ventas');
  s.appendRow(hdrSales.map((e) => ex.TextCellValue(e)).toList());

  final si = _sheet(book, 'venta_items');
  si.appendRow(hdrItems.map((e) => ex.TextCellValue(e)).toList());

  final sales = await db.query('sales', orderBy: 'id');
  for (final r in sales) {
    s.appendRow([
      ex.IntCellValue((r['id'] as num?)?.toInt() ?? 0),
      ex.TextCellValue((r['customer_phone'] ?? '').toString()),
      ex.TextCellValue((r['payment_method'] ?? '').toString()),
      ex.TextCellValue((r['place'] ?? '').toString()),
      ex.DoubleCellValue((r['shipping_cost'] as num?)?.toDouble() ?? 0),
      ex.DoubleCellValue((r['discount'] as num?)?.toDouble() ?? 0),
      ex.TextCellValue((r['date'] ?? '').toString()),
    ]);

    final items = await db.rawQuery('''
      SELECT si.sale_id, p.sku AS product_sku, si.quantity, si.unit_price
      FROM sale_items si
      JOIN products p ON p.id=si.product_id
      WHERE si.sale_id=?
      ORDER BY si.id
    ''', [r['id']]);
    for (final it in items) {
      si.appendRow([
        ex.IntCellValue((it['sale_id'] as num?)?.toInt() ?? 0),
        ex.TextCellValue((it['product_sku'] ?? '').toString()),
        ex.IntCellValue((it['quantity'] as num?)?.toInt() ?? 0),
        ex.DoubleCellValue((it['unit_price'] as num?)?.toDouble() ?? 0),
      ]);
    }
  }

  final bytes = book.save()!;
  await _writeToDownloads('sales.xlsx', bytes);
}

Future<void> exportPurchasesXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;

  final hdrPurchases = ['id','folio','supplier_phone','date'];
  final hdrItems = ['purchase_id','product_sku','quantity','unit_cost'];

  final book = ex.Excel.createExcel();
  final s = _sheet(book, 'compras');
  s.appendRow(hdrPurchases.map((e) => ex.TextCellValue(e)).toList());
  final si = _sheet(book, 'compra_items');
  si.appendRow(hdrItems.map((e) => ex.TextCellValue(e)).toList());

  final purchases = await db.rawQuery('''
    SELECT pu.id AS id, pu.folio, s.phone AS supplier_phone, pu.date
    FROM purchases pu
    LEFT JOIN suppliers s ON s.id = pu.supplier_id
    ORDER BY pu.id
  ''');

  for (final r in purchases) {
    s.appendRow([
      ex.IntCellValue((r['id'] as num?)?.toInt() ?? 0),
      ex.TextCellValue((r['folio'] ?? '').toString()),
      ex.TextCellValue((r['supplier_phone'] ?? '').toString()),
      ex.TextCellValue((r['date'] ?? '').toString()),
    ]);

    final items = await db.rawQuery('''
      SELECT pi.purchase_id, p.sku AS product_sku, pi.quantity, pi.unit_cost
      FROM purchase_items pi
      JOIN products p ON p.id=pi.product_id
      WHERE pi.purchase_id=?
      ORDER BY pi.id
    ''', [r['id']]);
    for (final it in items) {
      si.appendRow([
        ex.IntCellValue((it['purchase_id'] as num?)?.toInt() ?? 0),
        ex.TextCellValue((it['product_sku'] ?? '').toString()),
        ex.IntCellValue((it['quantity'] as num?)?.toInt() ?? 0),
        ex.DoubleCellValue((it['unit_cost'] as num?)?.toDouble() ?? 0),
      ]);
    }
  }

  final bytes = book.save()!;
  await _writeToDownloads('purchases.xlsx', bytes);
}

/// ======================= IMPORT =======================

Future<int?> _ensureSupplierByPhone(DatabaseExecutor txn, String phone) async {
  if (phone.isEmpty) return null;
  final existing =
      await txn.query('suppliers', where: 'phone=?', whereArgs: [phone], limit: 1);
  if (existing.isNotEmpty) return existing.first['id'] as int;
  final id = await txn.insert('suppliers', {'phone': phone});
  return id;
}

Future<int> _ensureProductBySku(DatabaseExecutor txn, String sku) async {
  final p = await txn.query('products', where: 'sku=?', whereArgs: [sku], limit: 1);
  if (p.isNotEmpty) return p.first['id'] as int;
  final id = await txn.insert('products', {
    'sku': sku,
    'name': sku,
    'category': '',
    'default_sale_price': 0.0,
    'last_purchase_price': 0.0,
    'stock': 0,
  });
  return id;
}

Future<void> importProductsXlsx(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book['productos'];
  if (sh == null) throw Exception('Hoja "productos" no encontrada');

  final db = await appdb.DatabaseHelper.instance.db;
  await db.transaction((txn) async {
    for (int i = 1; i < sh.rows.length; i++) {
      final r = sh.rows[i];
      final sku = _asString(r.elementAtOrNull(0));
      if (sku.isEmpty) continue;
      final name = _asString(r.elementAtOrNull(1));
      final category = _asString(r.elementAtOrNull(2));
      final dsp = _asDouble(r.elementAtOrNull(3));
      final lpp = _asDouble(r.elementAtOrNull(4));
      final stock = _asInt(r.elementAtOrNull(5));

      final id = await _ensureProductBySku(txn, sku);
      await txn.update('products', {
        'name': name,
        'category': category,
        'default_sale_price': dsp,
        'last_purchase_price': lpp,
        'stock': stock,
      }, where: 'id=?', whereArgs: [id]);
    }
  });
}

Future<void> importClientsXlsx(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book['clientes'];
  if (sh == null) throw Exception('Hoja "clientes" no encontrada');

  final db = await appdb.DatabaseHelper.instance.db;
  await db.transaction((txn) async {
    for (int i = 1; i < sh.rows.length; i++) {
      final r = sh.rows[i];
      final phone = _asString(r.elementAtOrNull(0));
      if (phone.isEmpty) continue;
      await txn.insert('customers', {
        'phone': phone,
        'name': _asString(r.elementAtOrNull(1)),
        'address': _asString(r.elementAtOrNull(2)),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}

Future<void> importSuppliersXlsx(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book['proveedores'];
  if (sh == null) throw Exception('Hoja "proveedores" no encontrada');

  final db = await appdb.DatabaseHelper.instance.db;
  await db.transaction((txn) async {
    for (int i = 1; i < sh.rows.length; i++) {
      final r = sh.rows[i];
      final phone = _asString(r.elementAtOrNull(0));
      if (phone.isEmpty) continue;
      await txn.insert('suppliers', {
        'phone': phone,
        'name': _asString(r.elementAtOrNull(1)),
        'address': _asString(r.elementAtOrNull(2)),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}

Future<void> importSalesXlsx(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book['ventas'];
  final shi = book['venta_items'];
  if (sh == null || shi == null) {
    throw Exception('Hojas "ventas" y/o "venta_items" no encontradas');
  }

  final db = await appdb.DatabaseHelper.instance.db;
  await db.transaction((txn) async {
    for (int i = 1; i < sh.rows.length; i++) {
      final r = sh.rows[i];
      final id = _asInt(r.elementAtOrNull(0));
      await txn.insert('sales', {
        'id': id == 0 ? null : id,
        'customer_phone': _asString(r.elementAtOrNull(1)),
        'payment_method': _asString(r.elementAtOrNull(2)),
        'place': _asString(r.elementAtOrNull(3)),
        'shipping_cost': _asDouble(r.elementAtOrNull(4)),
        'discount': _asDouble(r.elementAtOrNull(5)),
        'date': _asString(r.elementAtOrNull(6)),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    for (int i = 1; i < shi.rows.length; i++) {
      final r = shi.rows[i];
      final sid = _asInt(r.elementAtOrNull(0));
      final sku = _asString(r.elementAtOrNull(1));
      if (sid == 0 || sku.isEmpty) continue;
      final pid = await _ensureProductBySku(txn, sku);
      await txn.insert('sale_items', {
        'sale_id': sid,
        'product_id': pid,
        'quantity': _asInt(r.elementAtOrNull(2)),
        'unit_price': _asDouble(r.elementAtOrNull(3)),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}

Future<void> importPurchasesXlsx(Uint8List bytes) async {
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book['compras'];
  final shi = book['compra_items'];
  if (sh == null || shi == null) {
    throw Exception('Hojas "compras" y/o "compra_items" no encontradas');
  }

  final db = await appdb.DatabaseHelper.instance.db;
  await db.transaction((txn) async {
    for (int i = 1; i < sh.rows.length; i++) {
      final r = sh.rows[i];
      final id = _asInt(r.elementAtOrNull(0));
      final phone = _asString(r.elementAtOrNull(2));
      final supId = await _ensureSupplierByPhone(txn, phone);
      await txn.insert('purchases', {
        'id': id == 0 ? null : id,
        'folio': _asString(r.elementAtOrNull(1)),
        'supplier_id': supId,
        'date': _asString(r.elementAtOrNull(3)),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    for (int i = 1; i < shi.rows.length; i++) {
      final r = shi.rows[i];
      final pid = _asInt(r.elementAtOrNull(0));
      final sku = _asString(r.elementAtOrNull(1));
      if (pid == 0 || sku.isEmpty) continue;
      final prodId = await _ensureProductBySku(txn, sku);
      await txn.insert('purchase_items', {
        'purchase_id': pid,
        'product_id': prodId,
        'quantity': _asInt(r.elementAtOrNull(2)),
        'unit_cost': _asDouble(r.elementAtOrNull(3)),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}