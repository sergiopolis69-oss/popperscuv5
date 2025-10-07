import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

/// ----------------------------------------------------
/// Helpers
/// ----------------------------------------------------

Future<void> _ensureStoragePermission() async {
  // Defensivo: en Android 10+ no siempre es necesario, pero si el usuario lo niega, fallaría el picker/guardado.
  final status = await Permission.storage.request();
  // No forzamos error si está denegado, porque FileSaver puede usar SAF. Solo lo pedimos para mejorar tasa de éxito.
}

Excel _newBook() {
  final excel = Excel.createExcel();
  final def = excel.getDefaultSheet();
  if (def != null) {
    excel.delete(def); // evita hoja "Sheet1"
  }
  return excel;
}

Sheet? _getSheetInsensitive(Excel excel, String name) {
  for (final n in excel.tables.keys) {
    if (n.toLowerCase() == name.toLowerCase()) return excel.tables[n];
  }
  return null;
}

String _cellStr(Data? d) => d?.value?.toString().trim() ?? '';
int _cellInt(Data? d) => int.tryParse(_cellStr(d)) ?? 0;
double _cellDouble(Data? d) => double.tryParse(_cellStr(d).replaceAll(',', '.')) ?? 0.0;

/// Guarda usando FileSaver (preferido para Downloads / SAF) y además
/// deja copia en Documentos de la app por si el FileSaver no muestra diálogo.
Future<void> _saveAsXlsx(String baseName, List<int> bytes) async {
  try {
    // Copia local (no visible en Descargas, pero útil para depurar)
    final dbDir = await getDatabasesPath(); // disponible vía sqflite
    final f = File('$dbDir/$baseName.xlsx');
    await f.writeAsBytes(bytes, flush: true);
  } catch (_) {}

  // Descarga / SAF
  await FileSaver.instance.saveFile(
    name: baseName,
    ext: 'xlsx',
    mimeType: MimeType.microsoftExcel,
    bytes: Uint8List.fromList(bytes),
  );
}

Future<Excel?> _pickExcel() async {
  await _ensureStoragePermission();
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
  );
  if (res == null) return null;
  final file = res.files.single;
  final bytes = file.bytes ?? await File(file.path!).readAsBytes();
  return Excel.decodeBytes(bytes);
}

/// ----------------------------------------------------
/// EXPORTS
/// ----------------------------------------------------

Future<void> exportClientsXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('customers');
  final excel = _newBook();
  final sh = excel['clientes'];
  sh.appendRow(['phone', 'name', 'address']);
  for (final r in rows) {
    sh.appendRow([r['phone'], r['name'], r['address']]);
  }
  final bytes = excel.encode()!;
  await _saveAsXlsx('clientes', bytes);
}

Future<void> exportProductsXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('products');
  final excel = _newBook();
  final sh = excel['productos'];
  sh.appendRow([
    'id', 'sku', 'name', 'category', 'stock',
    'last_purchase_price', 'last_purchase_date',
    'default_sale_price', 'initial_cost'
  ]);
  for (final r in rows) {
    sh.appendRow([
      r['id'], r['sku'], r['name'], r['category'], r['stock'],
      r['last_purchase_price'], r['last_purchase_date'],
      r['default_sale_price'], r['initial_cost'],
    ]);
  }
  final bytes = excel.encode()!;
  await _saveAsXlsx('productos', bytes);
}

Future<void> exportSuppliersXlsx() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('suppliers');
  final excel = _newBook();
  final sh = excel['proveedores'];
  sh.appendRow(['id', 'name', 'phone', 'address']);
  for (final r in rows) {
    sh.appendRow([r['id'], r['name'], r['phone'], r['address']]);
  }
  final bytes = excel.encode()!;
  await _saveAsXlsx('proveedores', bytes);
}

Future<void> exportSalesXlsx() async {
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
      r['shipping_cost'], r['discount'], r['date']
    ]);
  }
  s2.appendRow(['sale_id','product_id','quantity','unit_price']);
  for (final it in items) {
    s2.appendRow([it['sale_id'], it['product_id'], it['quantity'], it['unit_price']]);
  }
  final bytes = excel.encode()!;
  await _saveAsXlsx('ventas', bytes);
}

Future<void> exportPurchasesXlsx() async {
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
  await _saveAsXlsx('compras', bytes);
}

/// Plantilla de productos
Future<void> exportProductsTemplateXlsx() async {
  final excel = _newBook();
  final sh = excel['productos'];
  sh.appendRow([
    'id (opcional)', 'sku', 'name*', 'category',
    'stock (entero)', 'last_purchase_price',
    'last_purchase_date(YYYY-MM-DD)',
    'default_sale_price', 'initial_cost'
  ]);
  sh.appendRow([null, 'ABC-001', 'Gorra azul', 'Accesorios', 10, 80.0, '2025-01-15', 129.0, 70.0]);
  final bytes = excel.encode()!;
  await _saveAsXlsx('plantilla_productos', bytes);
}

/// ----------------------------------------------------
/// IMPORTS
/// ----------------------------------------------------

Future<void> importClientsXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) return;
  final sh = _getSheetInsensitive(excel, 'clientes');
  if (sh == null) throw 'Hoja "clientes" no encontrada';
  final db = await DatabaseHelper.instance.db;
  final batch = db.batch();
  for (var i = 1; i < sh.maxRows; i++) {
    final row = sh.row(i);
    final phone = _cellStr(row.isNotEmpty ? row[0] : null);
    if (phone.isEmpty) continue;
    final name = _cellStr(row.length>1 ? row[1] : null);
    final addr = _cellStr(row.length>2 ? row[2] : null);
    batch.insert('customers', {'phone':phone,'name':name,'address':addr},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

Future<void> importProductsXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) return;
  final sh = _getSheetInsensitive(excel, 'productos');
  if (sh == null) throw 'Hoja "productos" no encontrada';
  final db = await DatabaseHelper.instance.db;
  final batch = db.batch();
  for (var i = 1; i < sh.maxRows; i++) {
    final r = sh.row(i);
    final name = _cellStr(r.length>2 ? r[2] : null);
    if (name.isEmpty) continue;
    final id = _cellInt(r.isNotEmpty ? r[0] : null);
    batch.insert('products', {
      'id': id == 0 ? null : id,
      'sku': _cellStr(r.length>1 ? r[1] : null),
      'name': name,
      'category': _cellStr(r.length>3 ? r[3] : null),
      'stock': _cellInt(r.length>4 ? r[4] : null),
      'last_purchase_price': _cellDouble(r.length>5 ? r[5] : null),
      'last_purchase_date': (() {
        final s = _cellStr(r.length>6 ? r[6] : null);
        return s.isEmpty ? null : s;
      })(),
      'default_sale_price': _cellDouble(r.length>7 ? r[7] : null),
      'initial_cost': _cellDouble(r.length>8 ? r[8] : null),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

Future<void> importSuppliersXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) return;
  final sh = _getSheetInsensitive(excel, 'proveedores');
  if (sh == null) throw 'Hoja "proveedores" no encontrada';
  final db = await DatabaseHelper.instance.db;
  final batch = db.batch();
  for (var i = 1; i < sh.maxRows; i++) {
    final r = sh.row(i);
    final name = _cellStr(r.length>1 ? r[1] : null);
    if (name.isEmpty) continue;
    final id = _cellInt(r.isNotEmpty ? r[0] : null);
    batch.insert('suppliers', {
      'id': id == 0 ? null : id,
      'name': name,
      'phone': _cellStr(r.length>2 ? r[2] : null),
      'address': _cellStr(r.length>3 ? r[3] : null),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

Future<void> importSalesXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) return;
  final s1 = _getSheetInsensitive(excel, 'ventas');
  final s2 = _getSheetInsensitive(excel, 'venta_items');
  if (s1 == null || s2 == null) throw 'Hojas "ventas" y/o "venta_items" no encontradas';
  final db = await DatabaseHelper.instance.db;
  final batch = db.batch();
  for (var i = 1; i < s1.maxRows; i++) {
    final r = s1.row(i);
    batch.insert('sales', {
      'id': _cellInt(r[0]),
      'customer_phone': _cellStr(r[1]),
      'payment_method': _cellStr(r[2]),
      'place': _cellStr(r[3]),
      'shipping_cost': _cellDouble(r[4]),
      'discount': _cellDouble(r[5]),
      'date': _cellStr(r[6]),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  for (var i = 1; i < s2.maxRows; i++) {
    final r = s2.row(i);
    batch.insert('sale_items', {
      'sale_id': _cellInt(r[0]),
      'product_id': _cellInt(r[1]),
      'quantity': _cellInt(r[2]),
      'unit_price': _cellDouble(r[3]),
    });
  }
  await batch.commit(noResult: true);
}

Future<void> importPurchasesXlsx() async {
  final excel = await _pickExcel();
  if (excel == null) return;
  final s1 = _getSheetInsensitive(excel, 'compras');
  final s2 = _getSheetInsensitive(excel, 'compra_items');
  if (s1 == null || s2 == null) throw 'Hojas "compras" y/o "compra_items" no encontradas';
  final db = await DatabaseHelper.instance.db;
  final batch = db.batch();
  for (var i = 1; i < s1.maxRows; i++) {
    final r = s1.row(i);
    batch.insert('purchases', {
      'id': _cellInt(r[0]),
      'folio': _cellStr(r[1]),
      'supplier_id': _cellInt(r[2]),
      'date': _cellStr(r[3]),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  for (var i = 1; i < s2.maxRows; i++) {
    final r = s2.row(i);
    batch.insert('purchase_items', {
      'purchase_id': _cellInt(r[0]),
      'product_id': _cellInt(r[1]),
      'quantity': _cellInt(r[2]),
      'unit_cost': _cellDouble(r[3]),
    });
  }
  await batch.commit(noResult: true);
}