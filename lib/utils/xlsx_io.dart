import 'dart:typed_data';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db.dart';

/// Resumen de una importación.
class ImportReport {
  int inserted = 0;
  int updated = 0;
  int skipped = 0;
  final List<String> errors = [];

  @override
  String toString() {
    final parts = <String>[
      'Insertados: $inserted',
      'Actualizados: $updated',
      'Omitidos: $skipped',
    ];
    if (errors.isNotEmpty) parts.add('Errores: ${errors.length}');
    return parts.join(' • ');
  }
}

/// -------- UTILIDADES --------

final _dateIso = DateFormat("yyyy-MM-dd'T'HH:mm:ss");

Sheet _sheet(Excel ex, String name) {
  // excel[name] crea la hoja si no existe
  return ex[name];
}

List<List<Data?>> _rows(Sheet sh) => sh.rows;

String _asString(Data? cell) {
  final v = cell?.value;
  if (v == null) return '';
  return v is String ? v.trim() : v.toString().trim();
}

double _asDouble(Data? cell) {
  final v = cell?.value;
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  final s = v.toString().replaceAll(',', '.');
  return double.tryParse(s) ?? 0.0;
}

int _asInt(Data? cell) {
  final v = cell?.value;
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

DateTime? _asDate(Data? cell) {
  final v = cell?.value;
  if (v == null) return null;
  if (v is DateTime) return v;
  final s = v.toString().trim();
  try {
    return DateTime.parse(s);
  } catch (_) {
    return null;
  }
}

/// Convierte dinámicos a CellValue (excel 4.x).
/// Para DateTime escribimos **texto ISO** para evitar incompatibilidades.
CellValue _cv(dynamic v) {
  if (v == null) return TextCellValue('');
  if (v is String) return TextCellValue(v);
  if (v is int) return IntCellValue(v);
  if (v is double) return DoubleCellValue(v);
  if (v is num) return DoubleCellValue(v.toDouble());
  if (v is DateTime) return TextCellValue(_dateIso.format(v));
  return TextCellValue(v.toString());
}

/// Guarda XLSX con FileSaver (puede o no devolver ruta visible).
Future<String?> _saveXlsx(String fname, Uint8List bytes) async {
  final path = await FileSaver.instance.saveFile(
    name: fname,
    bytes: bytes,
    ext: 'xlsx',
    mimeType: MimeType.microsoftExcel,
  );
  return (path is String && path.isNotEmpty) ? path : null;
}

/// Selector de .xlsx -> bytes
Future<Uint8List?> pickXlsxBytes() async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    allowMultiple: false,
    withData: true,
  );
  if (res == null) return null;
  final f = res.files.single;
  if (f.bytes != null) return f.bytes!;
  if (f.path != null) return File(f.path!).readAsBytes();
  return null;
}

/// -------- EXPORT: PRODUCTS --------
/// Hoja: products (sku, name, category, default_sale_price, last_purchase_price, stock)
Future<Uint8List> rebuildProductsXlsxBytes() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('products', orderBy: 'name COLLATE NOCASE');

  final ex = Excel.createExcel();
  final sh = _sheet(ex, 'products');

  sh.appendRow([
    _cv('sku'),
    _cv('name'),
    _cv('category'),
    _cv('default_sale_price'),
    _cv('last_purchase_price'),
    _cv('stock'),
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

  return Uint8List.fromList(ex.encode()!);
}

Future<String?> exportProductsXlsx() async {
  final bytes = await rebuildProductsXlsxBytes();
  return _saveXlsx('productos', bytes);
}

/// -------- EXPORT: CLIENTS --------
/// Hoja: customers (phone, name, address)
Future<Uint8List> rebuildClientsXlsxBytes() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('customers', orderBy: 'name COLLATE NOCASE');

  final ex = Excel.createExcel();
  final sh = _sheet(ex, 'customers');

  sh.appendRow([_cv('phone'), _cv('name'), _cv('address')]);
  for (final r in rows) {
    sh.appendRow([_cv(r['phone']), _cv(r['name']), _cv(r['address'])]);
  }
  return Uint8List.fromList(ex.encode()!);
}

Future<String?> exportClientsXlsx() async {
  final bytes = await rebuildClientsXlsxBytes();
  return _saveXlsx('clientes', bytes);
}

/// -------- EXPORT: SUPPLIERS --------
/// Hoja: suppliers (phone, name, address)
Future<Uint8List> rebuildSuppliersXlsxBytes() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('suppliers', orderBy: 'name COLLATE NOCASE');

  final ex = Excel.createExcel();
  final sh = _sheet(ex, 'suppliers');

  sh.appendRow([_cv('phone'), _cv('name'), _cv('address')]);
  for (final r in rows) {
    sh.appendRow([_cv(r['phone']), _cv(r['name']), _cv(r['address'])]);
  }
  return Uint8List.fromList(ex.encode()!);
}

Future<String?> exportSuppliersXlsx() async {
  final bytes = await rebuildSuppliersXlsxBytes();
  return _saveXlsx('proveedores', bytes);
}

/// -------- EXPORT: SALES --------
/// sales: id, customer_phone, payment_method, place, shipping_cost, discount, date (ISO)
/// sale_items: sale_id, product_sku, quantity, unit_price
Future<Uint8List> rebuildSalesXlsxBytes() async {
  final db = await DatabaseHelper.instance.db;

  final ex = Excel.createExcel();
  final s = _sheet(ex, 'sales');
  final si = _sheet(ex, 'sale_items');

  s.appendRow([
    _cv('id'),
    _cv('customer_phone'),
    _cv('payment_method'),
    _cv('place'),
    _cv('shipping_cost'),
    _cv('discount'),
    _cv('date'),
  ]);

  final sales = await db.query('sales', orderBy: 'date DESC');
  for (final r in sales) {
    s.appendRow([
      _cv(r['id']),
      _cv(r['customer_phone']),
      _cv(r['payment_method']),
      _cv(r['place']),
      _cv((r['shipping_cost'] as num?)?.toDouble() ?? 0),
      _cv((r['discount'] as num?)?.toDouble() ?? 0),
      _cv((r['date'] ?? '').toString()),
    ]);
  }

  si.appendRow([
    _cv('sale_id'),
    _cv('product_sku'),
    _cv('quantity'),
    _cv('unit_price'),
  ]);

  final items = await db.rawQuery('''
    SELECT si.sale_id, p.sku AS product_sku, si.quantity, si.unit_price
    FROM sale_items si
    JOIN products p ON p.id = si.product_id
    ORDER BY si.sale_id DESC
  ''');

  for (final r in items) {
    si.appendRow([
      _cv(r['sale_id']),
      _cv(r['product_sku']),
      _cv((r['quantity'] as num?)?.toInt() ?? 0),
      _cv((r['unit_price'] as num?)?.toDouble() ?? 0),
    ]);
  }

  return Uint8List.fromList(ex.encode()!);
}

Future<String?> exportSalesXlsx() async {
  final bytes = await rebuildSalesXlsxBytes();
  return _saveXlsx('ventas', bytes);
}

/// -------- EXPORT: PURCHASES --------
/// purchases: id, folio, supplier_phone, date (ISO)
/// purchase_items: purchase_id, product_sku, quantity, unit_cost
Future<Uint8List> rebuildPurchasesXlsxBytes() async {
  final db = await DatabaseHelper.instance.db;

  final ex = Excel.createExcel();
  final s = _sheet(ex, 'purchases');
  final si = _sheet(ex, 'purchase_items');

  s.appendRow([_cv('id'), _cv('folio'), _cv('supplier_phone'), _cv('date')]);

  final purchases = await db.query('purchases', orderBy: 'date DESC');
  for (final r in purchases) {
    s.appendRow([
      _cv(r['id']),
      _cv(r['folio']),
      _cv(r['supplier_phone']),
      _cv((r['date'] ?? '').toString()),
    ]);
  }

  si.appendRow([
    _cv('purchase_id'),
    _cv('product_sku'),
    _cv('quantity'),
    _cv('unit_cost'),
  ]);

  final items = await db.rawQuery('''
    SELECT pi.purchase_id, p.sku AS product_sku, pi.quantity, pi.unit_cost
    FROM purchase_items pi
    JOIN products p ON p.id = pi.product_id
    ORDER BY pi.purchase_id DESC
  ''');

  for (final r in items) {
    si.appendRow([
      _cv(r['purchase_id']),
      _cv(r['product_sku']),
      _cv((r['quantity'] as num?)?.toInt() ?? 0),
      _cv((r['unit_cost'] as num?)?.toDouble() ?? 0),
    ]);
  }

  return Uint8List.fromList(ex.encode()!);
}

Future<String?> exportPurchasesXlsx() async {
  final bytes = await rebuildPurchasesXlsxBytes();
  return _saveXlsx('compras', bytes);
}

/// -------- IMPORT: PRODUCTS --------
/// Hoja "products": sku (PK lógico, obligatorio y único), name, category, default_sale_price, last_purchase_price, stock
Future<ImportReport> importProductsXlsx(Uint8List bytes) async {
  final rep = ImportReport();
  final ex = Excel.decodeBytes(bytes);
  final sh = ex.sheets['products'];
  if (sh == null) {
    rep.errors.add('No se encontró hoja "products"');
    return rep;
  }

  final db = await DatabaseHelper.instance.db;
  final rows = _rows(sh);

  for (var i = 1; i < rows.length; i++) {
    final r = rows[i];
    final sku = _asString(r.elementAtOrNull(0));
    if (sku.isEmpty) {
      rep.skipped++;
      continue; // SKU obligatorio
    }
    final name = _asString(r.elementAtOrNull(1));
    final category = _asString(r.elementAtOrNull(2));
    final defSale = _asDouble(r.elementAtOrNull(3));
    final lastCost = _asDouble(r.elementAtOrNull(4));
    final stock = _asInt(r.elementAtOrNull(5));

    try {
      final exist = await db.query(
        'products',
        columns: ['id'],
        where: 'sku = ?',
        whereArgs: [sku],
        limit: 1,
      );

      if (exist.isEmpty) {
        await db.insert('products', {
          'sku': sku,
          'name': name,
          'category': category,
          'default_sale_price': defSale,
          'last_purchase_price': lastCost,
          'stock': stock,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
        rep.inserted++;
      } else {
        await db.update(
          'products',
          {
            'name': name,
            'category': category,
            'default_sale_price': defSale,
            'last_purchase_price': lastCost,
            'stock': stock,
          },
          where: 'sku = ?',
          whereArgs: [sku],
        );
        rep.updated++;
      }
    } catch (e) {
      rep.errors.add('Fila ${i + 1} (SKU $sku): $e');
    }
  }

  return rep;
}

/// -------- IMPORT: CLIENTS --------
/// Hoja "customers": phone (PK lógico), name, address
Future<ImportReport> importClientsXlsx(Uint8List bytes) async {
  final rep = ImportReport();
  final ex = Excel.decodeBytes(bytes);
  final sh = ex.sheets['customers'];
  if (sh == null) {
    rep.errors.add('No se encontró hoja "customers"');
    return rep;
  }

  final db = await DatabaseHelper.instance.db;
  final rows = _rows(sh);

  for (var i = 1; i < rows.length; i++) {
    final r = rows[i];
    final phone = _asString(r.elementAtOrNull(0));
    if (phone.isEmpty) {
      rep.skipped++;
      continue;
    }
    final name = _asString(r.elementAtOrNull(1));
    final address = _asString(r.elementAtOrNull(2));

    try {
      final exist = await db.query(
        'customers',
        where: 'phone = ?',
        whereArgs: [phone],
        limit: 1,
      );
      if (exist.isEmpty) {
        await db.insert('customers', {
          'phone': phone,
          'name': name,
          'address': address,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
        rep.inserted++;
      } else {
        await db.update(
          'customers',
          {'name': name, 'address': address},
          where: 'phone = ?',
          whereArgs: [phone],
        );
        rep.updated++;
      }
    } catch (e) {
      rep.errors.add('Fila ${i + 1} (phone $phone): $e');
    }
  }

  return rep;
}

/// -------- IMPORT: SUPPLIERS --------
/// Hoja "suppliers": phone (PK lógico), name, address
Future<ImportReport> importSuppliersXlsx(Uint8List bytes) async {
  final rep = ImportReport();
  final ex = Excel.decodeBytes(bytes);
  final sh = ex.sheets['suppliers'];
  if (sh == null) {
    rep.errors.add('No se encontró hoja "suppliers"');
    return rep;
  }

  final db = await DatabaseHelper.instance.db;
  final rows = _rows(sh);

  for (var i = 1; i < rows.length; i++) {
    final r = rows[i];
    final phone = _asString(r.elementAtOrNull(0));
    if (phone.isEmpty) {
      rep.skipped++;
      continue;
    }
    final name = _asString(r.elementAtOrNull(1));
    final address = _asString(r.elementAtOrNull(2));

    try {
      final exist = await db.query(
        'suppliers',
        where: 'phone = ?',
        whereArgs: [phone],
        limit: 1,
      );
      if (exist.isEmpty) {
        await db.insert('suppliers', {
          'phone': phone,
          'name': name,
          'address': address,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
        rep.inserted++;
      } else {
        await db.update(
          'suppliers',
          {'name': name, 'address': address},
          where: 'phone = ?',
          whereArgs: [phone],
        );
        rep.updated++;
      }
    } catch (e) {
      rep.errors.add('Fila ${i + 1} (phone $phone): $e');
    }
  }

  return rep;
}

/// -------- IMPORT: SALES --------
/// Hoja "sales": id, customer_phone, payment_method, place, shipping_cost, discount, date (ISO)
/// Hoja "sale_items": sale_id, product_sku, quantity, unit_price
Future<ImportReport> importSalesXlsx(Uint8List bytes) async {
  final rep = ImportReport();
  final ex = Excel.decodeBytes(bytes);
  final s = ex.sheets['sales'];
  final si = ex.sheets['sale_items'];
  if (s == null || si == null) {
    rep.errors.add('Faltan hojas "sales" o "sale_items"');
    return rep;
  }

  final db = await DatabaseHelper.instance.db;
  final rowsS = _rows(s);
  final rowsI = _rows(si);

  for (var i = 1; i < rowsS.length; i++) {
    final r = rowsS[i];
    final id = _asInt(r.elementAtOrNull(0));
    if (id <= 0) {
      rep.skipped++;
      continue;
    }
    final phone = _asString(r.elementAtOrNull(1));
    final pay = _asString(r.elementAtOrNull(2));
    final place = _asString(r.elementAtOrNull(3));
    final ship = _asDouble(r.elementAtOrNull(4));
    final disc = _asDouble(r.elementAtOrNull(5));
    final dateStr = _asString(r.elementAtOrNull(6));
    final date = DateTime.tryParse(dateStr) ?? DateTime.now();

    try {
      final exist =
          await db.query('sales', where: 'id = ?', whereArgs: [id], limit: 1);
      if (exist.isEmpty) {
        await db.insert('sales', {
          'id': id,
          'customer_phone': phone,
          'payment_method': pay,
          'place': place,
          'shipping_cost': ship,
          'discount': disc,
          'date': _dateIso.format(date),
        }, conflictAlgorithm: ConflictAlgorithm.abort);
        rep.inserted++;
      } else {
        await db.update(
          'sales',
          {
            'customer_phone': phone,
            'payment_method': pay,
            'place': place,
            'shipping_cost': ship,
            'discount': disc,
            'date': _dateIso.format(date),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        // limpiar items previos
        await db.delete('sale_items', where: 'sale_id = ?', whereArgs: [id]);
        rep.updated++;
      }
    } catch (e) {
      rep.errors.add('Venta id=$id: $e');
    }
  }

  for (var i = 1; i < rowsI.length; i++) {
    final r = rowsI[i];
    final saleId = _asInt(r.elementAtOrNull(0));
    if (saleId <= 0) {
      rep.skipped++;
      continue;
    }
    final sku = _asString(r.elementAtOrNull(1));
    final qty = _asInt(r.elementAtOrNull(2));
    final price = _asDouble(r.elementAtOrNull(3));
    if (sku.isEmpty || qty <= 0) {
      rep.skipped++;
      continue;
    }
    try {
      final prod = await db
          .query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
      if (prod.isEmpty) {
        rep.errors.add('sale_items fila ${i + 1}: SKU $sku no existe');
        continue;
      }
      final pid = prod.first['id'] as int;

      await db.insert('sale_items', {
        'sale_id': saleId,
        'product_id': pid,
        'quantity': qty,
        'unit_price': price,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      rep.errors.add('sale_items fila ${i + 1}: $e');
    }
  }

  return rep;
}

/// -------- IMPORT: PURCHASES --------
/// Hoja "purchases": id, folio, supplier_phone, date (ISO)
/// Hoja "purchase_items": purchase_id, product_sku, quantity, unit_cost
Future<ImportReport> importPurchasesXlsx(Uint8List bytes) async {
  final rep = ImportReport();
  final ex = Excel.decodeBytes(bytes);
  final s = ex.sheets['purchases'];
  final si = ex.sheets['purchase_items'];
  if (s == null || si == null) {
    rep.errors.add('Faltan hojas "purchases" o "purchase_items"');
    return rep;
  }

  final db = await DatabaseHelper.instance.db;
  final rowsS = _rows(s);
  final rowsI = _rows(si);

  for (var i = 1; i < rowsS.length; i++) {
    final r = rowsS[i];
    final id = _asInt(r.elementAtOrNull(0));
    if (id <= 0) {
      rep.skipped++;
      continue;
    }
    final folio = _asString(r.elementAtOrNull(1));
    final supplierPhone = _asString(r.elementAtOrNull(2));
    final dateStr = _asString(r.elementAtOrNull(3));
    final date = DateTime.tryParse(dateStr) ?? DateTime.now();

    try {
      final exist = await db
          .query('purchases', where: 'id = ?', whereArgs: [id], limit: 1);
      if (exist.isEmpty) {
        await db.insert('purchases', {
          'id': id,
          'folio': folio,
          'supplier_phone': supplierPhone,
          'date': _dateIso.format(date),
        }, conflictAlgorithm: ConflictAlgorithm.abort);
        rep.inserted++;
      } else {
        await db.update(
          'purchases',
          {
            'folio': folio,
            'supplier_phone': supplierPhone,
            'date': _dateIso.format(date),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        await db.delete('purchase_items',
            where: 'purchase_id = ?', whereArgs: [id]);
        rep.updated++;
      }
    } catch (e) {
      rep.errors.add('Compra id=$id: $e');
    }
  }

  for (var i = 1; i < rowsI.length; i++) {
    final r = rowsI[i];
    final purchaseId = _asInt(r.elementAtOrNull(0));
    if (purchaseId <= 0) {
      rep.skipped++;
      continue;
    }
    final sku = _asString(r.elementAtOrNull(1));
    final qty = _asInt(r.elementAtOrNull(2));
    final cost = _asDouble(r.elementAtOrNull(3));
    if (sku.isEmpty || qty <= 0) {
      rep.skipped++;
      continue;
    }
    try {
      final prod = await db
          .query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
      if (prod.isEmpty) {
        rep.errors.add('purchase_items fila ${i + 1}: SKU $sku no existe');
        continue;
      }
      final pid = prod.first['id'] as int;

      await db.insert('purchase_items', {
        'purchase_id': purchaseId,
        'product_id': pid,
        'quantity': qty,
        'unit_cost': cost,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Actualiza inventario y último costo
      await db.rawUpdate(
        'UPDATE products SET stock = COALESCE(stock,0) + ?, last_purchase_price = ? WHERE id = ?',
        [qty, cost, pid],
      );
    } catch (e) {
      rep.errors.add('purchase_items fila ${i + 1}: $e');
    }
  }

  return rep;
}