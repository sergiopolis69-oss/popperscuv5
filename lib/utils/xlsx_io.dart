import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

final _money = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

class ImportReport {
  final int inserted;
  final int updated;
  final int skipped;
  final List<String> errors;
  const ImportReport(this.inserted, this.updated, this.skipped, this.errors);

  @override
  String toString() =>
      'Insertados: $inserted • Actualizados: $updated • Omitidos: $skipped'
      '${errors.isEmpty ? '' : '\nErrores:\n- ${errors.join('\n- ')}'}';
}

// ---------------------------------------------------------------------
// Helpers Excel
// ---------------------------------------------------------------------

String _ts() => DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

Sheet _sheet(Excel ex, String name) {
  return ex.sheets[name] ?? ex..insertSheet(name) as Excel ? ex.sheets[name] as Sheet : ex.sheets[name]!;
}

List<List<Data?>> _readSheet(Excel ex, String name) {
  final sh = ex.sheets[name];
  if (sh == null) return const [];
  return sh.rows.map((r) => r.map((c) => c?.value).toList()).toList();
}

String _cellStr(List<Data?> row, int idx) {
  final v = idx < row.length ? row[idx] : null;
  return (v is String ? v : v?.toString() ?? '').trim();
}

double _cellNum(List<Data?> row, int idx) {
  final v = idx < row.length ? row[idx] : null;
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0.0;
}

int _cellInt(List<Data?> row, int idx) {
  return _cellNum(row, idx).toInt();
}

DateTime? _cellDate(List<Data?> row, int idx) {
  final v = idx < row.length ? row[idx] : null;
  if (v == null) return null;
  if (v is DateTime) return v;
  // Excel a veces trae fecha como string ISO o número (serial)
  final s = v.toString();
  final tryIso = DateTime.tryParse(s);
  if (tryIso != null) return tryIso;
  final n = double.tryParse(s);
  if (n != null) {
    // serial excel (1900-based)
    return DateTime(1899, 12, 30).add(Duration(days: n.round()));
  }
  return null;
}

// ---------------------------------------------------------------------
// EXPORTACIONES
// ---------------------------------------------------------------------

Future<void> exportProductsXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.rawQuery('SELECT sku,name,category,default_sale_price,last_purchase_price,stock FROM products ORDER BY name COLLATE NOCASE');

  final ex = Excel.createExcel();
  final s = _sheet(ex, 'products');

  s.appendRow([
    const TextCellValue('sku'),
    const TextCellValue('name'),
    const TextCellValue('category'),
    const TextCellValue('default_sale_price'),
    const TextCellValue('last_purchase_price'),
    const TextCellValue('stock'),
  ]);

  for (final r in rows) {
    s.appendRow([
      TextCellValue((r['sku'] ?? '').toString()),
      TextCellValue((r['name'] ?? '').toString()),
      TextCellValue((r['category'] ?? '').toString()),
      DoubleCellValue((r['default_sale_price'] as num?)?.toDouble() ?? 0),
      DoubleCellValue((r['last_purchase_price'] as num?)?.toDouble() ?? 0),
      IntCellValue((r['stock'] as num?)?.toInt() ?? 0),
    ]);
  }

  final bytes = ex.save()!;
  await FileSaver.instance.saveFile(
    name: 'productos_${_ts()}',
    bytes: Uint8List.fromList(bytes),
    ext: 'xlsx',
    mimeType: MimeType.microsoftExcel,
  );
}

Future<void> exportClientsXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.rawQuery('SELECT phone,name,address FROM customers ORDER BY name COLLATE NOCASE');

  final ex = Excel.createExcel();
  final s = _sheet(ex, 'customers');

  s.appendRow([
    const TextCellValue('phone'),
    const TextCellValue('name'),
    const TextCellValue('address'),
  ]);

  for (final r in rows) {
    s.appendRow([
      TextCellValue((r['phone'] ?? '').toString()),
      TextCellValue((r['name'] ?? '').toString()),
      TextCellValue((r['address'] ?? '').toString()),
    ]);
  }

  final bytes = ex.save()!;
  await FileSaver.instance.saveFile(
    name: 'clientes_${_ts()}',
    bytes: Uint8List.fromList(bytes),
    ext: 'xlsx',
    mimeType: MimeType.microsoftExcel,
  );
}

Future<void> exportSuppliersXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.rawQuery('SELECT phone,name,address FROM suppliers ORDER BY name COLLATE NOCASE');

  final ex = Excel.createExcel();
  final s = _sheet(ex, 'suppliers');

  s.appendRow([
    const TextCellValue('phone'),
    const TextCellValue('name'),
    const TextCellValue('address'),
  ]);

  for (final r in rows) {
    s.appendRow([
      TextCellValue((r['phone'] ?? '').toString()),
      TextCellValue((r['name'] ?? '').toString()),
      TextCellValue((r['address'] ?? '').toString()),
    ]);
  }

  final bytes = ex.save()!;
  await FileSaver.instance.saveFile(
    name: 'proveedores_${_ts()}',
    bytes: Uint8List.fromList(bytes),
    ext: 'xlsx',
    mimeType: MimeType.microsoftExcel,
  );
}

Future<void> exportSalesXlsx() async {
  final db = await DatabaseHelper.instance.db;

  final sales = await db.rawQuery('SELECT id,customer_phone,payment_method,place,shipping_cost,discount,date FROM sales ORDER BY date DESC');
  final items = await db.rawQuery('SELECT sale_id,product_id,quantity,unit_price, p.sku FROM sale_items si INNER JOIN products p ON p.id = si.product_id ORDER BY sale_id');

  final ex = Excel.createExcel();

  final s = _sheet(ex, 'sales');
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
      IntCellValue((r['id'] as num).toInt()),
      TextCellValue((r['customer_phone'] ?? '').toString()),
      TextCellValue((r['payment_method'] ?? '').toString()),
      TextCellValue((r['place'] ?? '').toString()),
      DoubleCellValue((r['shipping_cost'] as num?)?.toDouble() ?? 0),
      DoubleCellValue((r['discount'] as num?)?.toDouble() ?? 0),
      TextCellValue((r['date'] ?? '').toString()),
    ]);
  }

  final si = _sheet(ex, 'sale_items');
  si.appendRow([
    const TextCellValue('sale_id'),
    const TextCellValue('product_sku'),
    const TextCellValue('quantity'),
    const TextCellValue('unit_price'),
  ]);
  for (final r in items) {
    si.appendRow([
      IntCellValue((r['sale_id'] as num).toInt()),
      TextCellValue((r['sku'] ?? '').toString()),
      IntCellValue((r['quantity'] as num?)?.toInt() ?? 0),
      DoubleCellValue((r['unit_price'] as num?)?.toDouble() ?? 0),
    ]);
  }

  final bytes = ex.save()!;
  await FileSaver.instance.saveFile(
    name: 'ventas_${_ts()}',
    bytes: Uint8List.fromList(bytes),
    ext: 'xlsx',
    mimeType: MimeType.microsoftExcel,
  );
}

Future<void> exportPurchasesXlsx() async {
  final db = await DatabaseHelper.instance.db;

  final purchases = await db.rawQuery('SELECT id,folio,supplier_phone as supplier_id,date FROM purchases ORDER BY date DESC');
  final items = await db.rawQuery('SELECT purchase_id,product_id,quantity,unit_cost, p.sku FROM purchase_items pi INNER JOIN products p ON p.id = pi.product_id ORDER BY purchase_id');

  final ex = Excel.createExcel();

  final s = _sheet(ex, 'purchases');
  s.appendRow([
    const TextCellValue('id'),
    const TextCellValue('folio'),
    const TextCellValue('supplier_id'),
    const TextCellValue('date'),
  ]);
  for (final r in purchases) {
    s.appendRow([
      IntCellValue((r['id'] as num).toInt()),
      TextCellValue((r['folio'] ?? '').toString()),
      TextCellValue((r['supplier_id'] ?? '').toString()),
      TextCellValue((r['date'] ?? '').toString()),
    ]);
  }

  final si = _sheet(ex, 'purchase_items');
  si.appendRow([
    const TextCellValue('purchase_id'),
    const TextCellValue('product_sku'),
    const TextCellValue('quantity'),
    const TextCellValue('unit_cost'),
  ]);
  for (final r in items) {
    si.appendRow([
      IntCellValue((r['purchase_id'] as num).toInt()),
      TextCellValue((r['sku'] ?? '').toString()),
      IntCellValue((r['quantity'] as num?)?.toInt() ?? 0),
      DoubleCellValue((r['unit_cost'] as num?)?.toDouble() ?? 0),
    ]);
  }

  final bytes = ex.save()!;
  await FileSaver.instance.saveFile(
    name: 'compras_${_ts()}',
    bytes: Uint8List.fromList(bytes),
    ext: 'xlsx',
    mimeType: MimeType.microsoftExcel,
  );
}

// ---------------------------------------------------------------------
// IMPORTACIONES (desde selector de archivo .xlsx)
// ---------------------------------------------------------------------

Future<ImportReport> importProductsXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final ex = Excel.decodeBytes(bytes);

  final rows = _readSheet(ex, 'products');
  if (rows.isEmpty) return const ImportReport(0, 0, 0, ['Hoja "products" vacía o no existe']);

  // Headers esperados
  final header = rows.first.map((c) => c?.toString().trim().toLowerCase()).toList();
  final expect = ['sku','name','category','default_sale_price','last_purchase_price','stock'];
  for (final h in expect) {
    if (!header.contains(h)) {
      return ImportReport(0, 0, 0, ['Falta la columna "$h" en products']);
    }
  }

  int ins = 0, upd = 0, skip = 0;
  final errors = <String>[];

  final skuIdx = header.indexOf('sku');
  final nameIdx = header.indexOf('name');
  final catIdx  = header.indexOf('category');
  final spIdx   = header.indexOf('default_sale_price');
  final cpIdx   = header.indexOf('last_purchase_price');
  final stIdx   = header.indexOf('stock');

  final batch = db.batch();
  final seenSkus = <String>{};

  for (var i = 1; i < rows.length; i++) {
    final r = rows[i];
    final sku = _cellStr(r, skuIdx);
    if (sku.isEmpty) { skip++; continue; }
    if (seenSkus.contains(sku)) { skip++; continue; }
    seenSkus.add(sku);

    final name = _cellStr(r, nameIdx);
    final cat  = _cellStr(r, catIdx);
    final sale = _cellNum(r, spIdx);
    final cost = _cellNum(r, cpIdx);
    final stock= _cellInt(r, stIdx);

    try {
      // upsert por SKU
      final exists = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
      if (exists.isEmpty) {
        batch.insert('products', {
          'sku': sku,
          'name': name,
          'category': cat,
          'default_sale_price': sale,
          'last_purchase_price': cost,
          'stock': stock,
        });
        ins++;
      } else {
        final id = exists.first['id'] as int;
        batch.update('products', {
          'name': name,
          'category': cat,
          'default_sale_price': sale,
          'last_purchase_price': cost,
          'stock': stock,
        }, where: 'id = ?', whereArgs: [id]);
        upd++;
      }
    } catch (e) {
      errors.add('Fila ${i+1} (${sku}): $e');
      skip++;
    }
  }

  await batch.commit(noResult: true);
  return ImportReport(ins, upd, skip, errors);
}

Future<ImportReport> importClientsXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final ex = Excel.decodeBytes(bytes);

  final rows = _readSheet(ex, 'customers');
  if (rows.isEmpty) return const ImportReport(0, 0, 0, ['Hoja "customers" vacía o no existe']);

  final header = rows.first.map((c) => c?.toString().trim().toLowerCase()).toList();
  final expect = ['phone','name','address'];
  for (final h in expect) {
    if (!header.contains(h)) {
      return ImportReport(0, 0, 0, ['Falta la columna "$h" en customers']);
    }
  }

  int ins = 0, upd = 0, skip = 0;
  final phoneIdx = header.indexOf('phone');
  final nameIdx  = header.indexOf('name');
  final adrIdx   = header.indexOf('address');

  final batch = db.batch();

  for (var i = 1; i < rows.length; i++) {
    final r = rows[i];
    final phone = _cellStr(r, phoneIdx);
    if (phone.isEmpty) { skip++; continue; }
    final name  = _cellStr(r, nameIdx);
    final addr  = _cellStr(r, adrIdx);

    final exists = await db.query('customers', where: 'phone = ?', whereArgs: [phone], limit: 1);
    if (exists.isEmpty) {
      batch.insert('customers', {'phone': phone, 'name': name, 'address': addr});
      ins++;
    } else {
      batch.update('customers', {'name': name, 'address': addr}, where: 'phone = ?', whereArgs: [phone]);
      upd++;
    }
  }

  await batch.commit(noResult: true);
  return ImportReport(ins, upd, skip, const []);
}

Future<ImportReport> importSuppliersXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final ex = Excel.decodeBytes(bytes);

  final rows = _readSheet(ex, 'suppliers');
  if (rows.isEmpty) return const ImportReport(0, 0, 0, ['Hoja "suppliers" vacía o no existe']);

  final header = rows.first.map((c) => c?.toString().trim().toLowerCase()).toList();
  final expect = ['phone','name','address'];
  for (final h in expect) {
    if (!header.contains(h)) {
      return ImportReport(0, 0, 0, ['Falta la columna "$h" en suppliers']);
    }
  }

  int ins = 0, upd = 0, skip = 0;
  final phoneIdx = header.indexOf('phone');
  final nameIdx  = header.indexOf('name');
  final adrIdx   = header.indexOf('address');

  final batch = db.batch();

  for (var i = 1; i < rows.length; i++) {
    final r = rows[i];
    final phone = _cellStr(r, phoneIdx);
    if (phone.isEmpty) { skip++; continue; }
    final name  = _cellStr(r, nameIdx);
    final addr  = _cellStr(r, adrIdx);

    final exists = await db.query('suppliers', where: 'phone = ?', whereArgs: [phone], limit: 1);
    if (exists.isEmpty) {
      batch.insert('suppliers', {'phone': phone, 'name': name, 'address': addr});
      ins++;
    } else {
      batch.update('suppliers', {'name': name, 'address': addr}, where: 'phone = ?', whereArgs: [phone]);
      upd++;
    }
  }

  await batch.commit(noResult: true);
  return ImportReport(ins, upd, skip, const []);
}

Future<ImportReport> importSalesXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final ex = Excel.decodeBytes(bytes);

  final salesRows = _readSheet(ex, 'sales');
  final itemsRows = _readSheet(ex, 'sale_items');
  if (salesRows.isEmpty || itemsRows.isEmpty) {
    return const ImportReport(0, 0, 0, ['Hojas "sales" o "sale_items" faltantes']);
  }

  final hs = salesRows.first.map((c) => c?.toString().trim().toLowerCase()).toList();
  for (final h in ['id','customer_phone','payment_method','place','shipping_cost','discount','date']) {
    if (!hs.contains(h)) return ImportReport(0, 0, 0, ['Falta "$h" en sales']);
  }
  final hi = itemsRows.first.map((c) => c?.toString().trim().toLowerCase()).toList();
  for (final h in ['sale_id','product_sku','quantity','unit_price']) {
    if (!hi.contains(h)) return ImportReport(0, 0, 0, ['Falta "$h" en sale_items']);
  }

  final s_id     = hs.indexOf('id');
  final s_phone  = hs.indexOf('customer_phone');
  final s_pay    = hs.indexOf('payment_method');
  final s_place  = hs.indexOf('place');
  final s_ship   = hs.indexOf('shipping_cost');
  final s_disc   = hs.indexOf('discount');
  final s_date   = hs.indexOf('date');

  final i_sid    = hi.indexOf('sale_id');
  final i_sku    = hi.indexOf('product_sku');
  final i_qty    = hi.indexOf('quantity');
  final i_unit   = hi.indexOf('unit_price');

  int ins = 0, upd = 0, skip = 0;
  final errors = <String>[];

  // Construir mapa sale_id -> items
  final itemsMap = <int, List<List<Data?>>>{};
  for (var i = 1; i < itemsRows.length; i++) {
    final r = itemsRows[i];
    final sid = _cellInt(r, i_sid);
    itemsMap.putIfAbsent(sid, () => []).add(r);
  }

  await db.transaction((txn) async {
    for (var i = 1; i < salesRows.length; i++) {
      final r = salesRows[i];
      final id = _cellInt(r, s_id);
      final phone = _cellStr(r, s_phone);
      final pay = _cellStr(r, s_pay);
      final place = _cellStr(r, s_place);
      final ship = _cellNum(r, s_ship);
      final disc = _cellNum(r, s_disc);
      final date = _cellStr(r, s_date);

      if (id == 0 || phone.isEmpty) { skip++; continue; }

      try {
        // insert venta
        final saleId = await txn.insert('sales', {
          'customer_phone': phone,
          'payment_method': pay.isEmpty ? 'efectivo' : pay,
          'place': place.isEmpty ? null : place,
          'shipping_cost': ship,
          'discount': disc,
          'date': date.isEmpty ? DateTime.now().toIso8601String() : date,
        });

        // items
        final its = itemsMap[id] ?? const [];
        for (final it in its) {
          final sku = _cellStr(it, i_sku);
          if (sku.isEmpty) continue;
          final qty = _cellInt(it, i_qty);
          final unit = _cellNum(it, i_unit);

          final prod = await txn.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
          if (prod.isEmpty) {
            errors.add('Venta $id: SKU "$sku" no existe, item omitido');
            continue;
          }
          final pid = prod.first['id'] as int;

          await txn.insert('sale_items', {
            'sale_id': saleId,
            'product_id': pid,
            'quantity': qty,
            'unit_price': unit,
          });

          await txn.rawUpdate('UPDATE products SET stock = MAX(stock - ?, 0) WHERE id = ?', [qty, pid]);
        }
        ins++;
      } catch (e) {
        errors.add('Venta $id: $e');
        skip++;
      }
    }
  });

  return ImportReport(ins, upd, skip, errors);
}

Future<ImportReport> importPurchasesXlsx(Uint8List bytes) async {
  final db = await DatabaseHelper.instance.db;
  final ex = Excel.decodeBytes(bytes);

  final pRows = _readSheet(ex, 'purchases');
  final iRows = _readSheet(ex, 'purchase_items');
  if (pRows.isEmpty || iRows.isEmpty) {
    return const ImportReport(0, 0, 0, ['Hojas "purchases" o "purchase_items" faltantes']);
  }

  final hp = pRows.first.map((c) => c?.toString().trim().toLowerCase()).toList();
  for (final h in ['id','folio','supplier_id','date']) {
    if (!hp.contains(h)) return ImportReport(0, 0, 0, ['Falta "$h" en purchases']);
  }
  final hi = iRows.first.map((c) => c?.toString().trim().toLowerCase()).toList();
  for (final h in ['purchase_id','product_sku','quantity','unit_cost']) {
    if (!hi.contains(h)) return ImportReport(0, 0, 0, ['Falta "$h" en purchase_items']);
  }

  final p_id   = hp.indexOf('id');
  final p_fol  = hp.indexOf('folio');
  final p_sup  = hp.indexOf('supplier_id');
  final p_date = hp.indexOf('date');

  final i_pid  = hi.indexOf('purchase_id');
  final i_sku  = hi.indexOf('product_sku');
  final i_qty  = hi.indexOf('quantity');
  final i_cost = hi.indexOf('unit_cost');

  int ins = 0, upd = 0, skip = 0;
  final errors = <String>[];

  final itemsMap = <int, List<List<Data?>>>{};
  for (var i = 1; i < iRows.length; i++) {
    final r = iRows[i];
    final pid = _cellInt(r, i_pid);
    itemsMap.putIfAbsent(pid, () => []).add(r);
  }

  await db.transaction((txn) async {
    for (var i = 1; i < pRows.length; i++) {
      final r = pRows[i];
      final id = _cellInt(r, p_id);
      final folio = _cellStr(r, p_fol);
      final supplier = _cellStr(r, p_sup);
      final date = _cellStr(r, p_date);

      if (id == 0 || supplier.isEmpty) { skip++; continue; }

      try {
        final purchaseId = await txn.insert('purchases', {
          'folio': folio.isEmpty ? null : folio,
          'supplier_phone': supplier,
          'date': date.isEmpty ? DateTime.now().toIso8601String() : date,
        });

        final its = itemsMap[id] ?? const [];
        for (final it in its) {
          final sku = _cellStr(it, i_sku);
          if (sku.isEmpty) continue;
          final qty = _cellInt(it, i_qty);
          final cost = _cellNum(it, i_cost);

          final prod = await txn.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
          if (prod.isEmpty) {
            errors.add('Compra $id: SKU "$sku" no existe, item omitido');
            continue;
          }
          final pid = prod.first['id'] as int;

          await txn.insert('purchase_items', {
            'purchase_id': purchaseId,
            'product_id': pid,
            'quantity': qty,
            'unit_cost': cost,
          });

          await txn.rawUpdate('UPDATE products SET stock = stock + ?, last_purchase_price = ? WHERE id = ?', [qty, cost, pid]);
        }
        ins++;
      } catch (e) {
        errors.add('Compra $id: $e');
        skip++;
      }
    }
  });

  return ImportReport(ins, upd, skip, errors);
}

// ---------------------------------------------------------------------
// SELECTOR DE ARCHIVO PARA IMPORTAR (UI helpers)
// ---------------------------------------------------------------------

Future<Uint8List?> pickXlsxBytes() async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    withData: true,
  );
  if (res == null || res.files.isEmpty) return null;
  return res.files.single.bytes;
}