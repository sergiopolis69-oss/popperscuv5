import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

// -------- Helpers
Future<void> _saveBytes(String name, List<int> bytes) async {
  final dir = await getDownloadsDirectory();
  final fpath = '${dir!.path}/$name.xlsx';
  final f = File(fpath);
  await f.writeAsBytes(bytes, flush: true);
  await FileSaver.instance.saveFile(name: name, ext: 'xlsx', mimeType: MimeType.other, bytes: Uint8List.fromList(bytes));
}

Future<Excel?> _pickExcel() async {
  final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
  if (res == null) return null;
  final f = res.files.single;
  final bytes = f.bytes ?? await File(f.path!).readAsBytes();
  return Excel.decodeBytes(bytes);
}

// -------- EXPORTS

Future<void> exportClientsXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('customers');
  final excel = Excel.createExcel();
  final sheet = excel['clientes'];
  sheet.appendRow(['phone','name','address']);
  for (final r in rows) {
    sheet.appendRow([r['phone'], r['name'], r['address']]);
  }
  final bytes = excel.encode()!;
  await _saveBytes('clientes', bytes);
}

Future<void> exportProductsXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('products');
  final excel = Excel.createExcel();
  final sheet = excel['productos'];
  sheet.appendRow(['id','sku','name','category','stock','last_purchase_price','last_purchase_date','default_sale_price','initial_cost']);
  for (final r in rows) {
    sheet.appendRow([
      r['id'], r['sku'], r['name'], r['category'], r['stock'],
      r['last_purchase_price'], r['last_purchase_date'],
      r['default_sale_price'], r['initial_cost'],
    ]);
  }
  final bytes = excel.encode()!;
  await _saveBytes('productos', bytes);
}

Future<void> exportSuppliersXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('suppliers');
  final excel = Excel.createExcel();
  final sheet = excel['proveedores'];
  sheet.appendRow(['id','name','phone','address']);
  for (final r in rows) {
    sheet.appendRow([r['id'], r['name'], r['phone'], r['address']]);
  }
  final bytes = excel.encode()!;
  await _saveBytes('proveedores', bytes);
}

Future<void> exportSalesXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final sales = await db.query('sales');
  final items = await db.query('sale_items');

  final excel = Excel.createExcel();
  final s1 = excel['ventas'];
  final s2 = excel['venta_items'];
  s1.appendRow(['id','customer_phone','payment_method','place','shipping_cost','discount','date']);
  for (final r in sales) {
    s1.appendRow([r['id'], r['customer_phone'], r['payment_method'], r['place'], r['shipping_cost'], r['discount'], r['date']]);
  }
  s2.appendRow(['sale_id','product_id','quantity','unit_price']);
  for (final it in items) {
    s2.appendRow([it['sale_id'], it['product_id'], it['quantity'], it['unit_price']]);
  }

  final bytes = excel.encode()!;
  await _saveBytes('ventas', bytes);
}

Future<void> exportPurchasesXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final purchases = await db.query('purchases');
  final items = await db.query('purchase_items');

  final excel = Excel.createExcel();
  final s1 = excel['compras'];
  final s2 = excel['compra_items'];
  s1.appendRow(['id','folio','supplier_id','date']);
  for (final r in purchases) {
    s1.appendRow([r['id'], r['folio'], r['supplier_id'], r['date']]);
  }
  s2.appendRow(['purchase_id','product_id','quantity','unit_cost']);
  for (final it in items) {
    s2.appendRow([it['purchase_id'], it['product_id'], it['quantity'], it['unit_cost']]);
  }

  final bytes = excel.encode()!;
  await _saveBytes('compras', bytes);
}

// -------- IMPORTS

Future<void> importClientsXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) return;
  final sheet = excel['clientes'];
  final db = await DatabaseHelper.instance.db;
  final batch = db.batch();
  for (var i = 1; i < sheet.maxRows; i++) {
    final row = sheet.row(i);
    if (row.length < 2) continue;
    final phone = row[0]?.value?.toString() ?? '';
    if (phone.isEmpty) continue;
    final name = row[1]?.value?.toString() ?? '';
    final addr = row.length > 2 ? row[2]?.value?.toString() ?? '' : '';
    batch.insert('customers', {'phone': phone, 'name': name, 'address': addr}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

Future<void> importProductsXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) return;
  final sheet = excel['productos'];
  final db = await DatabaseHelper.instance.db;
  final batch = db.batch();
  for (var i = 1; i < sheet.maxRows; i++) {
    final r = sheet.row(i);
    if (r.length < 3) continue;
    final name = r[2]?.value?.toString() ?? '';
    if (name.isEmpty) continue;
    batch.insert('products', {
      'id': _toInt(r,0),
      'sku': r[1]?.value?.toString(),
      'name': name,
      'category': r.length>3 ? r[3]?.value?.toString() ?? '' : '',
      'stock': _toInt(r,4) ?? 0,
      'last_purchase_price': _toDouble(r,5) ?? 0.0,
      'last_purchase_date': r.length>6 ? r[6]?.value?.toString() : null,
      'default_sale_price': _toDouble(r,7) ?? 0.0,
      'initial_cost': _toDouble(r,8) ?? 0.0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

Future<void> importSuppliersXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) return;
  final sheet = excel['proveedores'];
  final db = await DatabaseHelper.instance.db;
  final batch = db.batch();
  for (var i = 1; i < sheet.maxRows; i++) {
    final r = sheet.row(i);
    if (r.length < 3) continue;
    final name = r[1]?.value?.toString() ?? '';
    final phone = r[2]?.value?.toString() ?? '';
    if (name.isEmpty) continue;
    batch.insert('suppliers', {
      'id': _toInt(r,0),
      'name': name,
      'phone': phone,
      'address': r.length>3 ? r[3]?.value?.toString() ?? '' : '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

Future<void> importSalesXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) return;
  final s1 = excel['ventas'];
  final s2 = excel['venta_items'];
  final db = await DatabaseHelper.instance.db;

  final batch = db.batch();
  for (var i = 1; i < s1.maxRows; i++) {
    final r = s1.row(i);
    if (r.length < 7) continue;
    batch.insert('sales', {
      'id': _toInt(r,0),
      'customer_phone': r[1]?.value?.toString(),
      'payment_method': r[2]?.value?.toString(),
      'place': r[3]?.value?.toString(),
      'shipping_cost': _toDouble(r,4) ?? 0.0,
      'discount': _toDouble(r,5) ?? 0.0,
      'date': r[6]?.value?.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  for (var i = 1; i < s2.maxRows; i++) {
    final r = s2.row(i);
    if (r.length < 4) continue;
    batch.insert('sale_items', {
      'sale_id': _toInt(r,0),
      'product_id': _toInt(r,1),
      'quantity': _toInt(r,2) ?? 0,
      'unit_price': _toDouble(r,3) ?? 0.0,
    });
  }
  await batch.commit(noResult: true);
}

Future<void> importPurchasesXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) return;
  final s1 = excel['compras'];
  final s2 = excel['compra_items'];
  final db = await DatabaseHelper.instance.db;

  final batch = db.batch();
  for (var i = 1; i < s1.maxRows; i++) {
    final r = s1.row(i);
    if (r.length < 4) continue;
    batch.insert('purchases', {
      'id': _toInt(r,0),
      'folio': r[1]?.value?.toString(),
      'supplier_id': _toInt(r,2),
      'date': r[3]?.value?.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  for (var i = 1; i < s2.maxRows; i++) {
    final r = s2.row(i);
    if (r.length < 4) continue;
    batch.insert('purchase_items', {
      'purchase_id': _toInt(r,0),
      'product_id': _toInt(r,1),
      'quantity': _toInt(r,2) ?? 0,
      'unit_cost': _toDouble(r,3) ?? 0.0,
    });
  }
  await batch.commit(noResult: true);
}

// helpers parse
int? _toInt(List<Data?> r, int idx) {
  final v = (idx<r.length)? r[idx]?.value : null;
  if (v == null) return null;
  return int.tryParse(v.toString());
}
double? _toDouble(List<Data?> r, int idx) {
  final v = (idx<r.length)? r[idx]?.value : null;
  if (v == null) return null;
  return double.tryParse(v.toString().replaceAll(',', '.'));
}