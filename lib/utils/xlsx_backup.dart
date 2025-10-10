import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:downloads_path_provider_28/downloads_path_provider_28.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

Future<Directory> _downloadsDir() async {
  final dir = await DownloadsPathProvider.downloadsDirectory;
  if (dir == null) throw Exception('No se pudo resolver la carpeta Descargas');
  return Directory(dir.path);
}

Future<void> _ensureStoragePerms() async {
  // Android 10+ normalmente no requiere WRITE externo si usamos /Download y SAF,
  // pero pedimos READ/WRITE por compatibilidad con más dispositivos.
  final statuses = await [Permission.storage].request();
  if (!statuses[Permission.storage]!.isGranted) {
    throw Exception('Permiso de almacenamiento denegado');
  }
}

Future<File> _writeExcelToDownloads(Excel excel, String filename) async {
  await _ensureStoragePerms();
  final dir = await _downloadsDir();
  final bytes = excel.save();
  if (bytes == null) throw Exception('No fue posible generar el archivo XLSX');
  final file = File(p.join(dir.path, '$filename.xlsx'));
  await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
  return file;
}

/// =======================
/// EXPORTACIONES
/// =======================

Future<File> exportClientsXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('customers', orderBy: 'name COLLATE NOCASE ASC');
  final excel = Excel.createExcel();
  final sh = excel['clientes'];
  sh.appendRow(['phone_id', 'name', 'address']);
  for (final r in rows) {
    sh.appendRow([r['phone'], r['name'], r['address']]);
  }
  return _writeExcelToDownloads(excel, 'clientes');
}

Future<File> exportSuppliersXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('suppliers', orderBy: 'name COLLATE NOCASE ASC');
  final excel = Excel.createExcel();
  final sh = excel['proveedores'];
  sh.appendRow(['id', 'name', 'phone', 'address']);
  for (final r in rows) {
    sh.appendRow([r['id'], r['name'], r['phone'], r['address']]);
  }
  return _writeExcelToDownloads(excel, 'proveedores');
}

Future<File> exportProductsXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('products', orderBy: 'name COLLATE NOCASE ASC');
  final excel = Excel.createExcel();
  final sh = excel['productos'];
  sh.appendRow([
    'id','sku','name','category',
    'default_sale_price','last_purchase_price','last_purchase_date','stock'
  ]);
  for (final r in rows) {
    sh.appendRow([
      r['id'], r['sku'], r['name'], r['category'],
      r['default_sale_price'], r['last_purchase_price'], r['last_purchase_date'], r['stock']
    ]);
  }
  return _writeExcelToDownloads(excel, 'productos');
}

Future<File> exportSalesXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.createExcel();

  // Encabezado ventas
  final shSales = excel['ventas'];
  shSales.appendRow(['sale_id','date','customer_phone','payment_method','place','shipping_cost','discount']);

  final sales = await db.rawQuery('''
    SELECT id, date, customer_phone, payment_method, place, 
           CAST(IFNULL(shipping_cost,0) AS REAL) AS shipping_cost,
           CAST(IFNULL(discount,0) AS REAL) AS discount
    FROM sales ORDER BY date DESC
  ''');
  for (final s in sales) {
    shSales.appendRow([
      s['id'], s['date'], s['customer_phone'], s['payment_method'],
      s['place'], s['shipping_cost'], s['discount']
    ]);
  }

  // Detalle con SKU
  final shItems = excel['venta_items'];
  shItems.appendRow(['sale_id','product_sku','product_name','quantity','unit_price']);
  final items = await db.rawQuery('''
    SELECT si.sale_id, p.sku AS product_sku, p.name AS product_name,
           CAST(si.quantity AS INTEGER) AS quantity,
           CAST(si.unit_price AS REAL) AS unit_price
    FROM sale_items si
    JOIN products p ON p.id = si.product_id
    ORDER BY si.sale_id DESC
  ''');
  for (final it in items) {
    shItems.appendRow([
      it['sale_id'], it['product_sku'], it['product_name'],
      it['quantity'], it['unit_price']
    ]);
  }

  return _writeExcelToDownloads(excel, 'ventas');
}

Future<File> exportPurchasesXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.createExcel();

  // Encabezado compras
  final shP = excel['compras'];
  shP.appendRow(['purchase_id','folio','date','supplier_id']);

  final purchases = await db.rawQuery('''
    SELECT id, folio, date, supplier_id
    FROM purchases ORDER BY date DESC
  ''');
  for (final pRow in purchases) {
    shP.appendRow([pRow['id'], pRow['folio'], pRow['date'], pRow['supplier_id']]);
  }

  // Detalle con SKU
  final shI = excel['compra_items'];
  shI.appendRow(['purchase_id','product_sku','product_name','quantity','unit_cost']);
  final items = await db.rawQuery('''
    SELECT pi.purchase_id, p.sku AS product_sku, p.name AS product_name,
           CAST(pi.quantity AS INTEGER) AS quantity,
           CAST(pi.unit_cost AS REAL) AS unit_cost
    FROM purchase_items pi
    JOIN products p ON p.id = pi.product_id
    ORDER BY pi.purchase_id DESC
  ''');
  for (final it in items) {
    shI.appendRow([
      it['purchase_id'], it['product_sku'], it['product_name'],
      it['quantity'], it['unit_cost']
    ]);
  }

  return _writeExcelToDownloads(excel, 'compras');
}

/// =======================
/// IMPORTACIONES
/// =======================
/// Cada import recibe bytes de un .xlsx (p.ej. del file picker)

Excel _openExcel(Uint8List bytes) {
  return Excel.decodeBytes(bytes);
}

Future<void> importClientsXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final ex = _openExcel(bytes);
  final sh = ex['clientes'];
  if (sh.maxRows <= 1) return;
  final batch = db.batch();
  for (int r = 1; r < sh.maxRows; r++) {
    final phone = sh.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value?.toString().trim() ?? '';
    final name  = sh.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value?.toString().trim();
    final addr  = sh.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value?.toString().trim();
    if (phone.isEmpty) continue;
    batch.insert('customers', {'phone': phone, 'name': name, 'address': addr},
      conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

Future<void> importSuppliersXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final ex = _openExcel(bytes);
  final sh = ex['proveedores'];
  if (sh.maxRows <= 1) return;
  final batch = db.batch();
  for (int r = 1; r < sh.maxRows; r++) {
    final name  = sh.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value?.toString().trim();
    final phone = sh.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value?.toString().trim();
    final addr  = sh.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value?.toString().trim();
    if ((name ?? '').isEmpty && (phone ?? '').isEmpty) continue;
    batch.insert('suppliers', {'name': name, 'phone': phone, 'address': addr},
      conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

Future<void> importProductsXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final ex = _openExcel(bytes);
  final sh = ex['productos'];
  if (sh.maxRows <= 1) return;
  final batch = db.batch();
  for (int r = 1; r < sh.maxRows; r++) {
    final sku   = sh.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value?.toString().trim();
    final name  = sh.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value?.toString().trim();
    final cat   = sh.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value?.toString().trim();
    final sale  = double.tryParse(sh.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value?.toString() ?? '') ?? 0;
    final cost  = double.tryParse(sh.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r)).value?.toString() ?? '') ?? 0;
    final lpd   = sh.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r)).value?.toString().trim();
    final stock = int.tryParse(sh.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r)).value?.toString() ?? '') ?? 0;
    if ((name ?? '').isEmpty) continue;
    batch.insert('products', {
      'sku': sku, 'name': name, 'category': cat,
      'default_sale_price': sale,
      'last_purchase_price': cost,
      'last_purchase_date': lpd,
      'stock': stock,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

/// Importa ventas + items usando SKU para resolver product_id.
/// Hojas requeridas: "ventas" y "venta_items".
Future<void> importSalesXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final ex = _openExcel(bytes);
  final shS = ex['ventas'];
  final shI = ex['venta_items'];
  if (shS.maxRows <= 1 || shI.maxRows <= 1) return;

  // Carga mapa SKU -> id
  final prods = await db.query('products', columns: ['id','sku']);
  final Map<String,int> skuToId = {};
  for (final p in prods) {
    final sku = (p['sku'] ?? '').toString();
    if (sku.isNotEmpty) skuToId[sku] = (p['id'] as int);
  }

  final batch = db.batch();

  // Importa ventas (sin forzar IDs para evitar conflicto; dejamos que SQLite asigne)
  // Guardamos mapping temporal rowIndex->saleId insertado, para poder enlazar items
  final Map<int,int> rowToSaleId = {};
  for (int r = 1; r < shS.maxRows; r++) {
    final date = shS.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value?.toString();
    final phone = shS.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value?.toString();
    final method = shS.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value?.toString();
    final place = shS.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value?.toString();
    final ship = double.tryParse(shS.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r)).value?.toString() ?? '') ?? 0;
    final disc = double.tryParse(shS.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r)).value?.toString() ?? '') ?? 0;

    final saleId = await db.insert('sales', {
      'date': date, 'customer_phone': phone, 'payment_method': method,
      'place': place, 'shipping_cost': ship, 'discount': disc,
    });
    rowToSaleId[r] = saleId;
  }

  // Importa items
  for (int r = 1; r < shI.maxRows; r++) {
    final rowSaleIdx = shI.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value; // índice relativo a hoja "ventas"
    final sku = shI.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value?.toString();
    final qty = int.tryParse(shI.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value?.toString() ?? '') ?? 0;
    final price = double.tryParse(shI.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value?.toString() ?? '') ?? 0;
    final saleId = rowToSaleId[rowSaleIdx] ?? 0;
    if (saleId == 0 || (sku ?? '').isEmpty || qty <= 0 || price <= 0) continue;
    final pid = skuToId[sku!];
    if (pid == null) continue; // SKU desconocido: lo ignoramos (o podrías crearlo)
    batch.insert('sale_items', {
      'sale_id': saleId, 'product_id': pid, 'quantity': qty, 'unit_price': price,
    });
    // stock se descuenta
    batch.rawUpdate('UPDATE products SET stock = stock - ? WHERE id = ?', [qty, pid]);
  }

  await batch.commit(noResult: true);
}

/// Importa compras + items usando SKU.
/// Hojas requeridas: "compras" y "compra_items".
Future<void> importPurchasesXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final ex = _openExcel(bytes);
  final shP = ex['compras'];
  final shI = ex['compra_items'];
  if (shP.maxRows <= 1 || shI.maxRows <= 1) return;

  final prods = await db.query('products', columns: ['id','sku']);
  final Map<String,int> skuToId = {};
  for (final p in prods) {
    final sku = (p['sku'] ?? '').toString();
    if (sku.isNotEmpty) skuToId[sku] = (p['id'] as int);
  }

  final batch = db.batch();
  final Map<int,int> rowToPurchaseId = {};
  for (int r = 1; r < shP.maxRows; r++) {
    final folio = shP.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value?.toString();
    final date  = shP.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value?.toString();
    final supId = int.tryParse(shP.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value?.toString() ?? '') ?? null;

    final purchaseId = await db.insert('purchases', {
      'folio': folio, 'date': date, 'supplier_id': supId,
    });
    rowToPurchaseId[r] = purchaseId;
  }

  for (int r = 1; r < shI.maxRows; r++) {
    final rowIdx = shI.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value;
    final sku = shI.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value?.toString();
    final qty = int.tryParse(shI.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value?.toString() ?? '') ?? 0;
    final cost = double.tryParse(shI.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value?.toString() ?? '') ?? 0;
    final pid = (sku != null && skuToId.containsKey(sku)) ? skuToId[sku]! : 0;
    final purchaseId = rowToPurchaseId[rowIdx] ?? 0;
    if (purchaseId == 0 || pid == 0 || qty <= 0 || cost <= 0) continue;

    batch.insert('purchase_items', {
      'purchase_id': purchaseId, 'product_id': pid, 'quantity': qty, 'unit_cost': cost,
    });
    batch.rawUpdate('UPDATE products SET stock = stock + ?, last_purchase_price = ?, last_purchase_date = ? WHERE id = ?',
      [qty, cost, DateTime.now().toIso8601String(), pid]);
  }

  await batch.commit(noResult: true);
}