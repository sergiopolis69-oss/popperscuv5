import 'dart:typed_data';
import 'package:flutter/painting.dart' show TextSpan;
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import '../data/database.dart' as appdb;

/// Reporte estándar de importación
class ImportReport {
  final int inserted;
  final int updated;
  final int skipped;
  final List<String> errors;
  const ImportReport({
    this.inserted = 0,
    this.updated = 0,
    this.skipped = 0,
    this.errors = const [],
  });
  ImportReport copyWith({
    int? inserted,
    int? updated,
    int? skipped,
    List<String>? errors,
  }) =>
      ImportReport(
        inserted: inserted ?? this.inserted,
        updated: updated ?? this.updated,
        skipped: skipped ?? this.skipped,
        errors: errors ?? this.errors,
      );
  @override
  String toString() =>
      'Insertados: $inserted · Actualizados: $updated · Omitidos: $skipped${errors.isEmpty ? "" : " · Errores: ${errors.length}"}';
}

/// Helpers CellValue (excel ^4.0.6)
CellValue _tx(String s) => TextCellValue(value: TextSpan(text: s));
CellValue _dbl(num n) => DoubleCellValue(value: n.toDouble());
CellValue _int(int n) => IntCellValue(value: n);

/// Lectura segura desde CellValue
String _readStr(CellValue? v) {
  if (v == null) return '';
  if (v is TextCellValue) {
    final txt = v.value;
    if (txt is TextSpan) return txt.toPlainText();
    return txt.toString();
  }
  if (v is DoubleCellValue) return v.value.toString();
  if (v is IntCellValue) return v.value.toString();
  if (v is BoolCellValue) return v.value ? 'true' : 'false';
  if (v is DateCellValue) {
    // Evito campos de hora/segundo para no depender de firma exacta
    final y = v.year ?? 0, m = v.month ?? 0, d = v.day ?? 0;
    if (y == 0) return '';
    String two(int x) => x.toString().padLeft(2, '0');
    return '${y.toString().padLeft(4, '0')}-${two(m)}-${two(d)}';
  }
  return v.toString();
}

double _readDouble(CellValue? v) {
  if (v == null) return 0.0;
  if (v is DoubleCellValue) return v.value;
  if (v is IntCellValue) return v.value.toDouble();
  if (v is TextCellValue) {
    final s = _readStr(v).replaceAll(',', '.');
    return double.tryParse(s) ?? 0.0;
  }
  return double.tryParse(_readStr(v)) ?? 0.0;
}

int _readInt(CellValue? v) {
  if (v == null) return 0;
  if (v is IntCellValue) return v.value;
  if (v is DoubleCellValue) return v.value.round();
  return int.tryParse(_readStr(v)) ?? 0;
}

/// Util para obtener hoja (crea si no existe)
Sheet _sheet(Excel ex, String name) => ex[name];

/// --------------------------------------------------------------------------------
/// EXPORTAR
/// --------------------------------------------------------------------------------

Future<Uint8List> rebuildProductsXlsxBytes() async {
  final db = await appdb.getDb();
  final rows = await db.rawQuery('''
    SELECT sku, name, IFNULL(category,'') AS category,
           IFNULL(default_sale_price,0) AS default_sale_price,
           IFNULL(last_purchase_price,0) AS last_purchase_price,
           IFNULL(stock,0) AS stock
    FROM products
    ORDER BY name
  ''');

  final ex = Excel.createExcel();
  final sh = _sheet(ex, 'products');

  sh.appendRow(<CellValue>[
    _tx('sku'),
    _tx('name'),
    _tx('category'),
    _tx('default_sale_price'),
    _tx('last_purchase_price'),
    _tx('stock'),
  ]);

  for (final r in rows) {
    sh.appendRow(<CellValue>[
      _tx((r['sku'] ?? '').toString()),
      _tx((r['name'] ?? '').toString()),
      _tx((r['category'] ?? '').toString()),
      _dbl((r['default_sale_price'] as num?)?.toDouble() ?? 0.0),
      _dbl((r['last_purchase_price'] as num?)?.toDouble() ?? 0.0),
      _int((r['stock'] as num?)?.toInt() ?? 0),
    ]);
  }
  final bytes = ex.encode()!;
  return Uint8List.fromList(bytes);
}

Future<Uint8List> rebuildClientsXlsxBytes() async {
  final db = await appdb.getDb();
  final rows =
      await db.rawQuery('SELECT phone, IFNULL(name,"") name, IFNULL(address,"") address FROM customers ORDER BY name');

  final ex = Excel.createExcel();
  final sh = _sheet(ex, 'customers');

  sh.appendRow(<CellValue>[_tx('phone'), _tx('name'), _tx('address')]);

  for (final r in rows) {
    sh.appendRow(<CellValue>[
      _tx((r['phone'] ?? '').toString()),
      _tx((r['name'] ?? '').toString()),
      _tx((r['address'] ?? '').toString()),
    ]);
  }
  return Uint8List.fromList(ex.encode()!);
}

Future<Uint8List> rebuildSuppliersXlsxBytes() async {
  final db = await appdb.getDb();
  final rows =
      await db.rawQuery('SELECT IFNULL(phone,"") phone, IFNULL(name,"") name, IFNULL(address,"") address FROM suppliers ORDER BY name');

  final ex = Excel.createExcel();
  final sh = _sheet(ex, 'suppliers');

  sh.appendRow(<CellValue>[_tx('phone'), _tx('name'), _tx('address')]);

  for (final r in rows) {
    sh.appendRow(<CellValue>[
      _tx((r['phone'] ?? '').toString()),
      _tx((r['name'] ?? '').toString()),
      _tx((r['address'] ?? '').toString()),
    ]);
  }
  return Uint8List.fromList(ex.encode()!);
}

Future<Uint8List> rebuildSalesXlsxBytes() async {
  final db = await appdb.getDb();

  final sales = await db.rawQuery('''
    SELECT id, IFNULL(customer_phone,"") customer_phone, IFNULL(payment_method,"") payment_method,
           IFNULL(place,"") place, IFNULL(shipping_cost,0) shipping_cost,
           IFNULL(discount,0) discount, IFNULL(date,"") date
    FROM sales
    ORDER BY date DESC, id DESC
  ''');

  final items = await db.rawQuery('''
    SELECT si.sale_id, p.sku AS product_sku, si.quantity, si.unit_price
    FROM sale_items si
    JOIN products p ON p.id = si.product_id
    ORDER BY si.sale_id
  ''');

  final ex = Excel.createExcel();
  final sh = _sheet(ex, 'sales');
  sh.appendRow(<CellValue>[
    _tx('id'),
    _tx('customer_phone'),
    _tx('payment_method'),
    _tx('place'),
    _tx('shipping_cost'),
    _tx('discount'),
    _tx('date'),
  ]);
  for (final r in sales) {
    sh.appendRow(<CellValue>[
      _int((r['id'] as num?)?.toInt() ?? 0),
      _tx((r['customer_phone'] ?? '').toString()),
      _tx((r['payment_method'] ?? '').toString()),
      _tx((r['place'] ?? '').toString()),
      _dbl((r['shipping_cost'] as num?)?.toDouble() ?? 0.0),
      _dbl((r['discount'] as num?)?.toDouble() ?? 0.0),
      _tx((r['date'] ?? '').toString()),
    ]);
  }

  final si = _sheet(ex, 'sale_items');
  si.appendRow(<CellValue>[_tx('sale_id'), _tx('product_sku'), _tx('quantity'), _tx('unit_price')]);
  for (final r in items) {
    si.appendRow(<CellValue>[
      _int((r['sale_id'] as num?)?.toInt() ?? 0),
      _tx((r['product_sku'] ?? '').toString()),
      _int((r['quantity'] as num?)?.toInt() ?? 0),
      _dbl((r['unit_price'] as num?)?.toDouble() ?? 0.0),
    ]);
  }

  return Uint8List.fromList(ex.encode()!);
}

Future<Uint8List> rebuildPurchasesXlsxBytes() async {
  final db = await appdb.getDb();

  final ph = await db.rawQuery('''
    SELECT id, IFNULL(folio,"") folio, 
           (SELECT IFNULL(phone,"") FROM suppliers s WHERE s.id = p.supplier_id) AS supplier_phone,
           IFNULL(date,"") date
    FROM purchases p
    ORDER BY date DESC, id DESC
  ''');

  final items = await db.rawQuery('''
    SELECT pi.purchase_id, p.sku AS product_sku, pi.quantity, pi.unit_cost
    FROM purchase_items pi
    JOIN products p ON p.id = pi.product_id
    ORDER BY pi.purchase_id
  ''');

  final ex = Excel.createExcel();
  final sh = _sheet(ex, 'purchases');
  sh.appendRow(<CellValue>[_tx('id'), _tx('folio'), _tx('supplier_phone'), _tx('date')]);
  for (final r in ph) {
    sh.appendRow(<CellValue>[
      _int((r['id'] as num?)?.toInt() ?? 0),
      _tx((r['folio'] ?? '').toString()),
      _tx((r['supplier_phone'] ?? '').toString()),
      _tx((r['date'] ?? '').toString()),
    ]);
  }

  final si = _sheet(ex, 'purchase_items');
  si.appendRow(<CellValue>[_tx('purchase_id'), _tx('product_sku'), _tx('quantity'), _tx('unit_cost')]);
  for (final r in items) {
    si.appendRow(<CellValue>[
      _int((r['purchase_id'] as num?)?.toInt() ?? 0),
      _tx((r['product_sku'] ?? '').toString()),
      _int((r['quantity'] as num?)?.toInt() ?? 0),
      _dbl((r['unit_cost'] as num?)?.toDouble() ?? 0.0),
    ]);
  }

  return Uint8List.fromList(ex.encode()!);
}

/// --------------------------------------------------------------------------------
/// IMPORTAR
/// --------------------------------------------------------------------------------

Future<ImportReport> importProductsXlsx(Uint8List bytes) async {
  final db = await appdb.getDb();
  final ex = Excel.decodeBytes(bytes);
  final sh = ex.sheets['products'];
  if (sh == null) {
    return const ImportReport(skipped: 0, errors: ['Hoja "products" no encontrada']);
  }

  int ins = 0, upd = 0, sk = 0;
  final errs = <String>[];

  // Map: sku -> id (si existe)
  Future<int?> _findId(String sku) async {
    final r = await db.rawQuery('SELECT id FROM products WHERE sku = ?', [sku]);
    if (r.isEmpty) return null;
    return (r.first['id'] as num).toInt();
  }

  // Procesa filas (salta encabezado)
  final rows = sh.rows;
  for (var i = 1; i < rows.length; i++) {
    final row = rows[i];
    final sku = _readStr(row.elementAtOrNull(0)?.value).trim();
    final name = _readStr(row.elementAtOrNull(1)?.value).trim();
    final category = _readStr(row.elementAtOrNull(2)?.value).trim();
    final dsp = _readDouble(row.elementAtOrNull(3)?.value);
    final lpp = _readDouble(row.elementAtOrNull(4)?.value);
    final stock = _readInt(row.elementAtOrNull(5)?.value);

    if (sku.isEmpty) {
      sk++;
      errs.add('Fila ${i + 1}: SKU vacío, omitido.');
      continue;
    }

    final existingId = await _findId(sku);
    if (existingId == null) {
      await db.insert('products', {
        'sku': sku,
        'name': name.isEmpty ? sku : name,
        'category': category,
        'default_sale_price': dsp,
        'last_purchase_price': lpp,
        'stock': stock,
      });
      ins++;
    } else {
      await db.update(
        'products',
        {
          'name': name.isEmpty ? sku : name,
          'category': category,
          'default_sale_price': dsp,
          'last_purchase_price': lpp,
          'stock': stock,
        },
        where: 'id = ?',
        whereArgs: [existingId],
      );
      upd++;
    }
  }

  return ImportReport(inserted: ins, updated: upd, skipped: sk, errors: errs);
}

Future<ImportReport> importClientsXlsx(Uint8List bytes) async {
  final db = await appdb.getDb();
  final ex = Excel.decodeBytes(bytes);
  final sh = ex.sheets['customers'];
  if (sh == null) {
    return const ImportReport(errors: ['Hoja "customers" no encontrada']);
  }

  int ins = 0, upd = 0, sk = 0;
  final errs = <String>[];

  final rows = sh.rows;
  for (var i = 1; i < rows.length; i++) {
    final row = rows[i];
    final phone = _readStr(row.elementAtOrNull(0)?.value).trim();
    final name = _readStr(row.elementAtOrNull(1)?.value).trim();
    final address = _readStr(row.elementAtOrNull(2)?.value).trim();

    if (phone.isEmpty) {
      sk++;
      errs.add('Fila ${i + 1}: phone vacío, omitido.');
      continue;
    }

    final exists =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM customers WHERE phone = ?', [phone])) ??
            0;

    if (exists == 0) {
      await db.insert('customers', {'phone': phone, 'name': name, 'address': address});
      ins++;
    } else {
      await db.update('customers', {'name': name, 'address': address},
          where: 'phone = ?', whereArgs: [phone]);
      upd++;
    }
  }
  return ImportReport(inserted: ins, updated: upd, skipped: sk, errors: errs);
}

Future<ImportReport> importSuppliersXlsx(Uint8List bytes) async {
  final db = await appdb.getDb();
  final ex = Excel.decodeBytes(bytes);
  final sh = ex.sheets['suppliers'];
  if (sh == null) {
    return const ImportReport(errors: ['Hoja "suppliers" no encontrada']);
  }

  int ins = 0, upd = 0, sk = 0;
  final errs = <String>[];

  Future<int?> _findIdByPhone(String phone) async {
    final r = await db.rawQuery('SELECT id FROM suppliers WHERE phone = ?', [phone]);
    if (r.isEmpty) return null;
    return (r.first['id'] as num).toInt();
  }

  final rows = sh.rows;
  for (var i = 1; i < rows.length; i++) {
    final row = rows[i];
    final phone = _readStr(row.elementAtOrNull(0)?.value).trim();
    final name = _readStr(row.elementAtOrNull(1)?.value).trim();
    final address = _readStr(row.elementAtOrNull(2)?.value).trim();

    if (phone.isEmpty) {
      sk++;
      errs.add('Fila ${i + 1}: phone vacío, omitido.');
      continue;
    }

    final id = await _findIdByPhone(phone);
    if (id == null) {
      await db.insert('suppliers', {'phone': phone, 'name': name, 'address': address});
      ins++;
    } else {
      await db.update('suppliers', {'name': name, 'address': address}, where: 'id = ?', whereArgs: [id]);
      upd++;
    }
  }
  return ImportReport(inserted: ins, updated: upd, skipped: sk, errors: errs);
}

Future<ImportReport> importSalesXlsx(Uint8List bytes) async {
  final db = await appdb.getDb();
  final ex = Excel.decodeBytes(bytes);
  final sh = ex.sheets['sales'];
  final si = ex.sheets['sale_items'];
  if (sh == null || si == null) {
    return const ImportReport(errors: ['Se requieren hojas "sales" y "sale_items"']);
  }

  int ins = 0, upd = 0, sk = 0;
  final errs = <String>[];

  // Mapea id externos => id reales
  final idMap = <int, int>{};

  await db.transaction((txn) async {
    // Ventas
    for (var i = 1; i < sh.rows.length; i++) {
      final row = sh.rows[i];
      final extId = _readInt(row.elementAtOrNull(0)?.value);
      final phone = _readStr(row.elementAtOrNull(1)?.value).trim();
      final pm = _readStr(row.elementAtOrNull(2)?.value).trim();
      final place = _readStr(row.elementAtOrNull(3)?.value).trim();
      final ship = _readDouble(row.elementAtOrNull(4)?.value);
      final disc = _readDouble(row.elementAtOrNull(5)?.value);
      final date = _readStr(row.elementAtOrNull(6)?.value).trim();

      if (extId <= 0) {
        sk++;
        errs.add('sale fila ${i + 1}: id inválido');
        continue;
      }

      final exist =
          Sqflite.firstIntValue(await txn.rawQuery('SELECT COUNT(*) FROM sales WHERE id=?', [extId])) ??
              0;

      if (exist == 0) {
        await txn.insert('sales', {
          'id': extId,
          'customer_phone': phone,
          'payment_method': pm,
          'place': place,
          'shipping_cost': ship,
          'discount': disc,
          'date': date,
        });
        idMap[extId] = extId;
        ins++;
      } else {
        await txn.update(
            'sales',
            {
              'customer_phone': phone,
              'payment_method': pm,
              'place': place,
              'shipping_cost': ship,
              'discount': disc,
              'date': date,
            },
            where: 'id=?',
            whereArgs: [extId]);
        idMap[extId] = extId;
        upd++;
      }
    }

    // Partidas
    // Limpia items existentes (opcional) para cada venta importada
    for (final sid in idMap.values) {
      await txn.delete('sale_items', where: 'sale_id=?', whereArgs: [sid]);
    }

    for (var i = 1; i < si.rows.length; i++) {
      final row = si.rows[i];
      final saleIdExt = _readInt(row.elementAtOrNull(0)?.value);
      final sku = _readStr(row.elementAtOrNull(1)?.value).trim();
      final qty = _readInt(row.elementAtOrNull(2)?.value);
      final unit = _readDouble(row.elementAtOrNull(3)?.value);
      if (saleIdExt <= 0 || sku.isEmpty || qty <= 0) {
        sk++;
        errs.add('sale_items fila ${i + 1}: datos inválidos');
        continue;
      }
      final saleId = idMap[saleIdExt];
      if (saleId == null) {
        sk++;
        errs.add('sale_items fila ${i + 1}: sale_id $saleIdExt no existe en importación');
        continue;
      }
      final prod = await txn.rawQuery('SELECT id FROM products WHERE sku = ?', [sku]);
      if (prod.isEmpty) {
        sk++;
        errs.add('sale_items fila ${i + 1}: producto SKU "$sku" no existe');
        continue;
      }
      final pid = (prod.first['id'] as num).toInt();
      await txn.insert('sale_items', {
        'sale_id': saleId,
        'product_id': pid,
        'quantity': qty,
        'unit_price': unit,
      });
    }
  });

  return ImportReport(inserted: ins, updated: upd, skipped: sk, errors: errs);
}

Future<ImportReport> importPurchasesXlsx(Uint8List bytes) async {
  final db = await appdb.getDb();
  final ex = Excel.decodeBytes(bytes);
  final sh = ex.sheets['purchases'];
  final si = ex.sheets['purchase_items'];
  if (sh == null || si == null) {
    return const ImportReport(errors: ['Se requieren hojas "purchases" y "purchase_items"']);
  }

  int ins = 0, upd = 0, sk = 0;
  final errs = <String>[];
  final idMap = <int, int>{};

  await db.transaction((txn) async {
    // Cabezera compras
    for (var i = 1; i < sh.rows.length; i++) {
      final row = sh.rows[i];
      final extId = _readInt(row.elementAtOrNull(0)?.value);
      final folio = _readStr(row.elementAtOrNull(1)?.value).trim();
      final supplierPhone = _readStr(row.elementAtOrNull(2)?.value).trim();
      final date = _readStr(row.elementAtOrNull(3)?.value).trim();

      if (extId <= 0) {
        sk++;
        errs.add('purchase fila ${i + 1}: id inválido');
        continue;
      }

      int? supplierId;
      if (supplierPhone.isNotEmpty) {
        final r = await txn.rawQuery('SELECT id FROM suppliers WHERE phone=?', [supplierPhone]);
        supplierId = r.isEmpty ? null : (r.first['id'] as num).toInt();
      }

      final exist = Sqflite.firstIntValue(
              await txn.rawQuery('SELECT COUNT(*) FROM purchases WHERE id=?', [extId])) ??
          0;

      if (exist == 0) {
        await txn.insert('purchases', {
          'id': extId,
          'folio': folio,
          'supplier_id': supplierId,
          'date': date,
        });
        idMap[extId] = extId;
        ins++;
      } else {
        await txn.update(
            'purchases',
            {
              'folio': folio,
              'supplier_id': supplierId,
              'date': date,
            },
            where: 'id=?',
            whereArgs: [extId]);
        idMap[extId] = extId;
        upd++;
      }
    }

    // Limpiar items de las compras importadas
    for (final pid in idMap.values) {
      await txn.delete('purchase_items', where: 'purchase_id=?', whereArgs: [pid]);
    }

    // Partidas de compra
    for (var i = 1; i < si.rows.length; i++) {
      final row = si.rows[i];
      final purchaseIdExt = _readInt(row.elementAtOrNull(0)?.value);
      final sku = _readStr(row.elementAtOrNull(1)?.value).trim();
      final qty = _readInt(row.elementAtOrNull(2)?.value);
      final unitCost = _readDouble(row.elementAtOrNull(3)?.value);

      if (purchaseIdExt <= 0 || sku.isEmpty || qty <= 0) {
        sk++;
        errs.add('purchase_items fila ${i + 1}: datos inválidos');
        continue;
      }

      final purchaseId = idMap[purchaseIdExt];
      if (purchaseId == null) {
        sk++;
        errs.add('purchase_items fila ${i + 1}: purchase_id $purchaseIdExt no existe en importación');
        continue;
      }

      final prod = await txn.rawQuery('SELECT id FROM products WHERE sku = ?', [sku]);
      if (prod.isEmpty) {
        sk++;
        errs.add('purchase_items fila ${i + 1}: producto SKU "$sku" no existe');
        continue;
      }
      final productId = (prod.first['id'] as num).toInt();

      await txn.insert('purchase_items', {
        'purchase_id': purchaseId,
        'product_id': productId,
        'quantity': qty,
        'unit_cost': unitCost,
      });

      // Actualiza últimos costos del producto y stock
      await txn.update(
        'products',
        {
          'last_purchase_price': unitCost,
          'last_purchase_date': DateTime.now().toIso8601String(),
          'stock': Sqflite.firstIntValue(await txn.rawQuery(
                  'SELECT IFNULL(stock,0) FROM products WHERE id=?', [productId]))! +
              qty,
        },
        where: 'id=?',
        whereArgs: [productId],
      );
    }
  });

  return ImportReport(inserted: ins, updated: upd, skipped: sk, errors: errs);
}

/// --------------------------------------------------------------------------------
/// FILE PICKER (.xlsx)
/// --------------------------------------------------------------------------------
Future<Uint8List> pickXlsxBytes() async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['xlsx'],
    withData: true,
  );
  if (res == null || res.files.isEmpty || res.files.single.bytes == null) {
    throw Exception('No seleccionaste ningún archivo .xlsx');
  }
  return res.files.single.bytes!;
}