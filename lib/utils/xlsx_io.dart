import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart'; // para Database / ConflictAlgorithm
import '../data/db.dart' as appdb;

/// Genera un nombre de archivo con timestamp seguro
String _tsName(String base) {
  final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  return '${base}_$ts.xlsx';
}

/// Guarda bytes en el directorio de documentos de la app y devuelve la ruta final.
Future<String> _saveBytes(Uint8List bytes, String filename) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// Crea/obtiene una hoja dentro del Excel.
Sheet _sheet(Excel ex, String name) {
  return ex.sheets[name] ?? ex['$name'];
}

/// Lee toda una tabla de la base (helper simple)
Future<List<Map<String, Object?>>> _all(Database db, String table) async {
  return db.query(table);
}

/// =============== EXPORTS ===============

Future<String> exportProductsXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final rows = await db.query(
    'products',
    orderBy: 'name COLLATE NOCASE',
  );

  final ex = Excel.createExcel();
  final sh = _sheet(ex, 'products');

  // encabezados
  sh.appendRow(<dynamic>[
    'sku',
    'name',
    'category',
    'default_sale_price',
    'last_purchase_price',
    'stock',
  ]);

  for (final r in rows) {
    sh.appendRow(<dynamic>[
      (r['sku'] ?? '').toString(),
      (r['name'] ?? '').toString(),
      (r['category'] ?? '').toString(),
      (r['default_sale_price'] as num?)?.toDouble() ?? 0.0,
      (r['last_purchase_price'] as num?)?.toDouble() ?? 0.0,
      (r['stock'] as num?)?.toInt() ?? 0,
    ]);
  }

  final bytes = Uint8List.fromList(ex.encode()!);
  return _saveBytes(bytes, _tsName('productos'));
}

Future<String> exportClientsXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final rows = await _all(db, 'customers');

  final ex = Excel.createExcel();
  final sh = _sheet(ex, 'clients');

  sh.appendRow(<dynamic>['phone', 'name', 'address']);
  for (final r in rows) {
    sh.appendRow(<dynamic>[
      (r['phone'] ?? '').toString(),
      (r['name'] ?? '').toString(),
      (r['address'] ?? '').toString(),
    ]);
  }

  final bytes = Uint8List.fromList(ex.encode()!);
  return _saveBytes(bytes, _tsName('clientes'));
}

Future<String> exportSuppliersXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final rows = await _all(db, 'suppliers');

  final ex = Excel.createExcel();
  final sh = _sheet(ex, 'suppliers');

  sh.appendRow(<dynamic>['phone', 'name', 'address']);
  for (final r in rows) {
    sh.appendRow(<dynamic>[
      (r['phone'] ?? '').toString(),
      (r['name'] ?? '').toString(),
      (r['address'] ?? '').toString(),
    ]);
  }

  final bytes = Uint8List.fromList(ex.encode()!);
  return _saveBytes(bytes, _tsName('proveedores'));
}

Future<String> exportSalesXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;

  final sales = await db.query('sales', orderBy: 'date DESC');
  final items = await db.query('sale_items'); // detalle

  final ex = Excel.createExcel();
  final sh = _sheet(ex, 'sales');
  final si = _sheet(ex, 'sale_items');

  sh.appendRow(<dynamic>[
    'id',
    'customer_phone',
    'payment_method',
    'place',
    'shipping_cost',
    'discount',
    'date',
  ]);

  for (final r in sales) {
    sh.appendRow(<dynamic>[
      (r['id'] as num?)?.toInt() ?? 0,
      (r['customer_phone'] ?? '').toString(),
      (r['payment_method'] ?? '').toString(),
      (r['place'] ?? '').toString(),
      (r['shipping_cost'] as num?)?.toDouble() ?? 0.0,
      (r['discount'] as num?)?.toDouble() ?? 0.0,
      (r['date'] ?? '').toString(),
    ]);
  }

  si.appendRow(<dynamic>['sale_id', 'product_sku', 'quantity', 'unit_price']);
  for (final r in items) {
    si.appendRow(<dynamic>[
      (r['sale_id'] as num?)?.toInt() ?? 0,
      (r['product_sku'] ?? '').toString(),
      (r['quantity'] as num?)?.toInt() ?? 0,
      (r['unit_price'] as num?)?.toDouble() ?? 0.0,
    ]);
  }

  final bytes = Uint8List.fromList(ex.encode()!);
  return _saveBytes(bytes, _tsName('ventas'));
}

Future<String> exportPurchasesXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;

  final purchases = await db.query('purchases', orderBy: 'date DESC');
  final items = await db.query('purchase_items');

  final ex = Excel.createExcel();
  final sh = _sheet(ex, 'purchases');
  final si = _sheet(ex, 'purchase_items');

  sh.appendRow(<dynamic>['id', 'folio', 'supplier_phone', 'date']);
  for (final r in purchases) {
    sh.appendRow(<dynamic>[
      (r['id'] as num?)?.toInt() ?? 0,
      (r['folio'] ?? '').toString(),
      (r['supplier_phone'] ?? '').toString(),
      (r['date'] ?? '').toString(),
    ]);
  }

  si.appendRow(<dynamic>['purchase_id', 'product_sku', 'quantity', 'unit_cost']);
  for (final r in items) {
    si.appendRow(<dynamic>[
      (r['purchase_id'] as num?)?.toInt() ?? 0,
      (r['product_sku'] ?? '').toString(),
      (r['quantity'] as num?)?.toInt() ?? 0,
      (r['unit_cost'] as num?)?.toDouble() ?? 0.0,
    ]);
  }

  final bytes = Uint8List.fromList(ex.encode()!);
  return _saveBytes(bytes, _tsName('compras'));
}