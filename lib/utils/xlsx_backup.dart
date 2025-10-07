import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:downloads_path_provider_28/downloads_path_provider_28.dart';
import 'package:open_filex/open_filex.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

/// =======================================================
///      Utilidades de exportación / importación XLSX
/// =======================================================

Future<Directory> _downloadsDir() async {
  final d = await DownloadsPathProvider.downloadsDirectory;
  return d ?? await getApplicationDocumentsDirectory();
}

Future<File> _saveInDownloads(String name, List<int> bytes) async {
  final dir = await _downloadsDir();
  final path = '${dir.path}/$name.xlsx';
  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<Excel?> _pickExcel() async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
  );
  if (res == null) return null;
  final file = res.files.single;
  final bytes = file.bytes ?? await File(file.path!).readAsBytes();
  return Excel.decodeBytes(bytes);
}

Excel _newBook() {
  final excel = Excel.createExcel();
  final def = excel.getDefaultSheet();
  if (def != null) excel.delete(def);
  return excel;
}

Sheet? _sheetInsensitive(Excel e, String n) {
  for (final k in e.tables.keys) {
    if (k.toLowerCase() == n.toLowerCase()) return e.tables[k];
  }
  return null;
}

String _s(Data? d) => d?.value?.toString().trim() ?? '';
int _i(Data? d) => int.tryParse(_s(d)) ?? 0;
double _d(Data? d) => double.tryParse(_s(d).replaceAll(',', '.')) ?? 0.0;

/// =======================================================
///                    EXPORTS
/// =======================================================

Future<File> exportClientsXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('customers');
  final excel = _newBook();
  final sh = excel['clientes'];
  sh.appendRow(['phone','name','address']);
  for (final r in rows) {
    sh.appendRow([r['phone'], r['name'], r['address']]);
  }
  final bytes = excel.encode()!;
  final file = await _saveInDownloads('clientes', bytes);
  return file;
}

Future<File> exportProductsXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('products');
  final excel = _newBook();
  final sh = excel['productos'];
  sh.appendRow([
    'id','sku','name','category','stock',
    'last_purchase_price','last_purchase_date',
    'default_sale_price','initial_cost'
  ]);
  for (final r in rows) {
    sh.appendRow([
      r['id'], r['sku'], r['name'], r['category'], r['stock'],
      r['last_purchase_price'], r['last_purchase_date'],
      r['default_sale_price'], r['initial_cost']
    ]);
  }
  final bytes = excel.encode()!;
  return await _saveInDownloads('productos', bytes);
}

Future<File> exportSuppliersXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('suppliers');
  final excel = _newBook();
  final sh = excel['proveedores'];
  sh.appendRow(['id','name','phone','address']);
  for (final r in rows) {
    sh.appendRow([r['id'], r['name'], r['phone'], r['address']]);
  }
  final bytes = excel.encode()!;
  return await _saveInDownloads('proveedores', bytes);
}

Future<File> exportSalesXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final sales = await db.query('sales');
  final items = await db.query('sale_items');
  final excel = _newBook();
  final s1 = excel['ventas'];
  final s2 = excel['venta_items'];
  s1.appendRow(['id','customer_phone','payment_method','place','shipping_cost','discount','date']);
  for (final r in sales) {
    s1.appendRow([
      r['id'], r['customer_phone'], r['payment_method'],
      r['place'], r['shipping_cost'], r['discount'], r['date']
    ]);
  }
  s2.appendRow(['sale_id','product_id','quantity','unit_price']);
  for (final it in items) {
    s2.appendRow([it['sale_id'], it['product_id'], it['quantity'], it['unit_price']]);
  }
  final bytes = excel.encode()!;
  return await _saveInDownloads('ventas', bytes);
}

Future<File> exportPurchasesXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final purchases = await db.query('purchases');
  final items = await db.query('purchase_items');
  final excel = _newBook();
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
  return await _saveInDownloads('compras', bytes);
}

Future<File> exportProductsTemplateXlsx() async {
  final excel = _newBook();
  final sh = excel['productos'];
  sh.appendRow([
    'id (opcional)','sku','name*','category',
    'stock','last_purchase_price','last_purchase_date','default_sale_price','initial_cost'
  ]);
  sh.appendRow([null,'ABC-001','Ejemplo','Categoría',10,100,'2025-01-01',150,80]);
  final bytes = excel.encode()!;
  return await _saveInDownloads('plantilla_productos', bytes);
}

/// =======================================================
///                    IMPORTS
/// =======================================================

Future<void> importClientsXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) return;
  final sh = _sheetInsensitive(excel, 'clientes');
  if (sh == null) throw 'Hoja clientes no encontrada';
  final db = await DatabaseHelper.instance.db;
  final batch = db.batch();
  for (var i=1; i<sh.maxRows; i++) {
    final r = sh.row(i);
    batch.insert('customers', {
      'phone': _s(r[0]),
      'name': _s(r[1]),
      'address': _s(r[2])
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult:true);
}

Future<void> importProductsXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) return;
  final sh = _sheetInsensitive(excel, 'productos');
  if (sh == null) throw 'Hoja productos no encontrada';
  final db = await DatabaseHelper.instance.db;
  final batch = db.batch();
  for (var i=1; i<sh.maxRows; i++) {
    final r = sh.row(i);
    batch.insert('products', {
      'id': _i(r[0]),
      'sku': _s(r[1]),
      'name': _s(r[2]),
      'category': _s(r[3]),
      'stock': _i(r[4]),
      'last_purchase_price': _d(r[5]),
      'last_purchase_date': _s(r[6]),
      'default_sale_price': _d(r[7]),
      'initial_cost': _d(r[8]),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult:true);
}

Future<void> importSuppliersXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) return;
  final sh = _sheetInsensitive(excel, 'proveedores');
  if (sh == null) throw 'Hoja proveedores no encontrada';
  final db = await DatabaseHelper.instance.db;
  final batch = db.batch();
  for (var i=1; i<sh.maxRows; i++) {
    final r = sh.row(i);
    batch.insert('suppliers', {
      'id': _i(r[0]),
      'name': _s(r[1]),
      'phone': _s(r[2]),
      'address': _s(r[3]),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult:true);
}

Future<void> importSalesXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) return;
  final s1 = _sheetInsensitive(excel, 'ventas');
  final s2 = _sheetInsensitive(excel, 'venta_items');
  if (s1 == null || s2 == null) throw 'Hojas ventas/venta_items no encontradas';
  final db = await DatabaseHelper.instance.db;
  final batch = db.batch();
  for (var i=1; i<s1.maxRows; i++) {
    final r = s1.row(i);
    batch.insert('sales', {
      'id': _i(r[0]),
      'customer_phone': _s(r[1]),
      'payment_method': _s(r[2]),
      'place': _s(r[3]),
      'shipping_cost': _d(r[4]),
      'discount': _d(r[5]),
      'date': _s(r[6]),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  for (var i=1; i<s2.maxRows; i++) {
    final r = s2.row(i);
    batch.insert('sale_items', {
      'sale_id': _i(r[0]),
      'product_id': _i(r[1]),
      'quantity': _i(r[2]),
      'unit_price': _d(r[3]),
    });
  }
  await batch.commit(noResult:true);
}

Future<void> importPurchasesXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) return;
  final s1 = _sheetInsensitive(excel, 'compras');
  final s2 = _sheetInsensitive(excel, 'compra_items');
  if (s1 == null || s2 == null) throw 'Hojas compras/compra_items no encontradas';
  final db = await DatabaseHelper.instance.db;
  final batch = db.batch();
  for (var i=1; i<s1.maxRows; i++) {
    final r = s1.row(i);
    batch.insert('purchases', {
      'id': _i(r[0]),
      'folio': _s(r[1]),
      'supplier_id': _i(r[2]),
      'date': _s(r[3]),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  for (var i=1; i<s2.maxRows; i++) {
    final r = s2.row(i);
    batch.insert('purchase_items', {
      'purchase_id': _i(r[0]),
      'product_id': _i(r[1]),
      'quantity': _i(r[2]),
      'unit_cost': _d(r[3]),
    });
  }
  await batch.commit(noResult:true);
}