import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../data/db.dart' as appdb;

/// ===== Helpers de Excel (CellValue) =====

CellValue _t(String v) => TextCellValue(v);
CellValue _d(num? v) => DoubleCellValue((v ?? 0).toDouble());
CellValue _i(num? v) => IntCellValue((v ?? 0).toInt());

String _tsName(String base) {
  final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  return '${base}_$ts.xlsx';
}

Future<String> _saveBytes(Uint8List bytes, String filename) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Sheet _sheet(Excel ex, String name) {
  // El operador [] crea la hoja si no existe en excel 4.x
  return ex[name];
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

  // encabezados (CellValue)
  sh.appendRow(<CellValue?>[
    _t('sku'),
    _t('name'),
    _t('category'),
    _t('default_sale_price'),
    _t('last_purchase_price'),
    _t('stock'),
  ]);

  for (final r in rows) {
    sh.appendRow(<CellValue?>[
      _t((r['sku'] ?? '').toString()),
      _t((r['name'] ?? '').toString()),
      _t((r['category'] ?? '').toString()),
      _d(r['default_sale_price'] as num?),
      _d(r['last_purchase_price'] as num?),
      _i(r['stock'] as num?),
    ]);
  }

  final bytes = Uint8List.fromList(ex.encode()!);
  return _saveBytes(bytes, _tsName('productos'));
}

Future<String> exportClientsXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final rows = await db.query('customers', orderBy: 'name COLLATE NOCASE');

  final ex = Excel.createExcel();
  final sh = _sheet(ex, 'clients');

  sh.appendRow(<CellValue?>[
    _t('phone'),
    _t('name'),
    _t('address'),
  ]);

  for (final r in rows) {
    sh.appendRow(<CellValue?>[
      _t((r['phone'] ?? '').toString()),
      _t((r['name'] ?? '').toString()),
      _t((r['address'] ?? '').toString()),
    ]);
  }

  final bytes = Uint8List.fromList(ex.encode()!);
  return _saveBytes(bytes, _tsName('clientes'));
}

Future<String> exportSuppliersXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;
  final rows = await db.query('suppliers', orderBy: 'name COLLATE NOCASE');

  final ex = Excel.createExcel();
  final sh = _sheet(ex, 'suppliers');

  sh.appendRow(<CellValue?>[
    _t('phone'),
    _t('name'),
    _t('address'),
  ]);

  for (final r in rows) {
    sh.appendRow(<CellValue?>[
      _t((r['phone'] ?? '').toString()),
      _t((r['name'] ?? '').toString()),
      _t((r['address'] ?? '').toString()),
    ]);
  }

  final bytes = Uint8List.fromList(ex.encode()!);
  return _saveBytes(bytes, _tsName('proveedores'));
}

Future<String> exportSalesXlsx() async {
  final db = await appdb.DatabaseHelper.instance.db;

  final sales = await db.query('sales', orderBy: 'date DESC');
  final items = await db.query('sale_items');

  final ex = Excel.createExcel();
  final sh = _sheet(ex, 'sales');
  final si = _sheet(ex, 'sale_items');

  sh.appendRow(<CellValue?>[
    _t('id'),
    _t('customer_phone'),
    _t('payment_method'),
    _t('place'),
    _t('shipping_cost'),
    _t('discount'),
    _t('date'),
  ]);

  for (final r in sales) {
    sh.appendRow(<CellValue?>[
      _i(r['id'] as num?),
      _t((r['customer_phone'] ?? '').toString()),
      _t((r['payment_method'] ?? '').toString()),
      _t((r['place'] ?? '').toString()),
      _d(r['shipping_cost'] as num?),
      _d(r['discount'] as num?),
      _t((r['date'] ?? '').toString()),
    ]);
  }

  si.appendRow(<CellValue?>[
    _t('sale_id'),
    _t('product_sku'),
    _t('quantity'),
    _t('unit_price'),
  ]);

  for (final r in items) {
    si.appendRow(<CellValue?>[
      _i(r['sale_id'] as num?),
      _t((r['product_sku'] ?? '').toString()),
      _i(r['quantity'] as num?),
      _d(r['unit_price'] as num?),
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

  sh.appendRow(<CellValue?>[
    _t('id'),
    _t('folio'),
    _t('supplier_phone'),
    _t('date'),
  ]);

  for (final r in purchases) {
    sh.appendRow(<CellValue?>[
      _i(r['id'] as num?),
      _t((r['folio'] ?? '').toString()),
      _t((r['supplier_phone'] ?? '').toString()),
      _t((r['date'] ?? '').toString()),
    ]);
  }

  si.appendRow(<CellValue?>[
    _t('purchase_id'),
    _t('product_sku'),
    _t('quantity'),
    _t('unit_cost'),
  ]);

  for (final r in items) {
    si.appendRow(<CellValue?>[
      _i(r['purchase_id'] as num?),
      _t((r['product_sku'] ?? '').toString()),
      _i(r['quantity'] as num?),
      _d(r['unit_cost'] as num?),
    ]);
  }

  final bytes = Uint8List.fromList(ex.encode()!);
  return _saveBytes(bytes, _tsName('compras'));
}