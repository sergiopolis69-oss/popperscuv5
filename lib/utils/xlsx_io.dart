// lib/utils/xlsx_io.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart' as ex;
import 'package:sqflite/sqflite.dart' as sqf;

import '../data/database.dart' as appdb;

/// ---------- Modelo de reporte de importación ----------
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
  }) {
    return ImportReport(
      inserted: inserted ?? this.inserted,
      updated: updated ?? this.updated,
      skipped: skipped ?? this.skipped,
      errors: errors ?? this.errors,
    );
  }
}

/// ---------- Utilidades internas ----------

ex.Sheet _sheet(ex.Excel book, String name) {
  // crea u obtiene la hoja
  if (!book.sheets.containsKey(name)) {
    book.addSheet(name);
  }
  return book.sheets[name]!;
}

// Atajos de celda (evita conflictos de TextSpan de Flutter):
ex.CellValue _tx(String s) => ex.TextCellValue(s);
ex.CellValue _dbl(num n) => ex.DoubleCellValue(n.toDouble());
ex.CellValue _int(int n) => ex.IntCellValue(n);

String _cellAsString(ex.CellValue? v) {
  if (v == null) return '';
  if (v is ex.TextCellValue) return v.value.text;
  return v.value.toString();
}

double _cellAsDouble(ex.CellValue? v) {
  if (v == null) return 0.0;
  if (v is ex.DoubleCellValue) return v.value;
  if (v is ex.IntCellValue) return v.value.toDouble();
  if (v is ex.TextCellValue) {
    final s = v.value.text.replaceAll(',', '.');
    return double.tryParse(s) ?? 0.0;
  }
  return double.tryParse(v.value.toString()) ?? 0.0;
}

int _cellAsInt(ex.CellValue? v) {
  if (v == null) return 0;
  if (v is ex.IntCellValue) return v.value;
  if (v is ex.DoubleCellValue) return v.value.toInt();
  if (v is ex.TextCellValue) return int.tryParse(v.value.text) ?? 0;
  return int.tryParse(v.value.toString()) ?? 0;
}

DateTime? _cellAsDate(ex.CellValue? v) {
  if (v == null) return null;
  if (v is ex.DateCellValue) {
    return DateTime(v.year, v.month, v.day);
  }
  if (v is ex.TextCellValue) {
    final s = v.value.text.trim();
    if (s.isEmpty) return null;
    // intentar parse ISO / yyyy-MM-dd
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// Devuelve el primer entero de una consulta COUNT(*)
int? _firstInt(List<Map<String, Object?>> rows) {
  if (rows.isEmpty) return null;
  final v = rows.first.values.first;
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

/// Guarda bytes XLSX en documentos de la app y devuelve la ruta.
Future<String> saveXlsxToAppDocs(String base, Uint8List bytes) async {
  final dir = await getApplicationDocumentsDirectory();
  final ts = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '')
      .replaceAll('.', '')
      .replaceAll('-', '')
      .replaceAll('T', '_');
  final f = File('${dir.path}/$base-$ts.xlsx');
  await f.writeAsBytes(bytes, flush: true);
  return f.path;
}

/// Abre un picker y devuelve los bytes del xlsx
Future<Uint8List> pickXlsxBytes() async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    withData: true,
  );
  if (res == null || res.files.isEmpty) {
    throw 'No se seleccionó archivo';
  }
  final f = res.files.first;
  if (f.bytes != null) return f.bytes!;
  if (f.path != null) return await File(f.path!).readAsBytes();
  throw 'Archivo inválido';
}

/// ---------- EXPORTACIONES ----------

Future<Uint8List> rebuildProductsXlsxBytes() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final rows = await db.rawQuery('''
    SELECT sku, name, COALESCE(category,'') AS category,
           COALESCE(default_sale_price,0) AS default_sale_price,
           COALESCE(last_purchase_price,0) AS last_purchase_price,
           COALESCE(stock,0) AS stock
    FROM products
    ORDER BY name
  ''');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'products');
  sh.appendRow(<ex.CellValue>[
    _tx('sku'),
    _tx('name'),
    _tx('category'),
    _tx('default_sale_price'),
    _tx('last_purchase_price'),
    _tx('stock'),
  ]);

  for (final r in rows) {
    sh.appendRow(<ex.CellValue>[
      _tx((r['sku'] ?? '').toString()),
      _tx((r['name'] ?? '').toString()),
      _tx((r['category'] ?? '').toString()),
      _dbl((r['default_sale_price'] as num?)?.toDouble() ?? 0),
      _dbl((r['last_purchase_price'] as num?)?.toDouble() ?? 0),
      _int((r['stock'] as num?)?.toInt() ?? 0),
    ]);
  }
  return Uint8List.fromList(book.encode()!);
}

Future<Uint8List> rebuildClientsXlsxBytes() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final rows = await db.rawQuery('SELECT phone,name,address FROM customers ORDER BY name');
  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'customers');
  sh.appendRow(<ex.CellValue>[_tx('phone'), _tx('name'), _tx('address')]);
  for (final r in rows) {
    sh.appendRow(<ex.CellValue>[
      _tx((r['phone'] ?? '').toString()),
      _tx((r['name'] ?? '').toString()),
      _tx((r['address'] ?? '').toString()),
    ]);
  }
  return Uint8List.fromList(book.encode()!);
}

Future<Uint8List> rebuildSuppliersXlsxBytes() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final rows = await db.rawQuery('SELECT phone,name,address FROM suppliers ORDER BY name');
  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'suppliers');
  sh.appendRow(<ex.CellValue>[_tx('phone'), _tx('name'), _tx('address')]);
  for (final r in rows) {
    sh.appendRow(<ex.CellValue>[
      _tx((r['phone'] ?? '').toString()),
      _tx((r['name'] ?? '').toString()),
      _tx((r['address'] ?? '').toString()),
    ]);
  }
  return Uint8List.fromList(book.encode()!);
}

Future<Uint8List> rebuildSalesXlsxBytes() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final sales = await db.rawQuery('''
    SELECT id, customer_phone, payment_method, place,
           COALESCE(shipping_cost,0) AS shipping_cost,
           COALESCE(discount,0) AS discount,
           COALESCE(date,'') AS date
    FROM sales
    ORDER BY id
  ''');

  final items = await db.rawQuery('''
    SELECT sale_id,
           p.sku AS product_sku,
           quantity,
           unit_price
    FROM sale_items si
    JOIN products p ON p.id = si.product_id
    ORDER BY si.sale_id, si.id
  ''');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'sales');
  sh.appendRow(<ex.CellValue>[
    _tx('id'),
    _tx('customer_phone'),
    _tx('payment_method'),
    _tx('place'),
    _tx('shipping_cost'),
    _tx('discount'),
    _tx('date'),
  ]);
  for (final r in sales) {
    sh.appendRow(<ex.CellValue>[
      _int((r['id'] as num).toInt()),
      _tx((r['customer_phone'] ?? '').toString()),
      _tx((r['payment_method'] ?? '').toString()),
      _tx((r['place'] ?? '').toString()),
      _dbl((r['shipping_cost'] as num?)?.toDouble() ?? 0),
      _dbl((r['discount'] as num?)?.toDouble() ?? 0),
      _tx((r['date'] ?? '').toString()),
    ]);
  }

  final shi = _sheet(book, 'sale_items');
  shi.appendRow(<ex.CellValue>[_tx('sale_id'), _tx('product_sku'), _tx('quantity'), _tx('unit_price')]);
  for (final r in items) {
    shi.appendRow(<ex.CellValue>[
      _int((r['sale_id'] as num).toInt()),
      _tx((r['product_sku'] ?? '').toString()),
      _int((r['quantity'] as num).toInt()),
      _dbl((r['unit_price'] as num).toDouble()),
    ]);
  }

  return Uint8List.fromList(book.encode()!);
}

Future<Uint8List> rebuildPurchasesXlsxBytes() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final purchases = await db.rawQuery('''
    SELECT id, COALESCE(folio,'') AS folio,
           (SELECT phone FROM suppliers s WHERE s.id = p.supplier_id) AS supplier_phone,
           COALESCE(date,'') AS date
    FROM purchases p
    ORDER BY id
  ''');
  final items = await db.rawQuery('''
    SELECT purchase_id, p.sku AS product_sku, quantity, unit_cost
    FROM purchase_items pi
    JOIN products p ON p.id = pi.product_id
    ORDER BY pi.purchase_id, pi.id
  ''');

  final book = ex.Excel.createExcel();
  final sh = _sheet(book, 'purchases');
  sh.appendRow(<ex.CellValue>[_tx('id'), _tx('folio'), _tx('supplier_phone'), _tx('date')]);
  for (final r in purchases) {
    sh.appendRow(<ex.CellValue>[
      _int((r['id'] as num).toInt()),
      _tx((r['folio'] ?? '').toString()),
      _tx((r['supplier_phone'] ?? '').toString()),
      _tx((r['date'] ?? '').toString()),
    ]);
  }

  final shi = _sheet(book, 'purchase_items');
  shi.appendRow(<ex.CellValue>[_tx('purchase_id'), _tx('product_sku'), _tx('quantity'), _tx('unit_cost')]);
  for (final r in items) {
    shi.appendRow(<ex.CellValue>[
      _int((r['purchase_id'] as num).toInt()),
      _tx((r['product_sku'] ?? '').toString()),
      _int((r['quantity'] as num).toInt()),
      _dbl((r['unit_cost'] as num).toDouble()),
    ]);
  }

  return Uint8List.fromList(book.encode()!);
}

/// ---------- IMPORTACIONES ----------

Future<ImportReport> importProductsXlsx(Uint8List bytes) async {
  final db = await appdb.DatabaseHelper.instance.db;
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book.sheets['products'];
  if (sh == null) throw 'Hoja "products" no encontrada';

  // encabezados esperados:
  // sku | name | category | default_sale_price | last_purchase_price | stock
  var rep = const ImportReport();
  final errors = <String>[];

  for (var i = 1; i < sh.rows.length; i++) {
    final row = sh.rows[i];
    final sku = _cellAsString(row.elementAtOrNull(0));
    final name = _cellAsString(row.elementAtOrNull(1));
    final category = _cellAsString(row.elementAtOrNull(2));
    final dsp = _cellAsDouble(row.elementAtOrNull(3));
    final lpp = _cellAsDouble(row.elementAtOrNull(4));
    final stock = _cellAsInt(row.elementAtOrNull(5));

    if (sku.isEmpty || name.isEmpty) {
      rep = rep.copyWith(skipped: rep.skipped + 1);
      errors.add('Línea ${i + 1}: sku y name son obligatorios');
      continue;
    }

    try {
      final exist = _firstInt(await db.rawQuery('SELECT id FROM products WHERE sku = ?', [sku]));
      if (exist == null) {
        await db.insert(
          'products',
          {
            'sku': sku,
            'name': name,
            'category': category,
            'default_sale_price': dsp,
            'last_purchase_price': lpp,
            'stock': stock,
          },
          conflictAlgorithm: sqf.ConflictAlgorithm.abort,
        );
        rep = rep.copyWith(inserted: rep.inserted + 1);
      } else {
        await db.update(
          'products',
          {
            'name': name,
            'category': category,
            'default_sale_price': dsp,
            'last_purchase_price': lpp,
            'stock': stock,
          },
          where: 'sku = ?',
          whereArgs: [sku],
          conflictAlgorithm: sqf.ConflictAlgorithm.abort,
        );
        rep = rep.copyWith(updated: rep.updated + 1);
      }
    } catch (e) {
      rep = rep.copyWith(skipped: rep.skipped + 1);
      errors.add('Línea ${i + 1}: $e');
    }
  }
  return rep.copyWith(errors: errors);
}

Future<ImportReport> importClientsXlsx(Uint8List bytes) async {
  final db = await appdb.DatabaseHelper.instance.db;
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book.sheets['customers'];
  if (sh == null) throw 'Hoja "customers" no encontrada';

  var rep = const ImportReport();
  final errors = <String>[];

  for (var i = 1; i < sh.rows.length; i++) {
    final r = sh.rows[i];
    final phone = _cellAsString(r.elementAtOrNull(0));
    final name = _cellAsString(r.elementAtOrNull(1));
    final address = _cellAsString(r.elementAtOrNull(2));
    if (phone.isEmpty) {
      rep = rep.copyWith(skipped: rep.skipped + 1);
      errors.add('Línea ${i + 1}: phone obligatorio');
      continue;
    }
    try {
      final exist = _firstInt(
            await db.rawQuery('SELECT COUNT(*) FROM customers WHERE phone=?', [phone]),
          ) ??
          0;
      if (exist == 0) {
        await db.insert(
          'customers',
          {'phone': phone, 'name': name, 'address': address},
          conflictAlgorithm: sqf.ConflictAlgorithm.replace,
        );
        rep = rep.copyWith(inserted: rep.inserted + 1);
      } else {
        await db.update(
          'customers',
          {'name': name, 'address': address},
          where: 'phone=?',
          whereArgs: [phone],
          conflictAlgorithm: sqf.ConflictAlgorithm.replace,
        );
        rep = rep.copyWith(updated: rep.updated + 1);
      }
    } catch (e) {
      rep = rep.copyWith(skipped: rep.skipped + 1);
      errors.add('Línea ${i + 1}: $e');
    }
  }
  return rep.copyWith(errors: errors);
}

Future<ImportReport> importSuppliersXlsx(Uint8List bytes) async {
  final db = await appdb.DatabaseHelper.instance.db;
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book.sheets['suppliers'];
  if (sh == null) throw 'Hoja "suppliers" no encontrada';

  var rep = const ImportReport();
  final errors = <String>[];

  for (var i = 1; i < sh.rows.length; i++) {
    final r = sh.rows[i];
    final phone = _cellAsString(r.elementAtOrNull(0));
    final name = _cellAsString(r.elementAtOrNull(1));
    final address = _cellAsString(r.elementAtOrNull(2));
    if (phone.isEmpty) {
      rep = rep.copyWith(skipped: rep.skipped + 1);
      errors.add('Línea ${i + 1}: phone obligatorio');
      continue;
    }
    try {
      final exist = _firstInt(await db.rawQuery('SELECT COUNT(*) FROM suppliers WHERE phone=?', [phone])) ?? 0;
      if (exist == 0) {
        await db.insert(
          'suppliers',
          {'phone': phone, 'name': name, 'address': address},
          conflictAlgorithm: sqf.ConflictAlgorithm.replace,
        );
        rep = rep.copyWith(inserted: rep.inserted + 1);
      } else {
        await db.update(
          'suppliers',
          {'name': name, 'address': address},
          where: 'phone=?',
          whereArgs: [phone],
          conflictAlgorithm: sqf.ConflictAlgorithm.replace,
        );
        rep = rep.copyWith(updated: rep.updated + 1);
      }
    } catch (e) {
      rep = rep.copyWith(skipped: rep.skipped + 1);
      errors.add('Línea ${i + 1}: $e');
    }
  }
  return rep.copyWith(errors: errors);
}

Future<ImportReport> importSalesXlsx(Uint8List bytes) async {
  final db = await appdb.DatabaseHelper.instance.db;
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book.sheets['sales'];
  final shi = book.sheets['sale_items'];
  if (sh == null || shi == null) throw 'Hojas "sales" y/o "sale_items" no encontradas';

  var rep = const ImportReport();
  final errors = <String>[];

  // Mapear ventas por ID externo
  // Encabezado: id | customer_phone | payment_method | place | shipping_cost | discount | date
  final tx = await db.transaction((txn) async {
    // primero, insertar/actualizar sales
    for (var i = 1; i < sh.rows.length; i++) {
      final r = sh.rows[i];
      final extId = _cellAsInt(r.elementAtOrNull(0));
      final phone = _cellAsString(r.elementAtOrNull(1));
      final pay = _cellAsString(r.elementAtOrNull(2));
      final place = _cellAsString(r.elementAtOrNull(3));
      final ship = _cellAsDouble(r.elementAtOrNull(4));
      final disc = _cellAsDouble(r.elementAtOrNull(5));
      final date = _cellAsString(r.elementAtOrNull(6));

      try {
        final exist = _firstInt(await txn.rawQuery('SELECT id FROM sales WHERE id=?', [extId]));
        if (exist == null) {
          await txn.insert(
            'sales',
            {
              'id': extId,
              'customer_phone': phone.isEmpty ? null : phone,
              'payment_method': pay,
              'place': place,
              'shipping_cost': ship,
              'discount': disc,
              'date': date,
            },
            conflictAlgorithm: sqf.ConflictAlgorithm.abort,
          );
          rep = rep.copyWith(inserted: rep.inserted + 1);
        } else {
          await txn.update(
            'sales',
            {
              'customer_phone': phone.isEmpty ? null : phone,
              'payment_method': pay,
              'place': place,
              'shipping_cost': ship,
              'discount': disc,
              'date': date,
            },
            where: 'id=?',
            whereArgs: [extId],
            conflictAlgorithm: sqf.ConflictAlgorithm.abort,
          );
          rep = rep.copyWith(updated: rep.updated + 1);
        }
      } catch (e) {
        rep = rep.copyWith(skipped: rep.skipped + 1);
        errors.add('sales fila ${i + 1}: $e');
      }
    }

    // limpiar e insertar sale_items por sale_id
    await txn.delete('sale_items');
    for (var i = 1; i < shi.rows.length; i++) {
      final r = shi.rows[i];
      final saleId = _cellAsInt(r.elementAtOrNull(0));
      final sku = _cellAsString(r.elementAtOrNull(1));
      final qty = _cellAsInt(r.elementAtOrNull(2));
      final unit = _cellAsDouble(r.elementAtOrNull(3));

      if (sku.isEmpty || qty <= 0) {
        rep = rep.copyWith(skipped: rep.skipped + 1);
        errors.add('sale_items fila ${i + 1}: sku/qty inválidos');
        continue;
      }
      try {
        final prodId = _firstInt(await txn.rawQuery('SELECT id FROM products WHERE sku=?', [sku]));
        if (prodId == null) {
          rep = rep.copyWith(skipped: rep.skipped + 1);
          errors.add('sale_items fila ${i + 1}: SKU no existe ($sku)');
          continue;
        }
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': prodId,
          'quantity': qty,
          'unit_price': unit,
        });
      } catch (e) {
        rep = rep.copyWith(skipped: rep.skipped + 1);
        errors.add('sale_items fila ${i + 1}: $e');
      }
    }
  });

  return rep.copyWith(errors: errors);
}

Future<ImportReport> importPurchasesXlsx(Uint8List bytes) async {
  final db = await appdb.DatabaseHelper.instance.db;
  final book = ex.Excel.decodeBytes(bytes);
  final sh = book.sheets['purchases'];
  final shi = book.sheets['purchase_items'];
  if (sh == null || shi == null) throw 'Hojas "purchases" y/o "purchase_items" no encontradas';

  var rep = const ImportReport();
  final errors = <String>[];

  await db.transaction((txn) async {
    // purchases: id | folio | supplier_phone | date
    for (var i = 1; i < sh.rows.length; i++) {
      final r = sh.rows[i];
      final id = _cellAsInt(r.elementAtOrNull(0));
      final folio = _cellAsString(r.elementAtOrNull(1));
      final supplierPhone = _cellAsString(r.elementAtOrNull(2));
      final date = _cellAsString(r.elementAtOrNull(3));

      try {
        int? supplierId;
        if (supplierPhone.isNotEmpty) {
          supplierId = _firstInt(
            await txn.rawQuery('SELECT id FROM suppliers WHERE phone=?', [supplierPhone]),
          );
        }

        final exist = _firstInt(await txn.rawQuery('SELECT id FROM purchases WHERE id=?', [id]));
        final data = {
          'id': id,
          'folio': folio,
          'supplier_id': supplierId,
          'date': date,
        };

        if (exist == null) {
          await txn.insert('purchases', data, conflictAlgorithm: sqf.ConflictAlgorithm.abort);
          rep = rep.copyWith(inserted: rep.inserted + 1);
        } else {
          await txn.update(
            'purchases',
            data,
            where: 'id=?',
            whereArgs: [id],
            conflictAlgorithm: sqf.ConflictAlgorithm.abort,
          );
          rep = rep.copyWith(updated: rep.updated + 1);
        }
      } catch (e) {
        rep = rep.copyWith(skipped: rep.skipped + 1);
        errors.add('purchases fila ${i + 1}: $e');
      }
    }

    // items: purchase_id | product_sku | quantity | unit_cost
    await txn.delete('purchase_items');
    for (var i = 1; i < shi.rows.length; i++) {
      final r = shi.rows[i];
      final pid = _cellAsInt(r.elementAtOrNull(0));
      final sku = _cellAsString(r.elementAtOrNull(1));
      final qty = _cellAsInt(r.elementAtOrNull(2));
      final cost = _cellAsDouble(r.elementAtOrNull(3));

      if (sku.isEmpty || qty <= 0) {
        rep = rep.copyWith(skipped: rep.skipped + 1);
        errors.add('purchase_items fila ${i + 1}: sku/qty inválidos');
        continue;
      }
      try {
        final prodId = _firstInt(await txn.rawQuery('SELECT id FROM products WHERE sku=?', [sku]));
        if (prodId == null) {
          rep = rep.copyWith(skipped: rep.skipped + 1);
          errors.add('purchase_items fila ${i + 1}: SKU no existe ($sku)');
          continue;
        }
        await txn.insert('purchase_items', {
          'purchase_id': pid,
          'product_id': prodId,
          'quantity': qty,
          'unit_cost': cost,
        });

        // actualiza último costo de compra y fecha
        await txn.update(
          'products',
          {
            'last_purchase_price': cost,
            'last_purchase_date': DateTime.now().toIso8601String(),
          },
          where: 'id=?',
          whereArgs: [prodId],
        );
      } catch (e) {
        rep = rep.copyWith(skipped: rep.skipped + 1);
        errors.add('purchase_items fila ${i + 1}: $e');
      }
    }
  });

  return rep.copyWith(errors: errors);
}