import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';

import '../data/db.dart' as appdb; // usamos appdb.getDb()

// ====== Paths / escritura ======

Future<String> _appDocsPath() async {
  final dir = await getApplicationDocumentsDirectory();
  return dir.path;
}

Future<String> _writeBytes(String fileName, List<int> bytes) async {
  final base = await _appDocsPath();
  final f = File('$base/$fileName');
  await f.create(recursive: true);
  await f.writeAsBytes(bytes, flush: true);
  return f.path;
}

// ====== Helpers Excel (4.0.6) ======

Sheet _sheet(Excel ex, String name) {
  // En excel 4.x acceder con ex['name'] crea la hoja si no existe
  return ex[name];
}

String _asString(dynamic v) {
  if (v == null) return '';
  final raw = (v is Data) ? v.value : v;
  if (raw == null) return '';
  return raw is String ? raw.trim() : raw.toString().trim();
}

double _asDouble(dynamic v) {
  if (v == null) return 0;
  final raw = (v is Data) ? v.value : v;
  if (raw is num) return raw.toDouble();
  final s = _asString(raw).replaceAll(',', '.');
  return double.tryParse(s) ?? 0;
}

int _asInt(dynamic v) {
  if (v == null) return 0;
  final raw = (v is Data) ? v.value : v;
  if (raw is num) return raw.toInt();
  return int.tryParse(_asString(raw)) ?? 0;
}

String _asDateText(dynamic v) {
  // Exportaremos fechas como texto yyyy-MM-dd para evitar DateCellValue
  final raw = (v is Data) ? v.value : v;
  if (raw is DateTime) return DateFormat('yyyy-MM-dd').format(raw);
  final s = _asString(raw);
  if (s.isEmpty) return '';
  // intenta parsear
  final d = DateTime.tryParse(s);
  return d == null ? s : DateFormat('yyyy-MM-dd').format(d);
}

// Convertir a CellValue esperado por excel 4.0.6
CellValue _cvText(String s) => TextCellValue(s);
CellValue _cvInt(int n) => IntCellValue(n);
CellValue _cvDouble(double d) => DoubleCellValue(d);

// ====== EXPORT ======

Future<String> exportProductsXlsx() async {
  final db = await appdb.getDb();
  final rows = await db.query('products', orderBy: 'name COLLATE NOCASE');

  final ex = Excel.createExcel();
  final sh = _sheet(ex, 'products');

  sh.appendRow([
    _cvText('sku'),
    _cvText('name'),
    _cvText('category'),
    _cvText('default_sale_price'),
    _cvText('last_purchase_price'),
    _cvText('stock'),
  ]);

  for (final r in rows) {
    sh.appendRow([
      _cvText((r['sku'] ?? '').toString()),
      _cvText((r['name'] ?? '').toString()),
      _cvText((r['category'] ?? '').toString()),
      _cvDouble((r['default_sale_price'] as num?)?.toDouble() ?? 0.0),
      _cvDouble((r['last_purchase_price'] as num?)?.toDouble() ?? 0.0),
      _cvInt((r['stock'] as num?)?.toInt() ?? 0),
    ]);
  }

  final bytes = ex.encode()!;
  return _writeBytes('productos.xlsx', bytes);
}

Future<String> exportClientsXlsx() async {
  final db = await appdb.getDb();
  final rows = await db.query('customers', orderBy: 'name COLLATE NOCASE');

  final ex = Excel.createExcel();
  final sh = _sheet(ex, 'clients');

  sh.appendRow([_cvText('phone'), _cvText('name'), _cvText('address')]);

  for (final r in rows) {
    sh.appendRow([
      _cvText((r['phone'] ?? '').toString()),
      _cvText((r['name'] ?? '').toString()),
      _cvText((r['address'] ?? '').toString()),
    ]);
  }

  final bytes = ex.encode()!;
  return _writeBytes('clientes.xlsx', bytes);
}

Future<String> exportSuppliersXlsx() async {
  final db = await appdb.getDb();
  final rows = await db.query('suppliers', orderBy: 'name COLLATE NOCASE');

  final ex = Excel.createExcel();
  final sh = _sheet(ex, 'suppliers');

  sh.appendRow([_cvText('phone'), _cvText('name'), _cvText('address')]);

  for (final r in rows) {
    sh.appendRow([
      _cvText((r['phone'] ?? '').toString()),
      _cvText((r['name'] ?? '').toString()),
      _cvText((r['address'] ?? '').toString()),
    ]);
  }

  final bytes = ex.encode()!;
  return _writeBytes('proveedores.xlsx', bytes);
}

Future<String> exportSalesXlsx() async {
  final db = await appdb.getDb();
  final sales = await db.query('sales', orderBy: 'date DESC, id DESC');
  final items = await db.query('sale_items', orderBy: 'sale_id');

  final ex = Excel.createExcel();

  final s = _sheet(ex, 'sales');
  s.appendRow([
    _cvText('id'),
    _cvText('customer_phone'),
    _cvText('payment_method'),
    _cvText('place'),
    _cvText('shipping_cost'),
    _cvText('discount'),
    _cvText('date'),
  ]);
  for (final r in sales) {
    s.appendRow([
      _cvInt((r['id'] as num?)?.toInt() ?? 0),
      _cvText((r['customer_phone'] ?? '').toString()),
      _cvText((r['payment_method'] ?? '').toString()),
      _cvText((r['place'] ?? '').toString()),
      _cvDouble((r['shipping_cost'] as num?)?.toDouble() ?? 0.0),
      _cvDouble((r['discount'] as num?)?.toDouble() ?? 0.0),
      _cvText(_asDateText(r['date'])),
    ]);
  }

  final si = _sheet(ex, 'sale_items');
  si.appendRow([_cvText('sale_id'), _cvText('product_sku'), _cvText('quantity'), _cvText('unit_price')]);
  for (final r in items) {
    si.appendRow([
      _cvInt((r['sale_id'] as num?)?.toInt() ?? 0),
      _cvText((r['product_sku'] ?? '').toString()),
      _cvInt((r['quantity'] as num?)?.toInt() ?? 0),
      _cvDouble((r['unit_price'] as num?)?.toDouble() ?? 0.0),
    ]);
  }

  final bytes = ex.encode()!;
  return _writeBytes('ventas.xlsx', bytes);
}

Future<String> exportPurchasesXlsx() async {
  final db = await appdb.getDb();
  final purchases = await db.query('purchases', orderBy: 'date DESC, id DESC');
  final items = await db.query('purchase_items', orderBy: 'purchase_id');

  final ex = Excel.createExcel();

  final s = _sheet(ex, 'purchases');
  s.appendRow([_cvText('id'), _cvText('folio'), _cvText('supplier_phone'), _cvText('date')]);
  for (final r in purchases) {
    s.appendRow([
      _cvInt((r['id'] as num?)?.toInt() ?? 0),
      _cvText((r['folio'] ?? '').toString()),
      _cvText((r['supplier_phone'] ?? '').toString()),
      _cvText(_asDateText(r['date'])),
    ]);
  }

  final si = _sheet(ex, 'purchase_items');
  si.appendRow([_cvText('purchase_id'), _cvText('product_sku'), _cvText('quantity'), _cvText('unit_cost')]);
  for (final r in items) {
    si.appendRow([
      _cvInt((r['purchase_id'] as num?)?.toInt() ?? 0),
      _cvText((r['product_sku'] ?? '').toString()),
      _cvInt((r['quantity'] as num?)?.toInt() ?? 0),
      _cvDouble((r['unit_cost'] as num?)?.toDouble() ?? 0.0),
    ]);
  }

  final bytes = ex.encode()!;
  return _writeBytes('compras.xlsx', bytes);
}

// ====== IMPORT ======

Future<void> importProductsXlsx(Uint8List bytes) async {
  final ex = Excel.decodeBytes(bytes);
  final sh = ex.sheets['products'] ?? ex.tables.values.firstOrNull;
  if (sh == null) throw 'Hoja "products" no encontrada';

  final db = await appdb.getDb();
  await db.transaction((txn) async {
    for (int i = 1; i < sh.maxRows; i++) {
      final row = sh.row(i);
      if (row.isEmpty) continue;

      final sku = _asString(row.elementAtOrNull(0)?.value);
      final name = _asString(row.elementAtOrNull(1)?.value);
      final category = _asString(row.elementAtOrNull(2)?.value);
      final salePrice = _asDouble(row.elementAtOrNull(3)?.value);
      final lastCost = _asDouble(row.elementAtOrNull(4)?.value);
      final stock = _asInt(row.elementAtOrNull(5)?.value);

      if (sku.isEmpty) continue;

      final existing = await txn.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
      if (existing.isEmpty) {
        await txn.insert('products', {
          'sku': sku,
          'name': name,
          'category': category,
          'default_sale_price': salePrice,
          'last_purchase_price': lastCost,
          'stock': stock,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      } else {
        await txn.update('products', {
          'name': name,
          'category': category,
          'default_sale_price': salePrice,
          'last_purchase_price': lastCost,
          'stock': stock,
        }, where: 'sku = ?', whereArgs: [sku]);
      }
    }
  });
}

Future<void> importClientsXlsx(Uint8List bytes) async {
  final ex = Excel.decodeBytes(bytes);
  final sh = ex.sheets['clients'] ?? ex.tables.values.firstOrNull;
  if (sh == null) throw 'Hoja "clients" no encontrada';

  final db = await appdb.getDb();
  await db.transaction((txn) async {
    for (int i = 1; i < sh.maxRows; i++) {
      final row = sh.row(i);
      if (row.isEmpty) continue;

      final phone = _asString(row.elementAtOrNull(0)?.value);
      final name = _asString(row.elementAtOrNull(1)?.value);
      final address = _asString(row.elementAtOrNull(2)?.value);

      if (phone.isEmpty) continue;

      final existing = await txn.query('customers', where: 'phone = ?', whereArgs: [phone], limit: 1);
      if (existing.isEmpty) {
        await txn.insert('customers', {'phone': phone, 'name': name, 'address': address},
            conflictAlgorithm: ConflictAlgorithm.abort);
      } else {
        await txn.update('customers', {'name': name, 'address': address}, where: 'phone = ?', whereArgs: [phone]);
      }
    }
  });
}

Future<void> importSuppliersXlsx(Uint8List bytes) async {
  final ex = Excel.decodeBytes(bytes);
  final sh = ex.sheets['suppliers'] ?? ex.tables.values.firstOrNull;
  if (sh == null) throw 'Hoja "suppliers" no encontrada';

  final db = await appdb.getDb();
  await db.transaction((txn) async {
    for (int i = 1; i < sh.maxRows; i++) {
      final row = sh.row(i);
      if (row.isEmpty) continue;

      final phone = _asString(row.elementAtOrNull(0)?.value);
      final name = _asString(row.elementAtOrNull(1)?.value);
      final address = _asString(row.elementAtOrNull(2)?.value);

      if (phone.isEmpty) continue;

      final existing = await txn.query('suppliers', where: 'phone = ?', whereArgs: [phone], limit: 1);
      if (existing.isEmpty) {
        await txn.insert('suppliers', {'phone': phone, 'name': name, 'address': address},
            conflictAlgorithm: ConflictAlgorithm.abort);
      } else {
        await txn.update('suppliers', {'name': name, 'address': address}, where: 'phone = ?', whereArgs: [phone]);
      }
    }
  });
}

Future<void> importSalesXlsx(Uint8List bytes) async {
  final ex = Excel.decodeBytes(bytes);
  final sh = ex.sheets['sales'];
  final si = ex.sheets['sale_items'];
  if (sh == null || si == null) throw 'Hojas "sales" y/o "sale_items" no encontradas';

  final db = await appdb.getDb();
  await db.transaction((txn) async {
    for (int i = 1; i < sh.maxRows; i++) {
      final row = sh.row(i);
      if (row.isEmpty) continue;

      final id = _asInt(row.elementAtOrNull(0)?.value);
      final phone = _asString(row.elementAtOrNull(1)?.value);
      final payment = _asString(row.elementAtOrNull(2)?.value);
      final place = _asString(row.elementAtOrNull(3)?.value);
      final shipping = _asDouble(row.elementAtOrNull(4)?.value);
      final discount = _asDouble(row.elementAtOrNull(5)?.value);
      final dateTxt = _asString(row.elementAtOrNull(6)?.value);

      await txn.insert('sales', {
        if (id > 0) 'id': id,
        'customer_phone': phone,
        'payment_method': payment,
        'place': place,
        'shipping_cost': shipping,
        'discount': discount,
        'date': dateTxt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    for (int i = 1; i < si.maxRows; i++) {
      final row = si.row(i);
      if (row.isEmpty) continue;

      final saleId = _asInt(row.elementAtOrNull(0)?.value);
      final sku = _asString(row.elementAtOrNull(1)?.value);
      final qty = _asInt(row.elementAtOrNull(2)?.value);
      final unit = _asDouble(row.elementAtOrNull(3)?.value);

      if (saleId <= 0 || sku.isEmpty || qty <= 0) continue;

      await txn.insert('sale_items', {
        'sale_id': saleId,
        'product_sku': sku,
        'quantity': qty,
        'unit_price': unit,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}

Future<void> importPurchasesXlsx(Uint8List bytes) async {
  final ex = Excel.decodeBytes(bytes);
  final sh = ex.sheets['purchases'];
  final si = ex.sheets['purchase_items'];
  if (sh == null || si == null) throw 'Hojas "purchases" y/o "purchase_items" no encontradas';

  final db = await appdb.getDb();
  await db.transaction((txn) async {
    for (int i = 1; i < sh.maxRows; i++) {
      final row = sh.row(i);
      if (row.isEmpty) continue;

      final id = _asInt(row.elementAtOrNull(0)?.value);
      final folio = _asString(row.elementAtOrNull(1)?.value);
      final supplier = _asString(row.elementAtOrNull(2)?.value);
      final dateTxt = _asString(row.elementAtOrNull(3)?.value);

      await txn.insert('purchases', {
        if (id > 0) 'id': id,
        'folio': folio,
        'supplier_phone': supplier,
        'date': dateTxt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    for (int i = 1; i < si.maxRows; i++) {
      final row = si.row(i);
      if (row.isEmpty) continue;

      final pid = _asInt(row.elementAtOrNull(0)?.value);
      final sku = _asString(row.elementAtOrNull(1)?.value);
      final qty = _asInt(row.elementAtOrNull(2)?.value);
      final cost = _asDouble(row.elementAtOrNull(3)?.value);

      if (pid <= 0 || sku.isEmpty || qty <= 0) continue;

      // Mapear sku -> id de producto
      final prod = await txn.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
      if (prod.isEmpty) continue;
      final productId = prod.first['id'] as int;

      await txn.insert('purchase_items', {
        'purchase_id': pid,
        'product_id': productId,
        'quantity': qty,
        'unit_cost': cost,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.rawUpdate(
        'UPDATE products SET stock = COALESCE(stock,0)+?, last_purchase_price = ? WHERE id = ?',
        [qty, cost, productId],
      );
    }
  });
}