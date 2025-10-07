import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';
import 'android_downloads.dart';

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

/// ------------------------------------------------------
/// EXPORTAR DIRECTAMENTE A DESCARGAS
/// ------------------------------------------------------

Future<String> exportClientsXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('customers');
  final excel = _newBook();
  final sh = excel['clientes'];
  sh.appendRow(['phone', 'name', 'address']);
  for (final r in rows) {
    sh.appendRow([r['phone'], r['name'], r['address']]);
  }
  final bytes = excel.encode()!;
  return await AndroidDownloads.saveBytes(baseName: 'clientes', bytes: bytes);
}

Future<String> exportProductsXlsx() async {
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
      r['default_sale_price'], r['initial_cost'],
    ]);
  }
  final bytes = excel.encode()!;
  return await AndroidDownloads.saveBytes(baseName: 'productos', bytes: bytes);
}

Future<String> exportSuppliersXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('suppliers');
  final excel = _newBook();
  final sh = excel['proveedores'];
  sh.appendRow(['id','name','phone','address']);
  for (final r in rows) {
    sh.appendRow([r['id'], r['name'], r['phone'], r['address']]);
  }
  final bytes = excel.encode()!;
  return await AndroidDownloads.saveBytes(baseName: 'proveedores', bytes: bytes);
}

Future<String> exportSalesXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final sales = await db.query('sales');
  final items = await db.query('sale_items');
  final excel = _newBook();
  final s1 = excel['ventas'];
  final s2 = excel['venta_items'];
  s1.appendRow(['id','customer_phone','payment_method','place','shipping_cost','discount','date']);
  for (final r in sales) {
    s1.appendRow([
      r['id'], r['customer_phone'], r['payment_method'], r['place'],
      r['shipping_cost'], r['discount'], r['date'],
    ]);
  }
  s2.appendRow(['sale_id','product_id','quantity','unit_price']);
  for (final it in items) {
    s2.appendRow([it['sale_id'], it['product_id'], it['quantity'], it['unit_price']]);
  }
  final bytes = excel.encode()!;
  return await AndroidDownloads.saveBytes(baseName: 'ventas', bytes: bytes);
}

Future<String> exportPurchasesXlsx() async {
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
  return await AndroidDownloads.saveBytes(baseName: 'compras', bytes: bytes);
}

Future<String> exportProductsTemplateXlsx() async {
  final excel = _newBook();
  final sh = excel['productos'];
  sh.appendRow([
    'id (opcional)','sku','name*','category',
    'stock','last_purchase_price','last_purchase_date',
    'default_sale_price','initial_cost'
  ]);
  sh.appendRow([null,'ABC-001','Ejemplo','Categoría',10,100,'2025-01-01',150,80]);
  final bytes = excel.encode()!;
  return await AndroidDownloads.saveBytes(baseName: 'plantilla_productos', bytes: bytes);
}

Future<void> openUriOrPath(String uriOrPath) async {
  await OpenFilex.open(uriOrPath);
}