import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart' as ex;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import 'package:popperscuv5/data/database.dart' as appdb;

/// Reporte genérico para importaciones/restauraciones
class ImportReport {
  int inserted;
  int updated;
  int skipped;
  int errors;
  final List<String> messages;
  ImportReport({
    this.inserted = 0,
    this.updated = 0,
    this.skipped = 0,
    this.errors = 0,
    List<String>? messages,
  }) : messages = messages ?? [];
}

/// ===== Helpers comunes =====

Future<String> _docsPath() async {
  final dir = await getApplicationDocumentsDirectory();
  return dir.path;
}

String _ts([DateTime? d]) {
  d ??= DateTime.now();
  return DateFormat('yyyyMMdd_HHmmss').format(d);
}

Future<Database> _db() async => appdb.DatabaseHelper.instance.db;

/// Obtiene (o crea) hoja por nombre. En excel ^4, el operador [] crea si no existe.
ex.Sheet _sheet(ex.Excel book, String name) => book[name];

/// Convierte Data? a String
String _asString(ex.Data? d) {
  if (d == null) return '';
  if (d is ex.TextCellValue) return d.value.text ?? '';
  if (d is ex.IntCellValue) return d.value.toString();
  if (d is ex.DoubleCellValue) return d.value.toString();
  if (d is ex.DateCellValue) return d.value.toIso8601String();
  return d.toString();
}

/// Convierte Data? a double
double _asDouble(ex.Data? d) {
  if (d == null) return 0.0;
  if (d is ex.DoubleCellValue) return d.value;
  if (d is ex.IntCellValue) return d.value.toDouble();
  if (d is ex.TextCellValue) {
    final s = (d.value.text ?? '').replaceAll(',', '.');
    return double.tryParse(s) ?? 0.0;
  }
  return 0.0;
}

/// Convierte Data? a int
int _asInt(ex.Data? d) {
  if (d == null) return 0;
  if (d is ex.IntCellValue) return d.value;
  if (d is ex.DoubleCellValue) return d.value.round();
  if (d is ex.TextCellValue) return int.tryParse(d.value.text ?? '') ?? 0;
  return 0;
}

/// Guarda bytes en Documentos de la app
Future<String> _saveBytes(String fileName, List<int> bytes) async {
  final base = await _docsPath();
  final path = p.join(base, fileName);
  final f = File(path);
  await f.writeAsBytes(bytes, flush: true);
  return path;
}

/// ===== EXPORTAR XLSX =====

Future<String> exportProductsXlsxToFile() async {
  final db = await _db();
  final rows = await db.rawQuery('''
    SELECT sku,name,category,default_sale_price,last_purchase_price,stock
    FROM products ORDER BY name
  ''');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'products');

  sh.appendRow(<ex.CellValue?>[
    ex.TextCellValue('sku'),
    ex.TextCellValue('name'),
    ex.TextCellValue('category'),
    ex.TextCellValue('default_sale_price'),
    ex.TextCellValue('last_purchase_price'),
    ex.TextCellValue('stock'),
  ]);

  for (final r in rows) {
    sh.appendRow(<ex.CellValue?>[
      ex.TextCellValue((r['sku'] ?? '').toString()),
      ex.TextCellValue((r['name'] ?? '').toString()),
      ex.TextCellValue((r['category'] ?? '').toString()),
      ex.DoubleCellValue((r['default_sale_price'] as num?)?.toDouble() ?? 0.0),
      ex.DoubleCellValue((r['last_purchase_price'] as num?)?.toDouble() ?? 0.0),
      ex.IntCellValue((r['stock'] as num?)?.toInt() ?? 0),
    ]);
  }

  final bytes = book.save();
  if (bytes == null) throw 'No se pudo generar XLSX';
  return _saveBytes('productos_${_ts()}.xlsx', bytes);
}

Future<String> exportClientsXlsxToFile() async {
  final db = await _db();
  final rows = await db.rawQuery('SELECT phone,name,address FROM customers ORDER BY name');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'customers');

  sh.appendRow(<ex.CellValue?>[
    ex.TextCellValue('phone'),
    ex.TextCellValue('name'),
    ex.TextCellValue('address'),
  ]);

  for (final r in rows) {
    sh.appendRow(<ex.CellValue?>[
      ex.TextCellValue((r['phone'] ?? '').toString()),
      ex.TextCellValue((r['name'] ?? '').toString()),
      ex.TextCellValue((r['address'] ?? '').toString()),
    ]);
  }

  final bytes = book.save();
  if (bytes == null) throw 'No se pudo generar XLSX';
  return _saveBytes('clientes_${_ts()}.xlsx', bytes);
}

Future<String> exportSuppliersXlsxToFile() async {
  final db = await _db();
  final rows = await db.rawQuery('SELECT phone,name,address FROM suppliers ORDER BY name');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'suppliers');

  sh.appendRow(<ex.CellValue?>[
    ex.TextCellValue('phone'),
    ex.TextCellValue('name'),
    ex.TextCellValue('address'),
  ]);

  for (final r in rows) {
    sh.appendRow(<ex.CellValue?>[
      ex.TextCellValue((r['phone'] ?? '').toString()),
      ex.TextCellValue((r['name'] ?? '').toString()),
      ex.TextCellValue((r['address'] ?? '').toString()),
    ]);
  }

  final bytes = book.save();
  if (bytes == null) throw 'No se pudo generar XLSX';
  return _saveBytes('proveedores_${_ts()}.xlsx', bytes);
}

Future<String> exportSalesXlsxToFile() async {
  final db = await _db();
  final sales = await db.rawQuery('SELECT id,customer_phone,payment_method,place,shipping_cost,discount,date FROM sales ORDER BY id');
  final items = await db.rawQuery('''
    SELECT si.sale_id, p.sku AS product_sku, si.quantity, si.unit_price
    FROM sale_items si
    JOIN products p ON p.id = si.product_id
    ORDER BY si.sale_id, p.sku
  ''');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'sales');
  final shi = _sheet(book, 'sale_items');

  sh.appendRow(<ex.CellValue?>[
    ex.TextCellValue('id'),
    ex.TextCellValue('customer_phone'),
    ex.TextCellValue('payment_method'),
    ex.TextCellValue('place'),
    ex.TextCellValue('shipping_cost'),
    ex.TextCellValue('discount'),
    ex.TextCellValue('date'),
  ]);
  for (final r in sales) {
    sh.appendRow(<ex.CellValue?>[
      ex.IntCellValue((r['id'] as num?)?.toInt() ?? 0),
      ex.TextCellValue((r['customer_phone'] ?? '').toString()),
      ex.TextCellValue((r['payment_method'] ?? '').toString()),
      ex.TextCellValue((r['place'] ?? '').toString()),
      ex.DoubleCellValue((r['shipping_cost'] as num?)?.toDouble() ?? 0.0),
      ex.DoubleCellValue((r['discount'] as num?)?.toDouble() ?? 0.0),
      ex.TextCellValue((r['date'] ?? '').toString()),
    ]);
  }

  shi.appendRow(<ex.CellValue?>[
    ex.TextCellValue('sale_id'),
    ex.TextCellValue('product_sku'),
    ex.TextCellValue('quantity'),
    ex.TextCellValue('unit_price'),
  ]);
  for (final r in items) {
    shi.appendRow(<ex.CellValue?>[
      ex.IntCellValue((r['sale_id'] as num?)?.toInt() ?? 0),
      ex.TextCellValue((r['product_sku'] ?? '').toString()),
      ex.IntCellValue((r['quantity'] as num?)?.toInt() ?? 0),
      ex.DoubleCellValue((r['unit_price'] as num?)?.toDouble() ?? 0.0),
    ]);
  }

  final bytes = book.save();
  if (bytes == null) throw 'No se pudo generar XLSX';
  return _saveBytes('ventas_${_ts()}.xlsx', bytes);
}

Future<String> exportPurchasesXlsxToFile() async {
  final db = await _db();
  final purchases = await db.rawQuery('''
    SELECT id, folio,
           (SELECT phone FROM suppliers s WHERE s.id = purchases.supplier_id) AS supplier_phone,
           date
    FROM purchases ORDER BY id
  ''');
  final items = await db.rawQuery('''
    SELECT pi.purchase_id, p.sku AS product_sku, pi.quantity, pi.unit_cost
    FROM purchase_items pi
    JOIN products p ON p.id = pi.product_id
    ORDER BY pi.purchase_id, p.sku
  ''');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'purchases');
  final shi = _sheet(book, 'purchase_items');

  sh.appendRow(<ex.CellValue?>[
    ex.TextCellValue('id'),
    ex.TextCellValue('folio'),
    ex.TextCellValue('supplier_phone'),
    ex.TextCellValue('date'),
  ]);
  for (final r in purchases) {
    sh.appendRow(<ex.CellValue?>[
      ex.IntCellValue((r['id'] as num?)?.toInt() ?? 0),
      ex.TextCellValue((r['folio'] ?? '').toString()),
      ex.TextCellValue((r['supplier_phone'] ?? '').toString()),
      ex.TextCellValue((r['date'] ?? '').toString()),
    ]);
  }

  shi.appendRow(<ex.CellValue?>[
    ex.TextCellValue('purchase_id'),
    ex.TextCellValue('product_sku'),
    ex.TextCellValue('quantity'),
    ex.TextCellValue('unit_cost'),
  ]);
  for (final r in items) {
    shi.appendRow(<ex.CellValue?>[
      ex.IntCellValue((r['purchase_id'] as num?)?.toInt() ?? 0),
      ex.TextCellValue((r['product_sku'] ?? '').toString()),
      ex.IntCellValue((r['quantity'] as num?)?.toInt() ?? 0),
      ex.DoubleCellValue((r['unit_cost'] as num?)?.toDouble() ?? 0.0),
    ]);
  }

  final bytes = book.save();
  if (bytes == null) throw 'No se pudo generar XLSX';
  return _saveBytes('compras_${_ts()}.xlsx', bytes);
}

/// ===== IMPORTAR XLSX =====

Future<ImportReport> importProductsFromBytes(Uint8List bytes) async {
  final db = await _db();
  final r = ImportReport();
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book.sheets.values.firstWhere(
    (s) => s.sheetName.toLowerCase().contains('product'),
    orElse: () => book['products'],
  );

  // Espera encabezados: sku, name, category, default_sale_price, last_purchase_price, stock
  final rows = sh.rows.skip(1); // salta header
  final batch = db.batch();
  for (final row in rows) {
    final sku = _asString(row.elementAtOrNull(0));
    final name = _asString(row.elementAtOrNull(1));
    final category = _asString(row.elementAtOrNull(2));
    final dsp = _asDouble(row.elementAtOrNull(3));
    final lpp = _asDouble(row.elementAtOrNull(4));
    final stock = _asInt(row.elementAtOrNull(5));

    if (sku.isEmpty) { r.skipped++; r.messages.add('SKU vacío, fila omitida'); continue; }
    if (name.isEmpty) { r.skipped++; r.messages.add('Nombre vacío (sku $sku)'); continue; }

    // upsert por sku
    batch.rawInsert('''
      INSERT INTO products (sku,name,category,default_sale_price,last_purchase_price,stock)
      VALUES(?,?,?,?,?,?)
      ON CONFLICT(sku) DO UPDATE SET
        name=excluded.name,
        category=excluded.category,
        default_sale_price=excluded.default_sale_price,
        last_purchase_price=excluded.last_purchase_price,
        stock=excluded.stock
    ''', [sku, name, category, dsp, lpp, stock]);
  }

  try {
    await batch.commit(noResult: true);
    // Para contadores aproximados: recalc desde archivo
    r.inserted = 0; r.updated = 0; r.skipped = r.skipped; r.errors = 0;
  } catch (e) {
    r.errors++; r.messages.add('Error aplicando cambios: $e');
  }
  return r;
}

Future<ImportReport> importClientsFromBytes(Uint8List bytes) async {
  final db = await _db();
  final r = ImportReport();
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book.sheets.values.firstWhere(
    (s) => s.sheetName.toLowerCase().contains('customer') || s.sheetName.toLowerCase().contains('client'),
    orElse: () => book['customers'],
  );

  final batch = db.batch();
  for (final row in sh.rows.skip(1)) {
    final phone = _asString(row.elementAtOrNull(0));
    final name = _asString(row.elementAtOrNull(1));
    final address = _asString(row.elementAtOrNull(2));
    if (phone.isEmpty) { r.skipped++; r.messages.add('Cliente sin teléfono'); continue; }

    batch.rawInsert('''
      INSERT INTO customers (phone, name, address)
      VALUES(?,?,?)
      ON CONFLICT(phone) DO UPDATE SET name=excluded.name, address=excluded.address
    ''', [phone, name, address]);
  }

  try { await batch.commit(noResult: true); } catch (e) { r.errors++; r.messages.add('Error: $e'); }
  return r;
}

Future<ImportReport> importSuppliersFromBytes(Uint8List bytes) async {
  final db = await _db();
  final r = ImportReport();
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book.sheets.values.firstWhere(
    (s) => s.sheetName.toLowerCase().contains('supplier') || s.sheetName.toLowerCase().contains('proveed'),
    orElse: () => book['suppliers'],
  );

  final batch = db.batch();
  for (final row in sh.rows.skip(1)) {
    final phone = _asString(row.elementAtOrNull(0));
    final name = _asString(row.elementAtOrNull(1));
    final address = _asString(row.elementAtOrNull(2));
    if (phone.isEmpty) { r.skipped++; r.messages.add('Proveedor sin teléfono'); continue; }

    batch.rawInsert('''
      INSERT INTO suppliers (phone, name, address)
      VALUES(?,?,?)
      ON CONFLICT(phone) DO UPDATE SET name=excluded.name, address=excluded.address
    ''', [phone, name, address]);
  }

  try { await batch.commit(noResult: true); } catch (e) { r.errors++; r.messages.add('Error: $e'); }
  return r;
}

Future<ImportReport> importSalesFromBytes(Uint8List bytes) async {
  final db = await _db();
  final r = ImportReport();
  final book = ex.Excel.decodeBytes(bytes);

  final shSales = book.sheets.values.firstWhere(
    (s) => s.sheetName.toLowerCase().contains('sale'),
    orElse: () => book['sales'],
  );
  final shItems = book.sheets.values.firstWhere(
    (s) => s.sheetName.toLowerCase().contains('item'),
    orElse: () => book['sale_items'],
  );

  // Limpiar ventas antes de importar (opcional: aquí las reemplazamos)
  await db.transaction((txn) async {
    await txn.delete('sale_items');
    await txn.delete('sales');

    for (final row in shSales.rows.skip(1)) {
      final id = _asInt(row.elementAtOrNull(0));
      final phone = _asString(row.elementAtOrNull(1));
      final pay = _asString(row.elementAtOrNull(2));
      final place = _asString(row.elementAtOrNull(3));
      final ship = _asDouble(row.elementAtOrNull(4));
      final disc = _asDouble(row.elementAtOrNull(5));
      final date = _asString(row.elementAtOrNull(6));

      await txn.insert('sales', {
        'id': id,
        'customer_phone': phone,
        'payment_method': pay,
        'place': place,
        'shipping_cost': ship,
        'discount': disc,
        'date': date,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    for (final row in shItems.rows.skip(1)) {
      final saleId = _asInt(row.elementAtOrNull(0));
      final sku = _asString(row.elementAtOrNull(1));
      final qty = _asInt(row.elementAtOrNull(2));
      final unit = _asDouble(row.elementAtOrNull(3));

      final pid = await _getProductIdBySku(txn, sku);
      if (pid == null) { r.skipped++; r.messages.add('SKU no encontrado en productos: $sku'); continue; }

      await txn.insert('sale_items', {
        'sale_id': saleId,
        'product_id': pid,
        'quantity': qty,
        'unit_price': unit,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });

  return r;
}

Future<ImportReport> importPurchasesFromBytes(Uint8List bytes) async {
  final db = await _db();
  final r = ImportReport();
  final book = ex.Excel.decodeBytes(bytes);

  final sh = book.sheets.values.firstWhere(
    (s) => s.sheetName.toLowerCase().contains('purchas') || s.sheetName.toLowerCase().contains('compra'),
    orElse: () => book['purchases'],
  );
  final shi = book.sheets.values.firstWhere(
    (s) => s.sheetName.toLowerCase().contains('item'),
    orElse: () => book['purchase_items'],
  );

  await db.transaction((txn) async {
    await txn.delete('purchase_items');
    await txn.delete('purchases');

    for (final row in sh.rows.skip(1)) {
      final id = _asInt(row.elementAtOrNull(0));
      final folio = _asString(row.elementAtOrNull(1));
      final supplierPhone = _asString(row.elementAtOrNull(2));
      final date = _asString(row.elementAtOrNull(3));

      // asegura proveedor por phone
      final supId = await _ensureSupplierByPhone(txn, supplierPhone);

      await txn.insert('purchases', {
        'id': id,
        'folio': folio,
        'supplier_id': supId,
        'date': date,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    for (final row in shi.rows.skip(1)) {
      final pid = _asInt(row.elementAtOrNull(0));
      final sku = _asString(row.elementAtOrNull(1));
      final qty = _asInt(row.elementAtOrNull(2));
      final cost = _asDouble(row.elementAtOrNull(3));

      final prodId = await _getProductIdBySku(txn, sku);
      if (prodId == null) { r.skipped++; r.messages.add('SKU no encontrado: $sku'); continue; }

      await txn.insert('purchase_items', {
        'purchase_id': pid,
        'product_id': prodId,
        'quantity': qty,
        'unit_cost': cost,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Actualiza precio/stock último de compra
      await txn.update('products', {
        'last_purchase_price': cost,
        'last_purchase_date': DateTime.now().toIso8601String(),
        'stock': (await _getCurrentStock(txn, prodId)) + qty,
      }, where: 'id=?', whereArgs: [prodId]);
    }
  });

  return r;
}

/// ===== Respaldar / Restaurar Base de Datos =====

Future<String> exportDatabaseCopyToFile() async {
  // Ruta actual del .db
  final base = await getDatabasesPath();
  final dbPath = p.join(base, 'pdv.db');

  final docs = await _docsPath();
  final ts = _ts();
  final dstMain = p.join(docs, 'backup_pdv_$ts.db');

  // Trata de copiar .db + -wal + -shm si existen (modo WAL)
  final mainFile = File(dbPath);
  if (!await mainFile.exists()) throw 'No se encontró el archivo de BD ($dbPath)';

  await mainFile.copy(dstMain);

  final wal = File('$dbPath-wal');
  final shm = File('$dbPath-shm');
  if (await wal.exists()) { await wal.copy('$dstMain-wal'); }
  if (await shm.exists()) { await shm.copy('$dstMain-shm'); }

  return dstMain;
}

Future<ImportReport> restoreDatabaseFromFile(String backupDbPath) async {
  final r = ImportReport();
  if (!await File(backupDbPath).exists()) { r.errors++; r.messages.add('Archivo no existe'); return r; }

  final current = await _db();
  // abre respaldo en solo lectura
  final src = await openDatabase(backupDbPath, readOnly: true);

  await current.transaction((txn) async {
    // Limpia tablas (respeta orden por dependencias)
    await txn.delete('sale_items');
    await txn.delete('purchase_items');
    await txn.delete('sales');
    await txn.delete('purchases');
    await txn.delete('products');
    await txn.delete('customers');
    await txn.delete('suppliers');

    // Copia suppliers (preserva id)
    final supRows = await src.rawQuery('SELECT id,phone,name,address FROM suppliers');
    for (final m in supRows) {
      await txn.insert('suppliers', m, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // Copia customers
    final custRows = await src.rawQuery('SELECT phone,name,address FROM customers');
    for (final m in custRows) {
      await txn.insert('customers', m, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // Copia products (preserva id y sku único)
    final prodRows = await src.rawQuery('''
      SELECT id,sku,name,category,default_sale_price,last_purchase_price,last_purchase_date,stock
      FROM products
    ''');
    for (final m in prodRows) {
      final sku = (m['sku'] ?? '').toString();
      if (sku.isEmpty) { r.skipped++; r.messages.add('Producto con SKU vacío omitido'); continue; }
      await txn.insert('products', m, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // Copia purchases (preserva id)
    final purRows = await src.rawQuery('SELECT id,folio,supplier_id,date FROM purchases');
    for (final m in purRows) {
      await txn.insert('purchases', m, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // Copia purchase_items (requiere producto por id)
    final pitRows = await src.rawQuery('SELECT purchase_id,product_id,quantity,unit_cost FROM purchase_items');
    for (final m in pitRows) {
      await txn.insert('purchase_items', m, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // Copia sales (preserva id)
    final saRows = await src.rawQuery('SELECT id,customer_phone,payment_method,place,shipping_cost,discount,date FROM sales');
    for (final m in saRows) {
      await txn.insert('sales', m, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // Copia sale_items
    final sitRows = await src.rawQuery('SELECT sale_id,product_id,quantity,unit_price FROM sale_items');
    for (final m in sitRows) {
      await txn.insert('sale_items', m, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });

  await src.close();
  return r;
}

/// ===== helpers DB internos =====

Future<int?> _getProductIdBySku(Transaction txn, String sku) async {
  if (sku.isEmpty) return null;
  final res = await txn.rawQuery('SELECT id FROM products WHERE sku=?', [sku]);
  if (res.isEmpty) return null;
  return (res.first['id'] as num).toInt();
}

Future<int> _getCurrentStock(Transaction txn, int productId) async {
  final res = await txn.rawQuery('SELECT stock FROM products WHERE id=?', [productId]);
  if (res.isEmpty) return 0;
  return (res.first['stock'] as num?)?.toInt() ?? 0;
}