import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db.dart' as appdb;

/// ===== Helpers de IO =====

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

/// ===== Helpers de Excel (sin tipos internos de excel) =====

Sheet _getOrCreate(Excel ex, String name) {
  final existing = ex.sheets[name];
  if (existing != null) return existing;
  ex.insertSheet(name);
  return ex.sheets[name]!;
}

String _asString(dynamic v) {
  if (v == null) return '';
  // Evita usar TextCellValue / Data explícitos
  return v is String ? v.trim() : v.toString().trim();
}

double _asDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  final s = _asString(v).replaceAll(',', '.');
  return double.tryParse(s) ?? 0;
}

int _asInt(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(_asString(v)) ?? 0;
}

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  // intenta ISO
  final s = _asString(v);
  try {
    return DateTime.tryParse(s);
  } catch (_) {
    return null;
  }
}

CellValue _cv(dynamic v) {
  // excel 4.x acepta primitivos directamente en appendRow; pero para seguridad
  // devolvemos TextCellValue para textos, y números directos.
  if (v == null) return const TextCellValue('');
  if (v is num) return v is int ? IntCellValue(v) : DoubleCellValue(v.toDouble());
  if (v is DateTime) {
    // excel 4.x también acepta Fecha como texto ISO para evitar problemas de zona
    return TextCellValue(v.toIso8601String());
  }
  return TextCellValue(_asString(v));
}

/// ====== EXPORT ======
/// Rutas devueltas: archivo dentro de Documents de la app.

Future<String> exportProductsXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final rows = await db.query('products', orderBy: 'name COLLATE NOCASE');

  final ex = Excel.createExcel();
  final sh = _getOrCreate(ex, 'products');
  sh.appendRow([
    const TextCellValue('sku'),
    const TextCellValue('name'),
    const TextCellValue('category'),
    const TextCellValue('default_sale_price'),
    const TextCellValue('last_purchase_price'),
    const TextCellValue('stock'),
  ]);
  for (final r in rows) {
    sh.appendRow([
      _cv(r['sku']),
      _cv(r['name']),
      _cv(r['category']),
      _cv((r['default_sale_price'] as num?)?.toDouble() ?? 0),
      _cv((r['last_purchase_price'] as num?)?.toDouble() ?? 0),
      _cv((r['stock'] as num?)?.toInt() ?? 0),
    ]);
  }

  final bytes = ex.encode();
  final path = await _writeBytes('productos.xlsx', bytes!);
  return path;
}

Future<String> exportClientsXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final rows = await db.query('customers', orderBy: 'name COLLATE NOCASE');

  final ex = Excel.createExcel();
  final sh = _getOrCreate(ex, 'clients');
  sh.appendRow([
    const TextCellValue('phone'),
    const TextCellValue('name'),
    const TextCellValue('address'),
  ]);
  for (final r in rows) {
    sh.appendRow([_cv(r['phone']), _cv(r['name']), _cv(r['address'])]);
  }

  final bytes = ex.encode();
  final path = await _writeBytes('clientes.xlsx', bytes!);
  return path;
}

Future<String> exportSuppliersXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final rows = await db.query('suppliers', orderBy: 'name COLLATE NOCASE');

  final ex = Excel.createExcel();
  final sh = _getOrCreate(ex, 'suppliers');
  sh.appendRow([
    const TextCellValue('phone'),
    const TextCellValue('name'),
    const TextCellValue('address'),
  ]);
  for (final r in rows) {
    sh.appendRow([_cv(r['phone']), _cv(r['name']), _cv(r['address'])]);
  }

  final bytes = ex.encode();
  final path = await _writeBytes('proveedores.xlsx', bytes!);
  return path;
}

Future<String> exportSalesXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final sales = await db.query('sales', orderBy: 'date DESC, id DESC');
  final items = await db.query('sale_items', orderBy: 'sale_id');

  final ex = Excel.createExcel();
  final s = _getOrCreate(ex, 'sales');
  s.appendRow([
    const TextCellValue('id'),
    const TextCellValue('customer_phone'),
    const TextCellValue('payment_method'),
    const TextCellValue('place'),
    const TextCellValue('shipping_cost'),
    const TextCellValue('discount'),
    const TextCellValue('date'),
  ]);
  for (final r in sales) {
    s.appendRow([
      _cv(r['id']),
      _cv(r['customer_phone']),
      _cv(r['payment_method']),
      _cv(r['place']),
      _cv((r['shipping_cost'] as num?)?.toDouble() ?? 0),
      _cv((r['discount'] as num?)?.toDouble() ?? 0),
      _cv(r['date']),
    ]);
  }

  final si = _getOrCreate(ex, 'sale_items');
  si.appendRow([
    const TextCellValue('sale_id'),
    const TextCellValue('product_sku'),
    const TextCellValue('quantity'),
    const TextCellValue('unit_price'),
  ]);
  for (final r in items) {
    si.appendRow([
      _cv(r['sale_id']),
      _cv(r['product_sku']),
      _cv((r['quantity'] as num?)?.toInt() ?? 0),
      _cv((r['unit_price'] as num?)?.toDouble() ?? 0),
    ]);
  }

  final bytes = ex.encode();
  final path = await _writeBytes('ventas.xlsx', bytes!);
  return path;
}

Future<String> exportPurchasesXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final purchases = await db.query('purchases', orderBy: 'date DESC, id DESC');
  final items = await db.query('purchase_items', orderBy: 'purchase_id');

  final ex = Excel.createExcel();
  final s = _getOrCreate(ex, 'purchases');
  s.appendRow([
    const TextCellValue('id'),
    const TextCellValue('folio'),
    const TextCellValue('supplier_phone'),
    const TextCellValue('date'),
  ]);
  for (final r in purchases) {
    s.appendRow([
      _cv(r['id']),
      _cv(r['folio']),
      _cv(r['supplier_phone']),
      _cv(r['date']),
    ]);
  }

  final si = _getOrCreate(ex, 'purchase_items');
  si.appendRow([
    const TextCellValue('purchase_id'),
    const TextCellValue('product_sku'),
    const TextCellValue('quantity'),
    const TextCellValue('unit_cost'),
  ]);
  for (final r in items) {
    si.appendRow([
      _cv(r['purchase_id']),
      _cv(r['product_sku']),
      _cv((r['quantity'] as num?)?.toInt() ?? 0),
      _cv((r['unit_cost'] as num?)?.toDouble() ?? 0),
    ]);
  }

  final bytes = ex.encode();
  final path = await _writeBytes('compras.xlsx', bytes!);
  return path;
}

/// ====== IMPORT ======
/// Reciben el XLSX en bytes. Valida SKU único (no vacío) en productos.

Future<void> importProductsXlsx(Uint8List bytes) async {
  final ex = Excel.decodeBytes(bytes);
  final sh = ex.sheets['products'] ?? ex.tables.values.firstOrNull;
  if (sh == null) throw 'Hoja "products" no encontrada';

  // Encabezados esperados:
  // sku | name | category | default_sale_price | last_purchase_price | stock
  final db = await appdb.DatabaseHelper.instance.db;
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

      if (sku.isEmpty) continue; // obligatorio
      // upsert por SKU
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

  final db = await appdb.DatabaseHelper.instance.db;
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

  final db = await appdb.DatabaseHelper.instance.db;
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

  final db = await appdb.DatabaseHelper.instance.db;
  await db.transaction((txn) async {
    // ventas
    for (int i = 1; i < sh.maxRows; i++) {
      final row = sh.row(i);
      if (row.isEmpty) continue;
      final id = _asInt(row.elementAtOrNull(0)?.value);
      final phone = _asString(row.elementAtOrNull(1)?.value);
      final payment = _asString(row.elementAtOrNull(2)?.value);
      final place = _asString(row.elementAtOrNull(3)?.value);
      final shipping = _asDouble(row.elementAtOrNull(4)?.value);
      final discount = _asDouble(row.elementAtOrNull(5)?.value);
      final date = _asString(row.elementAtOrNull(6)?.value);

      // insert con id si se provee (si tu tabla usa AUTOINCREMENT, puedes omitir id)
      await txn.insert('sales', {
        if (id > 0) 'id': id,
        'customer_phone': phone,
        'payment_method': payment,
        'place': place,
        'shipping_cost': shipping,
        'discount': discount,
        'date': date,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    // items
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

  final db = await appdb.DatabaseHelper.instance.db;
  await db.transaction((txn) async {
    for (int i = 1; i < sh.maxRows; i++) {
      final row = sh.row(i);
      if (row.isEmpty) continue;
      final id = _asInt(row.elementAtOrNull(0)?.value);
      final folio = _asString(row.elementAtOrNull(1)?.value);
      final supplier = _asString(row.elementAtOrNull(2)?.value);
      final date = _asString(row.elementAtOrNull(3)?.value);

      await txn.insert('purchases', {
        if (id > 0) 'id': id,
        'folio': folio,
        'supplier_phone': supplier,
        'date': date,
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

      // resolver product_id por SKU
      final prod = await txn.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
      if (prod.isEmpty) continue;
      final productId = prod.first['id'] as int;

      await txn.insert('purchase_items', {
        'purchase_id': pid,
        'product_id': productId,
        'quantity': qty,
        'unit_cost': cost,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // impacta stock y último costo
      await txn.rawUpdate(
        'UPDATE products SET stock = COALESCE(stock,0)+?, last_purchase_price = ? WHERE id = ?',
        [qty, cost, productId],
      );
    }
  });
}