import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db.dart' as appdb;

// ===== Helpers de celdas (lectura) =====

String _toStr(dynamic v) {
  if (v == null) return '';
  if (v is TextCellValue) return v.value;
  return v.toString();
}

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is DoubleCellValue) return v.value;
  if (v is IntCellValue) return v.value.toDouble();
  if (v is TextCellValue) return double.tryParse(v.value.replaceAll(',', '.')) ?? 0;
  if (v is num) return v.toDouble();
  return 0;
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is IntCellValue) return v.value;
  if (v is DoubleCellValue) return v.value.round();
  if (v is TextCellValue) return int.tryParse(v.value) ?? 0;
  if (v is num) return v.toInt();
  return 0;
}

DateTime? _toDate(dynamic v) {
  if (v == null) return null;
  if (v is DateCellValue) {
    return DateTime(v.year, v.month, v.day, v.hour, v.minute, v.second);
  }
  if (v is TextCellValue) {
    final s = v.value.trim();
    final p1 = DateTime.tryParse(s);
    if (p1 != null) return p1;
  }
  if (v is DateTime) return v;
  return null;
}

// ===== Helpers de celdas (escritura) =====

TextCellValue cvText(String s) => TextCellValue(s);
DoubleCellValue cvDouble(double n) => DoubleCellValue(n);
IntCellValue cvInt(int n) => IntCellValue(n);
DateCellValue cvDate(DateTime d) => DateCellValue(
  year: d.year,
  month: d.month,
  day: d.day,
  hour: d.hour,
  minute: d.minute,
  second: d.second,
);

// ===== Guardado de archivo en carpeta interna (retorna path) =====

Future<String> _saveXlsxToAppDocs(Excel ex, String baseName) async {
  final bytes = Uint8List.fromList(ex.encode()!);
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, '$baseName.xlsx'));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

// ===== Export: Productos, Clientes, Proveedores, Ventas, Compras =====

Future<String> exportProductsXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final rows = await db.query('products',
      columns: ['sku','name','category','default_sale_price','last_purchase_price','stock'],
      orderBy: 'name COLLATE NOCASE');

  final ex = Excel.createExcel();
  final sh = ex['products'];
  sh.appendRow([
    cvText('sku'),
    cvText('name'),
    cvText('category'),
    cvText('default_sale_price'),
    cvText('last_purchase_price'),
    cvText('stock'),
  ]);

  for (final r in rows) {
    sh.appendRow([
      cvText((r['sku'] ?? '').toString()),
      cvText((r['name'] ?? '').toString()),
      cvText((r['category'] ?? '').toString()),
      cvDouble(((r['default_sale_price'] as num?)?.toDouble() ?? 0)),
      cvDouble(((r['last_purchase_price'] as num?)?.toDouble() ?? 0)),
      cvInt(((r['stock'] as num?)?.toInt() ?? 0)),
    ]);
  }
  return _saveXlsxToAppDocs(ex, 'productos_export');
}

Future<String> exportClientsXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final rows = await db.query('customers', columns: ['phone','name','address'], orderBy: 'name COLLATE NOCASE');

  final ex = Excel.createExcel();
  final sh = ex['customers'];
  sh.appendRow([cvText('phone'), cvText('name'), cvText('address')]);
  for (final r in rows) {
    sh.appendRow([
      cvText((r['phone'] ?? '').toString()),
      cvText((r['name'] ?? '').toString()),
      cvText((r['address'] ?? '').toString()),
    ]);
  }
  return _saveXlsxToAppDocs(ex, 'clientes_export');
}

Future<String> exportSuppliersXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final rows = await db.query('suppliers', columns: ['phone','name','address'], orderBy: 'name COLLATE NOCASE');

  final ex = Excel.createExcel();
  final sh = ex['suppliers'];
  sh.appendRow([cvText('phone'), cvText('name'), cvText('address')]);
  for (final r in rows) {
    sh.appendRow([
      cvText((r['phone'] ?? '').toString()),
      cvText((r['name'] ?? '').toString()),
      cvText((r['address'] ?? '').toString()),
    ]);
  }
  return _saveXlsxToAppDocs(ex, 'proveedores_export');
}

Future<String> exportSalesXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final sales = await db.query('sales',
      columns: ['id','customer_phone','payment_method','place','shipping_cost','discount','date'],
      orderBy: 'date DESC');

  final items = await db.query('sale_items',
      columns: ['sale_id','product_id','quantity','unit_price']);

  // Mapa producto_id -> sku
  final prodRows = await db.query('products', columns: ['id','sku']);
  final skuById = { for (final r in prodRows) (r['id'] as int): r['sku'] as String };

  final ex = Excel.createExcel();
  final sh = ex['sales'];
  sh.appendRow([
    cvText('id'),
    cvText('customer_phone'),
    cvText('payment_method'),
    cvText('place'),
    cvText('shipping_cost'),
    cvText('discount'),
    cvText('date'),
  ]);
  for (final r in sales) {
    final d = DateTime.tryParse((r['date'] ?? '').toString());
    sh.appendRow([
      cvInt((r['id'] as int?) ?? 0),
      cvText((r['customer_phone'] ?? '').toString()),
      cvText((r['payment_method'] ?? '').toString()),
      cvText((r['place'] ?? '').toString()),
      cvDouble(((r['shipping_cost'] as num?)?.toDouble() ?? 0)),
      cvDouble(((r['discount'] as num?)?.toDouble() ?? 0)),
      d == null ? cvText('') : cvDate(d),
    ]);
  }

  final si = ex['sale_items'];
  si.appendRow([cvText('sale_id'), cvText('product_sku'), cvText('quantity'), cvText('unit_price')]);
  for (final r in items) {
    si.appendRow([
      cvInt((r['sale_id'] as int?) ?? 0),
      cvText(skuById[(r['product_id'] as int? ?? 0)] ?? ''),
      cvInt((r['quantity'] as int?) ?? 0),
      cvDouble(((r['unit_price'] as num?)?.toDouble() ?? 0)),
    ]);
  }

  return _saveXlsxToAppDocs(ex, 'ventas_export');
}

Future<String> exportPurchasesXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final purchases = await db.query('purchases',
      columns: ['id','folio','supplier_phone','date'],
      orderBy: 'date DESC');

  final items = await db.query('purchase_items',
      columns: ['purchase_id','product_id','quantity','unit_cost']);

  // Mapa producto_id -> sku
  final prodRows = await db.query('products', columns: ['id','sku']);
  final skuById = { for (final r in prodRows) (r['id'] as int): r['sku'] as String };

  final ex = Excel.createExcel();
  final sh = ex['purchases'];
  sh.appendRow([cvText('id'), cvText('folio'), cvText('supplier_id'), cvText('date')]);
  for (final r in purchases) {
    final d = DateTime.tryParse((r['date'] ?? '').toString());
    sh.appendRow([
      cvInt((r['id'] as int?) ?? 0),
      cvText((r['folio'] ?? '').toString()),
      cvText((r['supplier_phone'] ?? '').toString()),
      d == null ? cvText('') : cvDate(d),
    ]);
  }

  final si = ex['purchase_items'];
  si.appendRow([cvText('purchase_id'), cvText('product_sku'), cvText('quantity'), cvText('unit_cost')]);
  for (final r in items) {
    si.appendRow([
      cvInt((r['purchase_id'] as int?) ?? 0),
      cvText(skuById[(r['product_id'] as int? ?? 0)] ?? ''),
      cvInt((r['quantity'] as int?) ?? 0),
      cvDouble(((r['unit_cost'] as num?)?.toDouble() ?? 0)),
    ]);
  }

  return _saveXlsxToAppDocs(ex, 'compras_export');
}

// ===== Import: Productos, Clientes, Proveedores, Ventas, Compras =====
// Nota: El SKU es clave única de producto. No se insertan productos sin SKU.

Future<void> importProductsXlsx(Uint8List bytes) async {
  final ex = Excel.decodeBytes(bytes);
  final sh = ex['products'];
  if (sh.maxRows <= 1) return; // solo encabezados

  final db = await appdb.DatabaseHelper.instance.db;
  final batch = db.batch();

  // Encabezados: sku, name, category, default_sale_price, last_purchase_price, stock
  for (int i = 1; i < sh.rows.length; i++) {
    final row = sh.rows[i];
    final sku = _toStr(row[0]?.value).trim();
    if (sku.isEmpty) continue; // obligatorio

    final name = _toStr(row[1]?.value);
    final category = _toStr(row[2]?.value);
    final sp = _toDouble(row[3]?.value);
    final lp = _toDouble(row[4]?.value);
    final stock = _toInt(row[5]?.value);

    // upsert por sku
    batch.insert('products', {
      'sku': sku,
      'name': name,
      'category': category,
      'default_sale_price': sp,
      'last_purchase_price': lp,
      'stock': stock,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  await batch.commit(noResult: true);
}

Future<void> importClientsXlsx(Uint8List bytes) async {
  final ex = Excel.decodeBytes(bytes);
  final sh = ex['customers'];
  if (sh.maxRows <= 1) return;

  final db = await appdb.DatabaseHelper.instance.db;
  final batch = db.batch();

  // phone, name, address
  for (int i = 1; i < sh.rows.length; i++) {
    final row = sh.rows[i];
    final phone = _toStr(row[0]?.value).trim();
    if (phone.isEmpty) continue;

    final name = _toStr(row[1]?.value);
    final address = _toStr(row[2]?.value);

    batch.insert('customers', {
      'phone': phone,
      'name': name,
      'address': address,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

Future<void> importSuppliersXlsx(Uint8List bytes) async {
  final ex = Excel.decodeBytes(bytes);
  final sh = ex['suppliers'];
  if (sh.maxRows <= 1) return;

  final db = await appdb.DatabaseHelper.instance.db;
  final batch = db.batch();

  // phone, name, address
  for (int i = 1; i < sh.rows.length; i++) {
    final row = sh.rows[i];
    final phone = _toStr(row[0]?.value).trim();
    if (phone.isEmpty) continue;
    final name = _toStr(row[1]?.value);
    final address = _toStr(row[2]?.value);

    batch.insert('suppliers', {
      'phone': phone,
      'name': name,
      'address': address,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

Future<void> importSalesXlsx(Uint8List bytes) async {
  final ex = Excel.decodeBytes(bytes);
  final sh = ex['sales'];
  final si = ex['sale_items'];
  if (sh.maxRows <= 1) return;

  final db = await appdb.DatabaseHelper.instance.db;
  await db.transaction((txn) async {
    // Mapa sku -> id de producto
    final prodRows = await txn.query('products', columns: ['id','sku']);
    final idBySku = { for (final r in prodRows) (r['sku'] as String): (r['id'] as int) };

    // Insertar ventas
    for (int i = 1; i < sh.rows.length; i++) {
      final row = sh.rows[i];
      final id = _toInt(row[0]?.value);
      final phone = _toStr(row[1]?.value);
      final pay = _toStr(row[2]?.value);
      final place = _toStr(row[3]?.value);
      final ship = _toDouble(row[4]?.value);
      final disc = _toDouble(row[5]?.value);
      final d = _toDate(row[6]?.value) ?? DateTime.now();

      await txn.insert('sales', {
        'id': id == 0 ? null : id,
        'customer_phone': phone.isEmpty ? null : phone,
        'payment_method': pay,
        'place': place,
        'shipping_cost': ship,
        'discount': disc,
        'date': d.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // Ítems
    if (si.maxRows > 1) {
      for (int i = 1; i < si.rows.length; i++) {
        final row = si.rows[i];
        final saleId = _toInt(row[0]?.value);
        final sku = _toStr(row[1]?.value);
        final qty = _toInt(row[2]?.value);
        final unit = _toDouble(row[3]?.value);
        if (saleId == 0 || sku.isEmpty || qty <= 0) continue;

        final pid = idBySku[sku];
        if (pid == null) continue;

        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': pid,
          'quantity': qty,
          'unit_price': unit,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  });
}

Future<void> importPurchasesXlsx(Uint8List bytes) async {
  final ex = Excel.decodeBytes(bytes);
  final sh = ex['purchases'];
  final si = ex['purchase_items'];
  if (sh.maxRows <= 1) return;

  final db = await appdb.DatabaseHelper.instance.db;
  await db.transaction((txn) async {
    // Mapa sku -> id
    final prodRows = await txn.query('products', columns: ['id','sku']);
    final idBySku = { for (final r in prodRows) (r['sku'] as String): (r['id'] as int) };

    // Cabecera
    for (int i = 1; i < sh.rows.length; i++) {
      final row = sh.rows[i];
      final id = _toInt(row[0]?.value);
      final folio = _toStr(row[1]?.value);
      final supplier = _toStr(row[2]?.value);
      final d = _toDate(row[3]?.value) ?? DateTime.now();

      await txn.insert('purchases', {
        'id': id == 0 ? null : id,
        'folio': folio,
        'supplier_phone': supplier,
        'date': d.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // Líneas
    if (si.maxRows > 1) {
      for (int i = 1; i < si.rows.length; i++) {
        final row = si.rows[i];
        final purchaseId = _toInt(row[0]?.value);
        final sku = _toStr(row[1]?.value);
        final qty = _toInt(row[2]?.value);
        final cost = _toDouble(row[3]?.value);
        if (purchaseId == 0 || sku.isEmpty || qty <= 0) continue;
        final pid = idBySku[sku];
        if (pid == null) continue;

        await txn.insert('purchase_items', {
          'purchase_id': purchaseId,
          'product_id': pid,
          'quantity': qty,
          'unit_cost': cost,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        // Ajuste de stock y último costo
        await txn.rawUpdate(
          'UPDATE products SET stock = COALESCE(stock,0)+?, last_purchase_price = ? WHERE id = ?',
          [qty, cost, pid],
        );
      }
    }
  });
}