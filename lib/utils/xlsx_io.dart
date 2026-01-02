// lib/utils/xlsx_io.dart
//
// Utilidades para exportar / importar XLSX con excel ^4.0.6
// y la BD pdv.db.
//
// NOTA IMPORTANTE:
// - Export de productos / clientes / proveedores: compatible.
// - Export de ventas: ahora genera:
//   * Hoja 'sales' (encabezados básicos de venta)
//   * Hoja 'sale_items' (renglones de items)
//   * Hoja 'sales_detail' (renglones SKU con costo, descuento, envío repartido,
//     y utilidad por línea).
// - Export de compras: hoja 'purchases' + 'purchase_items' (ROBUSTO a schema).
// - Import de ventas / compras: NO implementado (lanza UnimplementedError).

import 'dart:typed_data';

import 'package:excel/excel.dart' as ex;
import 'package:sqflite/sqflite.dart';

import '../data/database.dart' as appdb;

// ====================== BD helper ===========================================

Future<Database> _db() async {
  try {
    return await appdb.getDb();
  } catch (_) {
    return await appdb.DatabaseHelper.instance.db;
  }
}

Future<bool> _tableExists(Database db, String table) async {
  final r = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
    [table],
  );
  return r.isNotEmpty;
}

Future<Set<String>> _columnsOf(Database db, String table) async {
  final rows = await db.rawQuery("PRAGMA table_info($table)");
  return rows
      .map((e) => (e['name'] ?? '').toString())
      .where((s) => s.isNotEmpty)
      .toSet();
}

Future<bool> _hasColumn(Database db, String table, String col) async {
  final cols = await _columnsOf(db, table);
  return cols.contains(col);
}

// ====================== Helpers Excel (lectura) =============================

ex.Data? _cell(List<ex.Data?> row, int index) {
  if (index < 0 || index >= row.length) return null;
  return row[index];
}

String _cellAsString(ex.Data? d) {
  final v = d?.value;
  if (v == null) return '';

  if (v is ex.TextCellValue) return v.value.toString();
  if (v is ex.IntCellValue) return v.value.toString();
  if (v is ex.DoubleCellValue) return v.value.toString();

  if (v is ex.DateCellValue) {
    final dt = v.asDateTimeLocal();
    return dt.toIso8601String();
  }

  return v.toString();
}

double _cellAsDouble(ex.Data? d) {
  final v = d?.value;
  if (v == null) return 0.0;

  if (v is ex.DoubleCellValue) return v.value;
  if (v is ex.IntCellValue) return v.value.toDouble();
  if (v is ex.TextCellValue) {
    final s = v.value.toString().replaceAll(',', '.');
    return double.tryParse(s) ?? 0.0;
  }
  return 0.0;
}

int _cellAsInt(ex.Data? d) {
  final v = d?.value;
  if (v == null) return 0;

  if (v is ex.IntCellValue) return v.value;
  if (v is ex.DoubleCellValue) return v.value.round();
  if (v is ex.TextCellValue) {
    final s = v.value.toString();
    return int.tryParse(s) ?? 0;
  }
  return 0;
}

DateTime? _cellAsDate(ex.Data? d) {
  final v = d?.value;
  if (v == null) return null;

  if (v is ex.DateCellValue) return v.asDateTimeLocal();
  if (v is ex.TextCellValue) {
    final s = v.value.toString();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
  return null;
}

// ====================== Helpers Excel (escritura) ===========================

Uint8List _encode(ex.Excel book) {
  final bytes = book.encode();
  if (bytes == null) return Uint8List(0);
  return Uint8List.fromList(bytes);
}

void _appendHeader(ex.Excel book, String sheet, List<String> cols) {
  book.appendRow(
    sheet,
    cols.map<ex.CellValue?>((c) => ex.TextCellValue(c)).toList(),
  );
}

ex.CellValue _tx(String s) => ex.TextCellValue(s);
ex.CellValue _i(num n) => ex.IntCellValue(n.toInt());
ex.CellValue _d(num n) => ex.DoubleCellValue(n.toDouble());

// ====================== EXPORT: PRODUCTS ====================================

Future<Uint8List> buildProductsXlsxBytes() async {
  final db = await _db();
  final rows = await db.rawQuery('''
    SELECT id, sku, name, category, default_sale_price, last_purchase_price, stock
    FROM products
    ORDER BY name COLLATE NOCASE
  ''');

  final book = ex.Excel.createExcel();
  if (book.sheets.containsKey('Sheet1')) book.delete('Sheet1');

  const sheet = 'products';
  _appendHeader(book, sheet, [
    'id',
    'sku',
    'name',
    'category',
    'default_sale_price',
    'last_purchase_price',
    'stock',
  ]);

  for (final r in rows) {
    book.appendRow(sheet, [
      _i((r['id'] as num?) ?? 0),
      _tx((r['sku'] ?? '').toString()),
      _tx((r['name'] ?? '').toString()),
      _tx((r['category'] ?? '').toString()),
      _d((r['default_sale_price'] as num?) ?? 0),
      _d((r['last_purchase_price'] as num?) ?? 0),
      _d((r['stock'] as num?) ?? 0),
    ]);
  }

  return _encode(book);
}

// ====================== EXPORT: CLIENTS =====================================

Future<Uint8List> buildClientsXlsxBytes() async {
  final db = await _db();
  final rows = await db.rawQuery('''
    SELECT phone, name, address
    FROM customers
    ORDER BY name COLLATE NOCASE
  ''');

  final book = ex.Excel.createExcel();
  if (book.sheets.containsKey('Sheet1')) book.delete('Sheet1');

  const sheet = 'clients';
  _appendHeader(book, sheet, ['phone', 'name', 'address']);

  for (final r in rows) {
    book.appendRow(sheet, [
      _tx((r['phone'] ?? '').toString()),
      _tx((r['name'] ?? '').toString()),
      _tx((r['address'] ?? '').toString()),
    ]);
  }

  return _encode(book);
}

// ====================== EXPORT: SUPPLIERS (robusto) ==========================

Future<Uint8List> buildSuppliersXlsxBytes() async {
  final db = await _db();

  final book = ex.Excel.createExcel();
  if (book.sheets.containsKey('Sheet1')) book.delete('Sheet1');

  const sheet = 'suppliers';

  if (!await _tableExists(db, 'suppliers')) {
    // Exporta vacío pero sin reventar
    _appendHeader(book, sheet, ['phone', 'name']);
    return _encode(book);
  }

  final hasAddress = await _hasColumn(db, 'suppliers', 'address');

  _appendHeader(book, sheet, [
    'phone',
    'name',
    if (hasAddress) 'address',
  ]);

  final rows = await db.rawQuery('''
    SELECT phone, name ${hasAddress ? ", address" : ""}
    FROM suppliers
    ORDER BY name COLLATE NOCASE
  ''');

  for (final r in rows) {
    book.appendRow(sheet, [
      _tx((r['phone'] ?? '').toString()),
      _tx((r['name'] ?? '').toString()),
      if (hasAddress) _tx((r['address'] ?? '').toString()),
    ]);
  }

  return _encode(book);
}

// ====================== EXPORT: SALES (+ detalle por SKU) ===================

Future<Uint8List> buildSalesXlsxBytes() async {
  final db = await _db();

  final salesRows = await db.rawQuery('''
    SELECT
      s.id,
      s.date,
      s.customer_phone,
      COALESCE(c.name,'') AS customer_name,
      COALESCE(s.payment_method,'') AS payment_method,
      COALESCE(s.discount,0) AS discount,
      COALESCE(s.shipping_cost,0) AS shipping_cost
    FROM sales s
    LEFT JOIN customers c ON c.phone = s.customer_phone
    ORDER BY s.date, s.id
  ''');

  final itemsRows = await db.rawQuery('''
    SELECT
      si.sale_id,
      si.product_id,
      p.sku,
      COALESCE(p.name,'') AS product_name,
      si.quantity,
      si.unit_price
    FROM sale_items si
    JOIN products p ON p.id = si.product_id
    ORDER BY si.sale_id, p.name
  ''');

  final flatRows = await db.rawQuery('''
    SELECT
      s.id AS sale_id,
      s.date,
      s.customer_phone,
      COALESCE(c.name,'') AS customer_name,
      COALESCE(s.payment_method,'') AS payment_method,
      COALESCE(s.discount,0) AS discount,
      COALESCE(s.shipping_cost,0) AS shipping_cost,
      si.product_id,
      p.sku,
      COALESCE(p.name,'') AS product_name,
      si.quantity,
      si.unit_price,
      COALESCE(p.last_purchase_price,0) AS unit_cost
    FROM sales s
    JOIN sale_items si ON si.sale_id = s.id
    JOIN products p ON p.id = si.product_id
    LEFT JOIN customers c ON c.phone = s.customer_phone
    ORDER BY s.id, p.name
  ''');

  final book = ex.Excel.createExcel();
  if (book.sheets.containsKey('Sheet1')) book.delete('Sheet1');

  const sSales = 'sales';
  const sItems = 'sale_items';
  const sDetail = 'sales_detail';

  _appendHeader(book, sSales, [
    'id',
    'date',
    'customer_phone',
    'customer_name',
    'payment_method',
    'discount',
    'shipping_cost',
  ]);

  for (final r in salesRows) {
    book.appendRow(sSales, [
      _i((r['id'] as num?) ?? 0),
      _tx((r['date'] ?? '').toString()),
      _tx((r['customer_phone'] ?? '').toString()),
      _tx((r['customer_name'] ?? '').toString()),
      _tx((r['payment_method'] ?? '').toString()),
      _d((r['discount'] as num?) ?? 0),
      _d((r['shipping_cost'] as num?) ?? 0),
    ]);
  }

  _appendHeader(book, sItems, [
    'sale_id',
    'product_id',
    'sku',
    'product_name',
    'quantity',
    'unit_price',
  ]);

  for (final r in itemsRows) {
    book.appendRow(sItems, [
      _i((r['sale_id'] as num?) ?? 0),
      _i((r['product_id'] as num?) ?? 0),
      _tx((r['sku'] ?? '').toString()),
      _tx((r['product_name'] ?? '').toString()),
      _d((r['quantity'] as num?) ?? 0),
      _d((r['unit_price'] as num?) ?? 0),
    ]);
  }

  _appendHeader(book, sDetail, [
    'sale_id',
    'date',
    'customer_phone',
    'customer_name',
    'payment_method',
    'sku',
    'product_name',
    'quantity',
    'unit_price',
    'line_gross',
    'unit_cost',
    'line_cost',
    'discount_total_alloc',
    'discount_per_unit',
    'shipping_total_alloc',
    'shipping_per_unit',
    'line_profit',
  ]);

  final bySale = <int, List<Map<String, Object?>>>{};
  for (final r in flatRows) {
    final saleId = (r['sale_id'] as int?) ?? 0;
    bySale.putIfAbsent(saleId, () => <Map<String, Object?>>[]).add(r);
  }

  for (final entry in bySale.entries) {
    final saleId = entry.key;
    final lines = entry.value;
    if (lines.isEmpty) continue;

    final first = lines.first;
    final discount = (first['discount'] as num?)?.toDouble() ?? 0.0;
    final shipping = (first['shipping_cost'] as num?)?.toDouble() ?? 0.0;

    double totalGross = 0.0;
    double totalQty = 0.0;
    for (final r in lines) {
      final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
      final unitPrice = (r['unit_price'] as num?)?.toDouble() ?? 0.0;
      totalQty += qty;
      totalGross += qty * unitPrice;
    }

    for (final r in lines) {
      final date = (r['date'] ?? '').toString();
      final customerPhone = (r['customer_phone'] ?? '').toString();
      final customerName = (r['customer_name'] ?? '').toString();
      final paymentMethod = (r['payment_method'] ?? '').toString();
      final sku = (r['sku'] ?? '').toString();
      final productName = (r['product_name'] ?? '').toString();
      final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
      final unitPrice = (r['unit_price'] as num?)?.toDouble() ?? 0.0;
      final unitCost = (r['unit_cost'] as num?)?.toDouble() ?? 0.0;

      final lineGross = qty * unitPrice;
      final lineCost = qty * unitCost;

      double share;
      if (totalGross > 0) {
        share = lineGross / totalGross;
      } else if (totalQty > 0) {
        share = qty / totalQty;
      } else {
        share = 0.0;
      }

      final lineDiscountTotal = discount * share;
      final discountPerUnit = qty > 0 ? lineDiscountTotal / qty : 0.0;

      final lineShippingTotal = shipping * share;
      final shippingPerUnit = qty > 0 ? lineShippingTotal / qty : 0.0;

      final lineNet = lineGross - lineDiscountTotal; // sin envío
      final lineProfit = lineNet - lineCost;

      book.appendRow(sDetail, [
        _i(saleId),
        _tx(date),
        _tx(customerPhone),
        _tx(customerName),
        _tx(paymentMethod),
        _tx(sku),
        _tx(productName),
        _d(qty),
        _d(unitPrice),
        _d(lineGross),
        _d(unitCost),
        _d(lineCost),
        _d(lineDiscountTotal),
        _d(discountPerUnit),
        _d(lineShippingTotal),
        _d(shippingPerUnit),
        _d(lineProfit),
      ]);
    }
  }

  return _encode(book);
}

// ====================== EXPORT: PURCHASES (robusto a schema) =================

Future<Uint8List> buildPurchasesXlsxBytes() async {
  final db = await _db();

  final book = ex.Excel.createExcel();
  if (book.sheets.containsKey('Sheet1')) book.delete('Sheet1');

  const sPurch = 'purchases';
  const sItems = 'purchase_items';

  // Si tu BD no trae compras, no revientes.
  if (!await _tableExists(db, 'purchases')) {
    _appendHeader(book, sPurch, ['purchase_id', 'folio', 'date', 'supplier_ref', 'supplier_name']);
    _appendHeader(book, sItems, ['purchase_id', 'product_id', 'sku', 'product_name', 'quantity', 'unit_cost', 'line_total']);
    return _encode(book);
  }

  final pCols = await _columnsOf(db, 'purchases');
  final hasSuppliers = await _tableExists(db, 'suppliers');

  final hasSupplierPhone = pCols.contains('supplier_phone');
  final hasSupplierId = pCols.contains('supplier_id');
  final hasSupplierText = pCols.contains('supplier') || pCols.contains('supplier_name');

  String supplierRefExpr = "''";
  String supplierNameExpr = "''";
  String joinClause = "";

  if (hasSuppliers) {
    final sCols = await _columnsOf(db, 'suppliers');
    final suppliersHasId = sCols.contains('id');
    final suppliersHasPhone = sCols.contains('phone');
    final suppliersHasName = sCols.contains('name');

    // A) purchases.supplier_phone -> suppliers.phone
    if (hasSupplierPhone && suppliersHasPhone && suppliersHasName) {
      supplierRefExpr = "COALESCE(p.supplier_phone,'')";
      supplierNameExpr = "COALESCE(s.name,'')";
      joinClause = "LEFT JOIN suppliers s ON s.phone = p.supplier_phone";
    }
    // B) purchases.supplier_id -> suppliers.id
    else if (hasSupplierId && suppliersHasId && suppliersHasName) {
      supplierRefExpr = "COALESCE(p.supplier_id,'')";
      supplierNameExpr = "COALESCE(s.name,'')";
      joinClause = "LEFT JOIN suppliers s ON s.id = p.supplier_id";
    }
    // C) texto directo en purchases
    else if (hasSupplierText) {
      final col = pCols.contains('supplier') ? 'supplier' : 'supplier_name';
      supplierRefExpr = "COALESCE(p.$col,'')";
      supplierNameExpr = "COALESCE(p.$col,'')";
      joinClause = "";
    }
  } else {
    // Sin tabla suppliers: usa lo que exista
    if (hasSupplierText) {
      final col = pCols.contains('supplier') ? 'supplier' : 'supplier_name';
      supplierRefExpr = "COALESCE(p.$col,'')";
      supplierNameExpr = "COALESCE(p.$col,'')";
    } else if (hasSupplierPhone) {
      supplierRefExpr = "COALESCE(p.supplier_phone,'')";
      supplierNameExpr = "COALESCE(p.supplier_phone,'')";
    } else if (hasSupplierId) {
      supplierRefExpr = "COALESCE(p.supplier_id,'')";
      supplierNameExpr = "COALESCE(p.supplier_id,'')";
    }
  }

  // Columnas de compras (folio/date pueden llamarse distinto en tu BD)
  final folioCol = pCols.contains('folio')
      ? 'folio'
      : (pCols.contains('code') ? 'code' : (pCols.contains('ref') ? 'ref' : null));
  final dateCol = pCols.contains('date')
      ? 'date'
      : (pCols.contains('created_at') ? 'created_at' : (pCols.contains('timestamp') ? 'timestamp' : null));

  final folioExpr = folioCol == null ? "''" : "COALESCE(p.$folioCol,'')";
  final dateExpr = dateCol == null ? "''" : "COALESCE(p.$dateCol,'')";

  _appendHeader(book, sPurch, [
    'purchase_id',
    'folio',
    'date',
    'supplier_ref',
    'supplier_name',
  ]);

  final heads = await db.rawQuery('''
    SELECT
      p.id AS purchase_id,
      $folioExpr AS folio,
      $dateExpr AS date,
      $supplierRefExpr AS supplier_ref,
      $supplierNameExpr AS supplier_name
    FROM purchases p
    $joinClause
    ORDER BY p.id
  ''');

  for (final r in heads) {
    book.appendRow(sPurch, [
      _i((r['purchase_id'] as num?) ?? 0),
      _tx((r['folio'] ?? '').toString()),
      _tx((r['date'] ?? '').toString()),
      _tx((r['supplier_ref'] ?? '').toString()),
      _tx((r['supplier_name'] ?? '').toString()),
    ]);
  }

  // ---- purchase_items robusto ----
  if (!await _tableExists(db, 'purchase_items')) {
    _appendHeader(book, sItems, ['purchase_id', 'product_id', 'sku', 'product_name', 'quantity', 'unit_cost', 'line_total']);
    return _encode(book);
  }

  final piCols = await _columnsOf(db, 'purchase_items');

  final purchaseIdCol = piCols.contains('purchase_id')
      ? 'purchase_id'
      : (piCols.contains('purchaseId') ? 'purchaseId' : null);

  final productIdCol = piCols.contains('product_id')
      ? 'product_id'
      : (piCols.contains('productId') ? 'productId' : null);

  final qtyCol = piCols.contains('quantity')
      ? 'quantity'
      : (piCols.contains('qty') ? 'qty' : null);

  // costo: intenta unit_cost, luego unit_price, luego cost
  final costCol = piCols.contains('unit_cost')
      ? 'unit_cost'
      : (piCols.contains('unit_price') ? 'unit_price' : (piCols.contains('cost') ? 'cost' : null));

  _appendHeader(book, sItems, [
    'purchase_id',
    'product_id',
    'sku',
    'product_name',
    'quantity',
    'unit_cost',
    'line_total',
  ]);

  // Si no hay columnas clave, exporta vacío sin fallar
  if (purchaseIdCol == null || productIdCol == null || qtyCol == null || costCol == null) {
    return _encode(book);
  }

  final items = await db.rawQuery('''
    SELECT
      pi.$purchaseIdCol AS purchase_id,
      pi.$productIdCol AS product_id,
      pr.sku,
      COALESCE(pr.name,'') AS product_name,
      COALESCE(pi.$qtyCol,0) AS quantity,
      COALESCE(pi.$costCol,0) AS unit_cost
    FROM purchase_items pi
    JOIN products pr ON pr.id = pi.$productIdCol
    ORDER BY pi.$purchaseIdCol, pr.name
  ''');

  for (final r in items) {
    final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
    final unitCost = (r['unit_cost'] as num?)?.toDouble() ?? 0.0;
    final lineTotal = qty * unitCost;

    book.appendRow(sItems, [
      _i((r['purchase_id'] as num?) ?? 0),
      _i((r['product_id'] as num?) ?? 0),
      _tx((r['sku'] ?? '').toString()),
      _tx((r['product_name'] ?? '').toString()),
      _d(qty),
      _d(unitCost),
      _d(lineTotal),
    ]);
  }

  return _encode(book);
}

// ====================== IMPORT: PRODUCTS ====================================

Future<void> importProductsXlsxBytes(Uint8List bytes) async {
  final db = await _db();
  final excel = ex.Excel.decodeBytes(bytes);
  final sheet = excel['products'];
  if (sheet == null) return;

  final rows = sheet.rows;
  if (rows.length <= 1) return;

  final batch = db.batch();

  for (var i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.isEmpty) continue;

    final id = _cellAsInt(_cell(row, 0));
    final sku = _cellAsString(_cell(row, 1)).trim();
    final name = _cellAsString(_cell(row, 2)).trim();
    final category = _cellAsString(_cell(row, 3)).trim();
    final defaultSalePrice = _cellAsDouble(_cell(row, 4));
    final lastPurchasePrice = _cellAsDouble(_cell(row, 5));
    final stock = _cellAsDouble(_cell(row, 6));

    if (sku.isEmpty && name.isEmpty) continue;

    final data = <String, Object?>{
      'sku': sku,
      'name': name,
      'category': category,
      'default_sale_price': defaultSalePrice,
      'last_purchase_price': lastPurchasePrice,
      'stock': stock,
    };

    if (id > 0) data['id'] = id;

    batch.insert(
      'products',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  await batch.commit(noResult: true);
}

// ====================== IMPORT: CLIENTS =====================================

Future<void> importClientsXlsxBytes(Uint8List bytes) async {
  final db = await _db();
  final excel = ex.Excel.decodeBytes(bytes);
  final sheet = excel['clients'];
  if (sheet == null) return;

  final rows = sheet.rows;
  if (rows.length <= 1) return;

  final batch = db.batch();

  for (var i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.isEmpty) continue;

    final phone = _cellAsString(_cell(row, 0)).trim();
    final name = _cellAsString(_cell(row, 1)).trim();
    final address = _cellAsString(_cell(row, 2)).trim();

    if (phone.isEmpty) continue;

    batch.insert(
      'customers',
      {
        'phone': phone,
        'name': name,
        'address': address,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  await batch.commit(noResult: true);
}

// ====================== IMPORT: SUPPLIERS ===================================

Future<void> importSuppliersXlsxBytes(Uint8List bytes) async {
  final db = await _db();
  final excel = ex.Excel.decodeBytes(bytes);
  final sheet = excel['suppliers'];
  if (sheet == null) return;

  final rows = sheet.rows;
  if (rows.length <= 1) return;

  final batch = db.batch();

  for (var i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.isEmpty) continue;

    final phone = _cellAsString(_cell(row, 0)).trim();
    final name = _cellAsString(_cell(row, 1)).trim();
    final address = _cellAsString(_cell(row, 2)).trim();

    if (phone.isEmpty) continue;

    batch.insert(
      'suppliers',
      {
        'phone': phone,
        'name': name,
        'address': address,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  await batch.commit(noResult: true);
}

// ====================== IMPORT: SALES / PURCHASES ===========================

Future<void> importSalesXlsxBytes(Uint8List bytes) async {
  throw UnimplementedError(
    'Importar Ventas desde XLSX no está implementado todavía. '
    'La exportación sí genera sales / sale_items / sales_detail.',
  );
}

Future<void> importPurchasesXlsxBytes(Uint8List bytes) async {
  throw UnimplementedError(
    'Importar Compras desde XLSX no está implementado todavía. '
    'La exportación sí genera purchases / purchase_items.',
  );
}