
import 'dart:typed_data';
import 'dart:io';
import 'package:xml/xml.dart' as xml;
import 'package:file_saver/file_saver.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import '../data/database.dart';

class XmlBackup {
  static Future<Uint8List> _buildXmlBytes() async {
    final db = await AppDatabase().db();
    final doc = xml.XmlBuilder();

    final products = await db.query('products');
    final customers = await db.query('customers');
    final purchases = await db.query('purchases');
    final purchaseItems = await db.query('purchase_items');
    final sales = await db.query('sales');
    final saleItems = await db.query('sale_items');

    doc.processing('xml', 'version="1.0" encoding="UTF-8"');
    doc.element('pdv', nest: () {
      void addTable(String name, List<Map<String, Object?>> rows){
        doc.element(name, nest: () {
          for (final r in rows){
            doc.element('row', nest: () {
              r.forEach((k,v){
                doc.element(k, nest: v?.toString() ?? '');
              });
            });
          }
        });
      }
      addTable('products', products);
      addTable('customers', customers);
      addTable('purchases', purchases);
      addTable('purchase_items', purchaseItems);
      addTable('sales', sales);
      addTable('sale_items', saleItems);
    });

    final xmlStr = doc.buildDocument().toXmlString(pretty: true, indent: '  ');
    return Uint8List.fromList(xmlStr.codeUnits);
  }

  static Future<String?> exportAll() async {
    final bytes = await _buildXmlBytes();
    final savedPath = await FileSaver.instance.saveFile(
      name: 'pdv_backup.xml',
      bytes: bytes,
      mimeType: MimeType.other,
    );
    return savedPath;
  }

  static Future<void> importAllWithPicker() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xml'],
      withData: true,
    );
    if (res == null) return;
    final file = res.files.single;
    final bytes = file.bytes;
    final path = file.path;
    final text = bytes != null
        ? String.fromCharCodes(bytes)
        : (path != null ? await File(path).readAsString() : null);
    if (text == null) return;

    final db = await AppDatabase().db();
    final doc = xml.XmlDocument.parse(text);
    await db.transaction((txn) async {
      for (final table in ['products','customers','purchases','purchase_items','sales','sale_items']){
        final elements = doc.findAllElements(table);
        if (elements.isEmpty) continue;
        final t = elements.first;
        for (final row in t.findAllElements('row')){
          final map = <String, Object?>{};
          for (final c in row.children.whereType<xml.XmlElement>()){
            map[c.name.toString()] = c.innerText.isEmpty ? null : c.innerText;
          }
          await txn.insert(table, map, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }
}
