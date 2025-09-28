import 'dart:io';
import 'package:xml/xml.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';
import 'package:path_provider/path_provider.dart';

Future<Directory> _downloads() async {
  final dir = await getExternalStorageDirectory();
  return dir ?? await getApplicationDocumentsDirectory();
}

Future<File> exportClientsXml() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('customers');
  final builder = XmlBuilder()..processing('xml', 'version="1.0"');
  builder.element('customers', nest: (){
    for (final r in rows) {
      builder.element('customer', nest: (){
        builder.element('phone', nest: r['phone'] ?? '');
        builder.element('name', nest: r['name'] ?? '');
        builder.element('address', nest: r['address'] ?? '');
      });
    }
  });
  final file = File('${(await _downloads()).path}/clientes.xml');
  return file.writeAsString(builder.buildDocument().toXmlString(pretty: true));
}

Future<File> exportProductsXml() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('products');
  final b = XmlBuilder()..processing('xml', 'version="1.0"');
  b.element('products', nest: (){
    for (final r in rows) {
      b.element('product', nest: (){
        b.element('id', nest: r['id']?.toString() ?? '');
        b.element('sku', nest: r['sku'] ?? '');
        b.element('name', nest: r['name'] ?? '');
        b.element('category', nest: r['category'] ?? '');
        b.element('stock', nest: r['stock']?.toString() ?? '0');
        b.element('last_purchase_price', nest: r['last_purchase_price']?.toString() ?? '0');
        b.element('last_purchase_date', nest: r['last_purchase_date'] ?? '');
      });
    }
  });
  final file = File('${(await _downloads()).path}/productos.xml');
  return file.writeAsString(b.buildDocument().toXmlString(pretty: true));
}

Future<File> exportSuppliersXml() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('suppliers');
  final b = XmlBuilder()..processing('xml', 'version="1.0"');
  b.element('suppliers', nest: (){
    for (final r in rows) {
      b.element('supplier', nest: (){
        b.element('id', nest: r['id']?.toString() ?? '');
        b.element('name', nest: r['name'] ?? '');
        b.element('phone', nest: r['phone'] ?? '');
        b.element('address', nest: r['address'] ?? '');
      });
    }
  });
  final file = File('${(await _downloads()).path}/proveedores.xml');
  return file.writeAsString(b.buildDocument().toXmlString(pretty: true));
}

Future<File> exportSalesXml() async {
  final db = await DatabaseHelper.instance.db;
  final sales = await db.query('sales');
  final items = await db.query('sale_items');
  final itemsBySale = <int, List<Map<String, Object?>>>{};
  for (final it in items) {
    final sid = it['sale_id'] as int;
    itemsBySale.putIfAbsent(sid, ()=>[]).add(it);
  }
  final b = XmlBuilder()..processing('xml', 'version="1.0"');
  b.element('sales', nest: (){
    for (final s in sales) {
      b.element('sale', nest: (){
        b.element('id', nest: s['id'].toString());
        b.element('customer_phone', nest: s['customer_phone'] ?? '');
        b.element('payment_method', nest: s['payment_method'] ?? '');
        b.element('place', nest: s['place'] ?? '');
        b.element('shipping_cost', nest: s['shipping_cost']?.toString() ?? '0');
        b.element('discount', nest: s['discount']?.toString() ?? '0');
        b.element('date', nest: s['date'] ?? '');
        b.element('items', nest: (){
          for (final it in itemsBySale[s['id']] ?? const []) {
            b.element('item', nest: (){
              b.element('product_id', nest: it['product_id'].toString());
              b.element('quantity', nest: it['quantity'].toString());
              b.element('unit_price', nest: it['unit_price'].toString());
            });
          }
        });
      });
    }
  });
  final file = File('${(await _downloads()).path}/ventas.xml');
  return file.writeAsString(b.buildDocument().toXmlString(pretty: true));
}

Future<File> exportPurchasesXml() async {
  final db = await DatabaseHelper.instance.db;
  final purchases = await db.query('purchases');
  final items = await db.query('purchase_items');
  final itemsBy = <int, List<Map<String,Object?>>>{};
  for (final it in items) {
    final pid = it['purchase_id'] as int;
    itemsBy.putIfAbsent(pid, ()=>[]).add(it);
  }
  final b = XmlBuilder()..processing('xml', 'version="1.0"');
  b.element('purchases', nest: (){
    for (final p in purchases) {
      b.element('purchase', nest: (){
        b.element('id', nest: p['id'].toString());
        b.element('folio', nest: p['folio'] ?? '');
        b.element('supplier_id', nest: p['supplier_id'].toString());
        b.element('date', nest: p['date'] ?? '');
        b.element('items', nest: (){
          for (final it in itemsBy[p['id']] ?? const []) {
            b.element('item', nest: (){
              b.element('product_id', nest: it['product_id'].toString());
              b.element('quantity', nest: it['quantity'].toString());
              b.element('unit_cost', nest: it['unit_cost'].toString());
            });
          }
        });
      });
    }
  });
  final file = File('${(await _downloads()).path}/compras.xml');
  return file.writeAsString(b.buildDocument().toXmlString(pretty: true));
}

Future<void> importSuppliersXml(File file) async {
  final db = await DatabaseHelper.instance.db;
  final doc = XmlDocument.parse(await file.readAsString());
  final batch = db.batch();
  for (final x in doc.findAllElements('supplier')) {
    final name = x.getElement('name')?.innerText ?? '';
    final phone = x.getElement('phone')?.innerText ?? '';
    final address = x.getElement('address')?.innerText ?? '';
    if (name.isEmpty) continue;
    batch.insert('suppliers', {'name': name, 'phone': phone, 'address': address},
      conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

Future<void> importClientsXml(File file) async {
  final db = await DatabaseHelper.instance.db;
  final doc = XmlDocument.parse(await file.readAsString());
  final batch = db.batch();
  for (final c in doc.findAllElements('customer')) {
    final phone = c.getElement('phone')?.innerText ?? '';
    if (phone.isEmpty) continue;
    batch.insert('customers', {
      'phone': phone,
      'name': c.getElement('name')?.innerText ?? '',
      'address': c.getElement('address')?.innerText ?? '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

Future<void> importProductsXml(File file) async {
  final db = await DatabaseHelper.instance.db;
  final doc = XmlDocument.parse(await file.readAsString());
  final batch = db.batch();
  for (final p in doc.findAllElements('product')) {
    final sku = p.getElement('sku')?.innerText ?? '';
    final name = p.getElement('name')?.innerText ?? '';
    if (name.isEmpty) continue;
    final map = {
      'sku': sku.isEmpty ? null : sku,
      'name': name,
      'category': p.getElement('category')?.innerText ?? '',
      'stock': int.tryParse(p.getElement('stock')?.innerText ?? '0') ?? 0,
      'last_purchase_price': double.tryParse(p.getElement('last_purchase_price')?.innerText ?? '0') ?? 0.0,
      'last_purchase_date': p.getElement('last_purchase_date')?.innerText,
    };
    batch.insert('products', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}
