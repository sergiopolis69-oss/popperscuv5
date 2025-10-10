import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

/// ---------- Helpers para Excel 4.x ----------
CellValue? cv(dynamic v) {
  if (v == null) return null;
  if (v is num) return DoubleCellValue(v.toDouble());
  if (v is bool) return BoolCellValue(v);
  return TextCellValue(v.toString());
}

Future<void> _ensureStoragePerms() async {
  final statuses = await [Permission.storage].request();
  // En Android 10+ normalmente no es necesario; si el OEM lo exige, esto lo cubre.
}

Future<void> _saveExcelToDownloads(Excel excel, String filename) async {
  final bytes = excel.save();
  if (bytes == null) throw Exception('No fue posible generar el archivo XLSX');
  await FileSaver.instance.saveFile(
    name: filename,
    bytes: Uint8List.fromList(bytes),
    ext: 'xlsx',
    mimeType: MimeType.other,
  );
}

/// =======================
/// EXPORTACIONES
/// =======================
Future<void> exportClientsXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('customers', orderBy: 'name COLLATE NOCASE ASC');
  final excel = Excel.createExcel();
  final sh = excel['clientes'];
  sh.appendRow([
    TextCellValue('phone_id'),
    TextCellValue('name'),
    TextCellValue('address'),
  ]);
  for (final r in rows) {
    sh.appendRow([cv(r['phone']), cv(r['name']), cv(r['address'])]);
  }
  await _saveExcelToDownloads(excel, 'clientes');
}

Future<void> exportSuppliersXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('suppliers', orderBy: 'name COLLATE NOCASE ASC');
  final excel = Excel.createExcel();
  final sh = excel['proveedores'];
  sh.appendRow([
    TextCellValue('id'),
    TextCellValue('name'),
    TextCellValue('phone'),
    TextCellValue('address'),
  ]);
  for (final r in rows) {
    sh.appendRow([cv(r['id']), cv(r['name']), cv(r['phone']), cv(r['address'])]);
  }
  await _saveExcelToDownloads(excel, 'proveedores');
}

Future<void> exportProductsXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('products', orderBy: 'name COLLATE NOCASE ASC');
  final excel = Excel.createExcel();
  final sh = excel['productos'];
  sh.appendRow([
    TextCellValue('id'),
    TextCellValue('sku'),
    TextCellValue('name'),
    TextCellValue('category'),
    TextCellValue('default_sale_price'),
    TextCellValue('last_purchase_price'),
    TextCellValue('last_purchase_date'),
    TextCellValue('stock'),
  ]);
  for (final r in rows) {
    sh.appendRow([
      cv(r['id']),
      cv(r['sku']),
      cv(r['name']),
      cv(r['category']),
      cv(r['default_sale_price']),
      cv(r['last_purchase_price']),
      cv(r['last_purchase_date']),
      cv(r['stock']),
    ]);
  }
  await _saveExcelToDownloads(excel, 'productos');
}

Future<void> exportSalesXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.createExcel();

  final shSales = excel['ventas'];
  shSales.appendRow([
    TextCellValue('sale_id'),
    TextCellValue('date'),
    TextCellValue('customer_phone'),
    TextCellValue('payment_method'),
    TextCellValue('place'),
    TextCellValue('shipping_cost'),
    TextCellValue('discount'),
  ]);
  final sales = await db.rawQuery('''
    SELECT id, date, customer_phone, payment_method, place,
           CAST(IFNULL(shipping_cost,0) AS REAL) AS shipping_cost,
           CAST(IFNULL(discount,0) AS REAL) AS discount
    FROM sales ORDER BY date DESC
  ''');
  for (final s in sales) {
    shSales.appendRow([
      cv(s['id']),
      cv(s['date']),
      cv(s['customer_phone']),
      cv(s['payment_method']),
      cv(s['place']),
      cv(s['shipping_cost']),
      cv(s['discount']),
    ]);
  }

  final shItems = excel['venta_items'];
  shItems.appendRow([
    TextCellValue('sale_id'),
    TextCellValue('product_sku'),
    TextCellValue('product_name'),
    TextCellValue('quantity'),
    TextCellValue('unit_price'),
  ]);
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
      cv(it['sale_id']),
      cv(it['product_sku']),
      cv(it['product_name']),
      cv(it['quantity']),
      cv(it['unit_price']),
    ]);
  }

  await _saveExcelToDownloads(excel, 'ventas');
}

Future<void> exportPurchasesXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final excel = Excel.createExcel();

  final shP = excel['compras'];
  shP.appendRow([
    TextCellValue('purchase_id'),
    TextCellValue('folio'),
    TextCellValue('date'),
    TextCellValue('supplier_id'),
  ]);
  final purchases = await db.rawQuery('''
    SELECT id, folio, date, supplier_id
    FROM purchases ORDER BY date DESC
  ''');
  for (final pRow in purchases) {
    shP.appendRow([
      cv(pRow['id']),
      cv(pRow['folio']),
      cv(pRow['date']),
      cv(pRow['supplier_id']),
    ]);
  }

  final shI = excel['compra_items'];
  shI.appendRow([
    TextCellValue('purchase_id'),
    TextCellValue('product_sku'),
    TextCellValue('product_name'),
    TextCellValue('quantity'),
    TextCellValue('unit_cost'),
  ]);
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
      cv(it['purchase_id']),
      cv(it['product_sku']),
      cv(it['product_name']),
      cv(it['quantity']),
      cv(it['unit_cost']),
    ]);
  }

  await _saveExcelToDownloads(excel, 'compras');
}

/// =======================
/// IMPORTACIONES
/// =======================
Excel _openExcel(Uint8List bytes) => Excel.decodeBytes(bytes);

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

Future<void> importSalesXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final ex = _openExcel(bytes);
  final shS = ex['ventas'];
  final shI = ex['venta_items'];
  if (shS.maxRows <= 1 || shI.maxRows <= 1) return;

  final prods = await db.query('products', columns: ['id','sku']);
  final Map<String,int> skuToId = {
    for (final p in prods)
      if ((p['sku'] ?? '').toString().isNotEmpty)
        (p['sku'] as String): (p['id'] as int)
  };

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

  final batch = db.batch();
  for (int r = 1; r < shI.maxRows; r++) {
    final rowSaleIdx = shI.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value;
    final sku = shI.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value?.toString();
    final qty = int.tryParse(shI.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value?.toString() ?? '') ?? 0;
    final price = double.tryParse(shI.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value?.toString() ?? '') ?? 0;

    final saleId = rowToSaleId[rowSaleIdx] ?? 0;
    final pid = (sku != null) ? skuToId[sku] : null;
    if (saleId == 0 || pid == null || qty <= 0 || price <= 0) continue;

    batch.insert('sale_items', {
      'sale_id': saleId, 'product_id': pid, 'quantity': qty, 'unit_price': price,
    });
    batch.rawUpdate('UPDATE products SET stock = stock - ? WHERE id = ?', [qty, pid]);
  }
  await batch.commit(noResult: true);
}

Future<void> importPurchasesXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final ex = _openExcel(bytes);
  final shP = ex['compras'];
  final shI = ex['compra_items'];
  if (shP.maxRows <= 1 || shI.maxRows <= 1) return;

  final prods = await db.query('products', columns: ['id','sku']);
  final Map<String,int> skuToId = {
    for (final p in prods)
      if ((p['sku'] ?? '').toString().isNotEmpty)
        (p['sku'] as String): (p['id'] as int)
  };

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

  final batch = db.batch();
  for (int r = 1; r < shI.maxRows; r++) {
    final rowIdx = shI.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value;
    final sku = shI.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value?.toString();
    final qty = int.tryParse(shI.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value?.toString() ?? '') ?? 0;
    final cost = double.tryParse(shI.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value?.toString() ?? '') ?? 0;

    final purchaseId = rowToPurchaseId[rowIdx] ?? 0;
    final pid = (sku != null) ? skuToId[sku] : null;
    if (purchaseId == 0 || pid == null || qty <= 0 || cost <= 0) continue;

    batch.insert('purchase_items', {
      'purchase_id': purchaseId, 'product_id': pid, 'quantity': qty, 'unit_cost': cost,
    });
    batch.rawUpdate(
      'UPDATE products SET stock = stock + ?, last_purchase_price = ?, last_purchase_date = ? WHERE id = ?',
      [qty, cost, DateTime.now().toIso8601String(), pid],
    );
  }
  await batch.commit(noResult: true);
}