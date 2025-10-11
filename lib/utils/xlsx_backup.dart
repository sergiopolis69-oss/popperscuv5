import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:path/path.dart' as p;

import '../repositories/product_repository.dart';
import '../repositories/customer_repository.dart';
import '../repositories/supplier_repository.dart';
import '../repositories/sales_repository.dart';
import '../repositories/purchase_repository.dart';

final _prodRepo = ProductRepository();
final _custRepo = CustomerRepository();
final _suppRepo = SupplierRepository();
final _salesRepo = SalesRepository();
final _purchRepo = PurchaseRepository();

String _stamp() {
  final now = DateTime.now();
  return '${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}_${now.hour.toString().padLeft(2,'0')}${now.minute.toString().padLeft(2,'0')}';
}

// Helpers para escribir celdas con el tipo correcto:
CellValue _txt(Object? v) => TextCellValue((v ?? '').toString());
CellValue _num(num? v) => v == null ? TextCellValue('') : DoubleCellValue(v.toDouble());

// ==================== EXPORT ====================

Future<String> exportProductsXlsx() async {
  final excel = Excel.createExcel();
  final sh = excel['products'];

  sh.appendRow(<CellValue>[
    TextCellValue('sku'),
    TextCellValue('name'),
    TextCellValue('category'),
    TextCellValue('default_sale_price'),
    TextCellValue('last_purchase_price'),
    TextCellValue('last_purchase_date'),
    TextCellValue('stock'),
  ]);

  final rows = await _prodRepo.all(); // [{sku,name,category,default_sale_price,last_purchase_price,last_purchase_date,stock}]
  for (final r in rows) {
    sh.appendRow(<CellValue>[
      _txt(r['sku']),
      _txt(r['name']),
      _txt(r['category']),
      _num(r['default_sale_price'] as num?),
      _num(r['last_purchase_price'] as num?),
      _txt(r['last_purchase_date']),
      _num(r['stock'] as num?),
    ]);
  }

  final data = Uint8List.fromList(excel.encode()!);
  final fileName = 'productos_${_stamp()}';
  final path = await FileSaver.instance.saveFile(
    name: fileName,
    bytes: data,
    ext: 'xlsx',
    mimeType: MimeType.other, // Portable
  );
  return (path is String) ? path : path.toString();
}

Future<String> exportClientsXlsx() async {
  final excel = Excel.createExcel();
  final sh = excel['clients'];

  sh.appendRow(<CellValue>[
    TextCellValue('phone_id'),
    TextCellValue('name'),
    TextCellValue('address'),
  ]);

  final rows = await _custRepo.all(); // [{phone,name,address}]
  for (final r in rows) {
    sh.appendRow(<CellValue>[
      _txt(r['phone']),
      _txt(r['name']),
      _txt(r['address']),
    ]);
  }

  final data = Uint8List.fromList(excel.encode()!);
  final path = await FileSaver.instance.saveFile(
    name: 'clientes_${_stamp()}',
    bytes: data,
    ext: 'xlsx',
    mimeType: MimeType.other,
  );
  return (path is String) ? path : path.toString();
}

Future<String> exportSuppliersXlsx() async {
  final excel = Excel.createExcel();
  final sh = excel['suppliers'];

  sh.appendRow(<CellValue>[
    TextCellValue('id'),
    TextCellValue('name'),
    TextCellValue('phone'),
    TextCellValue('address'),
  ]);

  final rows = await _suppRepo.all(); // [{id,name,phone,address}]
  for (final r in rows) {
    sh.appendRow(<CellValue>[
      _txt(r['id']),
      _txt(r['name']),
      _txt(r['phone']),
      _txt(r['address']),
    ]);
  }

  final data = Uint8List.fromList(excel.encode()!);
  final path = await FileSaver.instance.saveFile(
    name: 'proveedores_${_stamp()}',
    bytes: data,
    ext: 'xlsx',
    mimeType: MimeType.other,
  );
  return (path is String) ? path : path.toString();
}

Future<String> exportSalesXlsx() async {
  // Hoja master de ventas + hoja items con SKU
  final excel = Excel.createExcel();
  final shSales = excel['sales'];
  final shItems = excel['sale_items'];

  shSales.appendRow(<CellValue>[
    TextCellValue('sale_id'),
    TextCellValue('date'),
    TextCellValue('customer_phone'),
    TextCellValue('payment_method'),
    TextCellValue('place'),
    TextCellValue('shipping_cost'),
    TextCellValue('discount'),
  ]);

  shItems.appendRow(<CellValue>[
    TextCellValue('sale_id'),
    TextCellValue('product_sku'),
    TextCellValue('product_name'),
    TextCellValue('quantity'),
    TextCellValue('unit_price'),
  ]);

  final sales = await _salesRepo.all(); // [{id,date,customer_phone,payment_method,place,shipping,discount}]
  for (final s in sales) {
    shSales.appendRow(<CellValue>[
      _txt(s['id']),
      _txt(s['date']),
      _txt(s['customer_phone']),
      _txt(s['payment_method']),
      _txt(s['place']),
      _num(s['shipping_cost'] as num?),
      _num(s['discount'] as num?),
    ]);
    final items = await _salesRepo.itemsBySaleId(s['id']); // [{product_sku,product_name,quantity,unit_price}]
    for (final it in items) {
      shItems.appendRow(<CellValue>[
        _txt(s['id']),
        _txt(it['product_sku']),
        _txt(it['product_name']),
        _num(it['quantity'] as num?),
        _num(it['unit_price'] as num?),
      ]);
    }
  }

  final data = Uint8List.fromList(excel.encode()!);
  final path = await FileSaver.instance.saveFile(
    name: 'ventas_${_stamp()}',
    bytes: data,
    ext: 'xlsx',
    mimeType: MimeType.other,
  );
  return (path is String) ? path : path.toString();
}

Future<String> exportPurchasesXlsx() async {
  // Hoja master de compras + hoja items con SKU
  final excel = Excel.createExcel();
  final shP = excel['purchases'];
  final shI = excel['purchase_items'];

  shP.appendRow(<CellValue>[
    TextCellValue('purchase_id'),
    TextCellValue('folio'),
    TextCellValue('date'),
    TextCellValue('supplier_id'),
  ]);

  shI.appendRow(<CellValue>[
    TextCellValue('purchase_id'),
    TextCellValue('product_sku'),
    TextCellValue('product_name'),
    TextCellValue('quantity'),
    TextCellValue('unit_cost'),
  ]);

  final purchases = await _purchRepo.all(); // [{id,folio,date,supplier_id}]
  for (final pRow in purchases) {
    shP.appendRow(<CellValue>[
      _txt(pRow['id']),
      _txt(pRow['folio']),
      _txt(pRow['date']),
      _txt(pRow['supplier_id']),
    ]);

    final items = await _purchRepo.itemsByPurchaseId(pRow['id']); // [{product_sku,product_name,quantity,unit_cost}]
    for (final it in items) {
      shI.appendRow(<CellValue>[
        _txt(pRow['id']),
        _txt(it['product_sku']),
        _txt(it['product_name']),
        _num(it['quantity'] as num?),
        _num(it['unit_cost'] as num?),
      ]);
    }
  }

  final data = Uint8List.fromList(excel.encode()!);
  final path = await FileSaver.instance.saveFile(
    name: 'compras_${_stamp()}',
    bytes: data,
    ext: 'xlsx',
    mimeType: MimeType.other,
  );
  return (path is String) ? path : path.toString();
}

// ==================== IMPORT ====================
// Reciben bytes del archivo XLSX y crean/actualizan registros.
// Ajusta la lógica interna a tus repos si cambia el nombre de columnas.

Future<void> importProductsXlsx(Uint8List bytes) async {
  final excel = Excel.decodeBytes(bytes);
  final sh = excel['products'];
  final rows = sh.rows;
  if (rows.isEmpty) return;
  // header en fila 0
  for (int i=1; i<rows.length; i++) {
    final r = rows[i];
    String sku = (r[0]?.value ?? '').toString();
    if (sku.isEmpty) continue; // SKU obligatorio
    await _prodRepo.upsert({
      'sku': sku,
      'name': (r[1]?.value ?? '').toString(),
      'category': (r[2]?.value ?? '').toString(),
      'default_sale_price': num.tryParse((r[3]?.value ?? '').toString()) ?? 0,
      'last_purchase_price': num.tryParse((r[4]?.value ?? '').toString()) ?? 0,
      'last_purchase_date': (r[5]?.value ?? '').toString(),
      'stock': num.tryParse((r[6]?.value ?? '').toString()) ?? 0,
    });
  }
}

Future<void> importClientsXlsx(Uint8List bytes) async {
  final excel = Excel.decodeBytes(bytes);
  final sh = excel['clients'];
  final rows = sh.rows;
  if (rows.isEmpty) return;
  for (int i=1; i<rows.length; i++) {
    final r = rows[i];
    final phone = (r[0]?.value ?? '').toString();
    if (phone.isEmpty) continue;
    await _custRepo.upsert({
      'phone': phone,
      'name': (r[1]?.value ?? '').toString(),
      'address': (r[2]?.value ?? '').toString(),
    });
  }
}

Future<void> importSuppliersXlsx(Uint8List bytes) async {
  final excel = Excel.decodeBytes(bytes);
  final sh = excel['suppliers'];
  final rows = sh.rows;
  if (rows.isEmpty) return;
  for (int i=1; i<rows.length; i++) {
    final r = rows[i];
    final id = (r[0]?.value ?? '').toString();
    if (id.isEmpty) continue;
    await _suppRepo.upsert({
      'id': id,
      'name': (r[1]?.value ?? '').toString(),
      'phone': (r[2]?.value ?? '').toString(),
      'address': (r[3]?.value ?? '').toString(),
    });
  }
}

Future<void> importSalesXlsx(Uint8List bytes) async {
  final excel = Excel.decodeBytes(bytes);
  final shSales = excel['sales'];
  final shItems = excel['sale_items'];
  if (shSales.rows.isEmpty) return;

  // Insertar ventas
  for (int i=1; i<shSales.rows.length; i++) {
    final r = shSales.rows[i];
    final id = (r[0]?.value ?? '').toString();
    if (id.isEmpty) continue;
    await _salesRepo.upsert({
      'id': id,
      'date': (r[1]?.value ?? '').toString(),
      'customer_phone': (r[2]?.value ?? '').toString(),
      'payment_method': (r[3]?.value ?? '').toString(),
      'place': (r[4]?.value ?? '').toString(),
      'shipping_cost': num.tryParse((r[5]?.value ?? '').toString()) ?? 0,
      'discount': num.tryParse((r[6]?.value ?? '').toString()) ?? 0,
    });
  }

  // Insertar items
  for (int i=1; i<shItems.rows.length; i++) {
    final r = shItems.rows[i];
    final saleId = (r[0]?.value ?? '').toString();
    final sku    = (r[1]?.value ?? '').toString();
    if (saleId.isEmpty || sku.isEmpty) continue;

    // Si el SKU no existe, lo ignoramos por seguridad:
    final p = await _prodRepo.findBySku(sku);
    if (p == null) continue;

    await _salesRepo.upsertItem({
      'sale_id': saleId,
      'product_sku': sku,
      'product_name': (r[2]?.value ?? '').toString(),
      'quantity': num.tryParse((r[3]?.value ?? '').toString()) ?? 0,
      'unit_price': num.tryParse((r[4]?.value ?? '').toString()) ?? 0,
    });
  }
}

Future<void> importPurchasesXlsx(Uint8List bytes) async {
  final excel = Excel.decodeBytes(bytes);
  final shP = excel['purchases'];
  final shI = excel['purchase_items'];
  if (shP.rows.isEmpty) return;

  for (int i=1; i<shP.rows.length; i++) {
    final r = shP.rows[i];
    final id = (r[0]?.value ?? '').toString();
    if (id.isEmpty) continue;
    await _purchRepo.upsert({
      'id': id,
      'folio': (r[1]?.value ?? '').toString(),
      'date': (r[2]?.value ?? '').toString(),
      'supplier_id': (r[3]?.value ?? '').toString(),
    });
  }

  for (int i=1; i<shI.rows.length; i++) {
    final r = shI.rows[i];
    final purchaseId = (r[0]?.value ?? '').toString();
    final sku        = (r[1]?.value ?? '').toString();
    if (purchaseId.isEmpty || sku.isEmpty) continue;

    final p = await _prodRepo.findBySku(sku);
    if (p == null) continue;

    await _purchRepo.upsertItem({
      'purchase_id': purchaseId,
      'product_sku': sku,
      'product_name': (r[2]?.value ?? '').toString(),
      'quantity': num.tryParse((r[3]?.value ?? '').toString()) ?? 0,
      'unit_cost': num.tryParse((r[4]?.value ?? '').toString()) ?? 0,
    });
  }
}
