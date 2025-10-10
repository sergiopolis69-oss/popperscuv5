import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:downloads_path_provider_28/downloads_path_provider_28.dart';
import '../repositories/product_repository.dart';
import '../data/db.dart';

// Helpers
Future<File> _saveToDownloads(Uint8List bytes, String fileName) async {
  Directory? dir;
  if (Platform.isAndroid) {
    await Permission.storage.request();
    dir = await DownloadsPathProvider.downloadsDirectory;
  }
  dir ??= await getApplicationDocumentsDirectoryCompat(); // fallback interno
  final f = File('${dir.path}/$fileName');
  await f.writeAsBytes(bytes, flush: true);
  return f;
}

// Fallback interno si falla la lib de descargas
Future<Directory> getApplicationDocumentsDirectoryCompat() async {
  final base = Directory('/storage/emulated/0/Android/data');
  final pkg = 'com.example.popperscuv5';
  final d = Directory('${base.path}/$pkg/files');
  if (!(await d.exists())) await d.create(recursive: true);
  return d;
}

Uint8List _excelToBytes(Excel ex) {
  final bytes = ex.encode();
  if (bytes == null) throw Exception('No se pudo codificar XLSX');
  return Uint8List.fromList(bytes);
}

// -------------------- EXPORT --------------------

Future<File> exportProductsXlsx() async {
  final repo = ProductRepository();
  final rows = await repo.all();

  final ex = Excel.createExcel();
  final sh = ex['products'];
  sh.appendRow(const [
    TextCellValue('sku'),
    TextCellValue('name'),
    TextCellValue('category'),
    TextCellValue('default_sale_price'),
    TextCellValue('last_purchase_price'),
    TextCellValue('last_purchase_date'),
    TextCellValue('stock'),
  ]);

  for (final r in rows) {
    sh.appendRow([
      TextCellValue((r['sku'] ?? '').toString()),
      TextCellValue((r['name'] ?? '').toString()),
      TextCellValue((r['category'] ?? '').toString()),
      DoubleCellValue(((r['default_sale_price'] as num?) ?? 0).toDouble()),
      DoubleCellValue(((r['last_purchase_price'] as num?) ?? 0).toDouble()),
      TextCellValue((r['last_purchase_date'] ?? '').toString()),
      DoubleCellValue(((r['stock'] as num?) ?? 0).toDouble()),
    ]);
  }

  final file = await _saveToDownloads(_excelToBytes(ex), 'productos.xlsx');
  return file;
}

Future<File> exportClientsXlsx() async {
  final db = await openAppDb();
  final rows = await db.query('customers');
  final ex = Excel.createExcel();
  final sh = ex['customers'];
  sh.appendRow(const [
    TextCellValue('phone_id'),
    TextCellValue('name'),
    TextCellValue('address'),
  ]);
  for (final r in rows) {
    sh.appendRow([
      TextCellValue((r['phone'] ?? '').toString()),
      TextCellValue((r['name'] ?? '').toString()),
      TextCellValue((r['address'] ?? '').toString()),
    ]);
  }
  return _saveToDownloads(_excelToBytes(ex), 'clientes.xlsx');
}

Future<File> exportSuppliersXlsx() async {
  final db = await openAppDb();
  final rows = await db.query('suppliers');
  final ex = Excel.createExcel();
  final sh = ex['suppliers'];
  sh.appendRow(const [
    TextCellValue('id'),
    TextCellValue('name'),
    TextCellValue('phone'),
    TextCellValue('address'),
  ]);
  for (final r in rows) {
    sh.appendRow([
      TextCellValue((r['id'] ?? '').toString()),
      TextCellValue((r['name'] ?? '').toString()),
      TextCellValue((r['phone'] ?? '').toString()),
      TextCellValue((r['address'] ?? '').toString()),
    ]);
  }
  return _saveToDownloads(_excelToBytes(ex), 'proveedores.xlsx');
}

Future<File> exportSalesXlsx() async {
  final db = await openAppDb();
  final sales = await db.query('sales', orderBy: 'date DESC');
  final items = await db.query('sale_items');

  final ex = Excel.createExcel();
  final shSales = ex['sales'];
  final shItems = ex['sale_items'];

  shSales.appendRow(const [
    TextCellValue('sale_id'),
    TextCellValue('date'),
    TextCellValue('customer_phone'),
    TextCellValue('payment_method'),
    TextCellValue('place'),
    TextCellValue('shipping_cost'),
    TextCellValue('discount'),
  ]);
  for (final s in sales) {
    shSales.appendRow([
      IntCellValue((s['id'] as int?) ?? 0),
      TextCellValue((s['date'] ?? '').toString()),
      TextCellValue((s['customer_phone'] ?? '').toString()),
      TextCellValue((s['payment_method'] ?? '').toString()),
      TextCellValue((s['place'] ?? '').toString()),
      DoubleCellValue(((s['shipping_cost'] as num?) ?? 0).toDouble()),
      DoubleCellValue(((s['discount'] as num?) ?? 0).toDouble()),
    ]);
  }

  shItems.appendRow(const [
    TextCellValue('sale_id'),
    TextCellValue('product_sku'),
    TextCellValue('product_name'),
    TextCellValue('quantity'),
    TextCellValue('unit_price'),
  ]);
  for (final it in items) {
    shItems.appendRow([
      IntCellValue((it['sale_id'] as int?) ?? 0),
      TextCellValue((it['product_sku'] ?? '').toString()),
      TextCellValue((it['product_name'] ?? '').toString()),
      DoubleCellValue(((it['quantity'] as num?) ?? 0).toDouble()),
      DoubleCellValue(((it['unit_price'] as num?) ?? 0).toDouble()),
    ]);
  }

  return _saveToDownloads(_excelToBytes(ex), 'ventas.xlsx');
}

Future<File> exportPurchasesXlsx() async {
  final db = await openAppDb();
  final purchases = await db.query('purchases', orderBy: 'date DESC');
  final items = await db.query('purchase_items');

  final ex = Excel.createExcel();
  final shP = ex['purchases'];
  final shI = ex['purchase_items'];

  shP.appendRow(const [
    TextCellValue('purchase_id'),
    TextCellValue('folio'),
    TextCellValue('date'),
    TextCellValue('supplier_id'),
  ]);
  for (final p in purchases) {
    shP.appendRow([
      IntCellValue((p['id'] as int?) ?? 0),
      TextCellValue((p['folio'] ?? '').toString()),
      TextCellValue((p['date'] ?? '').toString()),
      TextCellValue((p['supplier_id'] ?? '').toString()),
    ]);
  }

  shI.appendRow(const [
    TextCellValue('purchase_id'),
    TextCellValue('product_sku'),
    TextCellValue('product_name'),
    TextCellValue('quantity'),
    TextCellValue('unit_cost'),
  ]);
  for (final it in items) {
    shI.appendRow([
      IntCellValue((it['purchase_id'] as int?) ?? 0),
      TextCellValue((it['product_sku'] ?? '').toString()),
      TextCellValue((it['product_name'] ?? '').toString()),
      DoubleCellValue(((it['quantity'] as num?) ?? 0).toDouble()),
      DoubleCellValue(((it['unit_cost'] as num?) ?? 0).toDouble()),
    ]);
  }

  return _saveToDownloads(_excelToBytes(ex), 'compras.xlsx');
}

// -------------------- IMPORT --------------------

Future<void> importProductsXlsx(Uint8List bytes) async {
  final repo = ProductRepository();
  final ex = Excel.decodeBytes(bytes);
  final sh = ex['products'];
  // cabeceras en fila 0
  for (int r = 1; r < sh.rows.length; r++) {
    final row = sh.row(r);
    if (row.isEmpty) continue;
    final sku = (row[0]?.value?.toString() ?? '').trim();
    if (sku.isEmpty) continue;
    await repo.upsert({
      'sku': sku,
      'name': row[1]?.value?.toString() ?? '',
      'category': row[2]?.value?.toString() ?? 'general',
      'default_sale_price': double.tryParse(row[3]?.value?.toString() ?? '') ?? 0,
      'last_purchase_price': double.tryParse(row[4]?.value?.toString() ?? '') ?? null,
      'last_purchase_date': row[5]?.value?.toString(),
      'stock': double.tryParse(row[6]?.value?.toString() ?? '') ?? 0,
    });
  }
}

Future<void> importClientsXlsx(Uint8List bytes) async {
  final db = await openAppDb();
  final ex = Excel.decodeBytes(bytes);
  final sh = ex['customers'];
  for (int r = 1; r < sh.rows.length; r++) {
    final row = sh.row(r);
    if (row.isEmpty) continue;
    final phone = (row[0]?.value?.toString() ?? '').trim();
    if (phone.isEmpty) continue;
    await db.insert('customers', {
      'phone': phone,
      'name': row[1]?.value?.toString() ?? '',
      'address': row[2]?.value?.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<void> importSuppliersXlsx(Uint8List bytes) async {
  final db = await openAppDb();
  final ex = Excel.decodeBytes(bytes);
  final sh = ex['suppliers'];
  for (int r = 1; r < sh.rows.length; r++) {
    final row = sh.row(r);
    if (row.isEmpty) continue;
    final id = (row[0]?.value?.toString() ?? '').trim();
    if (id.isEmpty) continue;
    await db.insert('suppliers', {
      'id': id,
      'name': row[1]?.value?.toString() ?? '',
      'phone': row[2]?.value?.toString(),
      'address': row[3]?.value?.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}