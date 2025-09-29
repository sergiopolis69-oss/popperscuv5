import 'dart:io';
import 'package:xml/xml.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_saver/file_saver.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

// ============ EXPORTS ============

Future<void> exportClientsXml() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('customers');
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0"');
  builder.element('customers', nest: () {
    for (final r in rows) {
      builder.element('customer', nest: () {
        builder.element('phone', nest: r['phone']);
        builder.element('name', nest: r['name']);
        builder.element('address', nest: r['address']);
      });
    }
  });
  final xml = builder.buildDocument().toXmlString(pretty: true);
  final dir = await getDownloadsDirectory();
  final file = File('${dir!.path}/clientes.xml');
  await file.writeAsString(xml);
  await FileSaver.instance.saveFile(name: 'clientes', bytes: xml.codeUnits, ext: 'xml', mimeType: MimeType.text);
}

Future<void> exportProductsXml() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('products');
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0"');
  builder.element('products', nest: () {
    for (final r in rows) {
      builder.element('product', nest: () {
        builder.element('id', nest: r['id']);
        builder.element('sku', nest: r['sku']);
        builder.element('name', nest: r['name']);
        builder.element('category', nest: r['category']);
        builder.element('stock', nest: r['stock']);
        builder.element('last_purchase_price', nest: r['last_purchase_price']);
        builder.element('last_purchase_date', nest: r['last_purchase_date']);
        builder.element('default_sale_price', nest: r['default_sale_price']);
        builder.element('initial_cost', nest: r['initial_cost']);
      });
    }
  });
  final xml = builder.buildDocument().toXmlString(pretty: true);
  final dir = await getDownloadsDirectory();
  final file = File('${dir!.path}/productos.xml');
  await file.writeAsString(xml);
  await FileSaver.instance.saveFile(name: 'productos', bytes: xml.codeUnits, ext: 'xml', mimeType: MimeType.text);
}

Future<void> exportSuppliersXml() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('suppliers');
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0"');
  builder.element('suppliers', nest: () {
    for (final r in rows) {
      builder.element('supplier', nest: () {
        builder.element('id', nest: r['id']);
        builder.element('name', nest: r['name']);
        builder.element('phone', nest: r['phone']);
        builder.element('address', nest: r['address']);
      });
    }
  });
  final xml = builder.buildDocument().toXmlString(pretty: true);
  final dir = await getDownloadsDirectory();
  final file = File('${dir!.path}/proveedores.xml');
  await file.writeAsString(xml);
  await FileSaver.instance.saveFile(name: 'proveedores', bytes: xml.codeUnits, ext: 'xml', mimeType: MimeType.text);
}

Future<void> exportSalesXml() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('sales');
  final items = await db.query('sale_items');
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0"');
  builder.element('sales', nest: () {
    for (final r in rows) {
      builder.element('sale', nest: () {
        builder.element('id', nest: r['id']);
        builder.element('customer_phone', nest: r['customer_phone']);
        builder.element('payment_method', nest: r['payment_method']);
        builder.element('place', nest: r['place']);
        builder.element('shipping_cost', nest: r['shipping_cost']);
        builder.element('discount', nest: r['discount']);
        builder.element('date', nest: r['date']);
        builder.element('items', nest: () {
          for (final it in items.where((e) => e['sale_id'] == r['id'])) {
            builder.element('item', nest: () {
              builder.element('product_id', nest: it['product_id']);
              builder.element('quantity', nest: it['quantity']);
              builder.element('unit_price', nest: it['unit_price']);
            });
          }
        });
      });
    }
  });
  final xml = builder.buildDocument().toXmlString(pretty: true);
  final dir = await getDownloadsDirectory();
  final file = File('${dir!.path}/ventas.xml');
  await file.writeAsString(xml);
  await FileSaver.instance.saveFile(name: 'ventas', bytes: xml.codeUnits, ext: 'xml', mimeType: MimeType.text);
}

Future<void> exportPurchasesXml() async {
  final db = await DatabaseHelper.instance.db;
  final rows = await db.query('purchases');
  final items = await db.query('purchase_items');
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0"');
  builder.element('purchases', nest: () {
    for (final r in rows) {
      builder.element('purchase', nest: () {
        builder.element('id', nest: r['id']);
        builder.element('folio', nest: r['folio']);
        builder.element('supplier_id', nest: r['supplier_id']);
        builder.element('date', nest: r['date']);
        builder.element('items', nest: () {
          for (final it in items.where((e) => e['purchase_id'] == r['id'])) {
            builder.element('item', nest: () {
              builder.element('product_id', nest: it['product_id']);
              builder.element('quantity', nest: it['quantity']);
              builder.element('unit_cost', nest: it['unit_cost']);
            });
          }
        });
      });
    }
  });
  final xml = builder.buildDocument().toXmlString(pretty: true);
  final dir = await getDownloadsDirectory();
  final file = File('${dir!.path}/compras.xml');
  await file.writeAsString(xml);
  await FileSaver.instance.saveFile(name: 'compras', bytes: xml.codeUnits, ext: 'xml', mimeType: MimeType.text);
}

// ============ IMPORTS ============

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
    final name = p.getElement('name')?.innerText ?? '';
    if (name.isEmpty) continue;
    batch.insert('products', {
      'sku': p.getElement('sku')?.innerText,
      'name': name,
      'category': p.getElement('category')?.innerText ?? '',
      'stock': int.tryParse(p.getElement('stock')?.innerText ?? '0') ?? 0,
      'last_purchase_price': double.tryParse(p.getElement('last_purchase_price')?.innerText ?? '0') ?? 0.0,
      'last_purchase_date': p.getElement('last_purchase_date')?.innerText,
      'default_sale_price': double.tryParse(p.getElement('default_sale_price')?.innerText ?? '0') ?? 0.0,
      'initial_cost': double.tryParse(p.getElement('initial_cost')?.innerText ?? '0') ?? 0.0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}

Future<void> importSuppliersXml(File file) async {
  final db = await DatabaseHelper.instance.db;
  final doc = XmlDocument.parse(await file.readAsString());
  final batch = db.batch();
  for (final x in doc.findAllElements('supplier')) {
    final name = x.getElement('name')?.innerText ?? '';
    if (name.isEmpty) continue;
    batch.insert('suppliers', {
      'id': int.tryParse(x.getElement('id')?.innerText ?? ''),
      'name': name,
      'phone': x.getElement('phone')?.innerText ?? '',
      'address': x.getElement('address')?.innerText ?? '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await batch.commit(noResult: true);
}