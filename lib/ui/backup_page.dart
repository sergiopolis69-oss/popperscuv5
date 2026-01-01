// lib/ui/backup_page.dart
import 'dart:typed_data';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:popperscuv5/utils/xlsx_io.dart' as xio;
import 'package:popperscuv5/data/database.dart' as appdb;
import 'package:sqflite/sqflite.dart';

// XLSX builder (excel)
import 'package:excel/excel.dart' as ex;

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  // snackbars locales
  void showOk(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  void showErr(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red.shade700, content: Text(msg)),
      );

  Future<Database> _db() => appdb.getDb();
  Future<String> _dbPath() async => (await _db()).path;

  // ====== EXPORTAR XLSX ======================================================
  Future<void> _export({
    required String fileName,
    required Future<Uint8List> Function() builder,
  }) async {
    try {
      final bytes = await builder(); // construye el XLSX en memoria

      final savedUriOrPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar $fileName',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes, // <- CLAVE
      );

      if (savedUriOrPath == null) return; // usuario canceló
      showOk('Exportado a:\n$savedUriOrPath');
    } catch (e, st) {
      if (kDebugMode) print(st);
      showErr('Error al exportar: $e');
    }
  }

  // ====== IMPORTAR XLSX ======================================================
  Future<void> _pickAndImport({
    required String label,
    required Future<void> Function(Uint8List) importer,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
      if (result == null || result.files.single.bytes == null) {
        showErr('No seleccionaste archivo.');
        return;
      }
      await importer(result.files.single.bytes!);
      showOk('Importación de $label completa');
    } catch (e) {
      showErr('Error importando $label: $e');
    }
  }

  // ====== RESPALDO / RESTAURAR BD ============================================
  Future<void> _backupDb() async {
    try {
      final path = await _dbPath();
      final bytes = await File(path).readAsBytes();

      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar respaldo de BD',
        fileName: 'pdv.db',
        type: FileType.custom,
        allowedExtensions: const ['db'],
        bytes: bytes,
      );
      if (saved == null) return;
      showOk('BD guardada en:\n$saved');
    } catch (e) {
      showErr('Error al respaldar BD: $e');
    }
  }

  Future<void> _restoreDb() async {
    try {
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (pick == null || pick.files.single.bytes == null) {
        showErr('No seleccionaste archivo .db');
        return;
      }
      final name = (pick.files.single.name).toLowerCase();
      if (!name.endsWith('.db')) {
        showErr('Selecciona un archivo con extensión .db');
        return;
      }
      final dest = await _dbPath();
      await File(dest).writeAsBytes(pick.files.single.bytes!, flush: true);
      showOk('BD restaurada. Reinicia la app para ver los cambios.');
    } catch (e) {
      showErr('Error al restaurar BD: $e');
    }
  }

  // ==========================================================================
  // NUEVO: XLSX de Ventas con Artículos + Utilidad por SKU (en la MISMA hoja)
  // ==========================================================================
  double _toDouble(Object? v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  int _toInt(Object? v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  Future<Uint8List> _buildSalesWithItemsAndProfitXlsxBytes() async {
    final db = await _db();

    // Trae ventas + cliente (si existe)
    final sales = await db.rawQuery('''
      SELECT
        s.id,
        s.date,
        s.customer_phone,
        COALESCE(c.name,'') AS customer_name,
        s.payment_method,
        s.place,
        COALESCE(s.shipping_cost,0) AS shipping_cost,
        COALESCE(s.discount,0) AS discount
      FROM sales s
      LEFT JOIN customers c ON c.phone = s.customer_phone
      ORDER BY s.date DESC, s.id DESC
    ''');

    // Trae items + producto (SKU/Nombre/Costo actual)
    final items = await db.rawQuery('''
      SELECT
        si.sale_id,
        si.product_id,
        si.quantity,
        si.unit_price,
        COALESCE(p.sku,'') AS sku,
        COALESCE(p.name,'') AS product_name,
        COALESCE(p.last_purchase_price,0) AS last_purchase_price
      FROM sale_items si
      LEFT JOIN products p ON p.id = si.product_id
      ORDER BY si.sale_id DESC
    ''');

    // Agrupar items por venta
    final bySale = <int, List<Map<String, dynamic>>>{};
    for (final r in items) {
      final saleId = _toInt(r['sale_id']);
      (bySale[saleId] ??= []).add(r.cast<String, dynamic>());
    }

    final excel = ex.Excel.createExcel();
    excel.delete('Sheet1');
    final sheet = excel['Ventas_detalle'];

    // Encabezados (una sola hoja)
    sheet.appendRow([
      ex.TextCellValue('sale_id'),
      ex.TextCellValue('date'),
      ex.TextCellValue('customer_phone'),
      ex.TextCellValue('customer_name'),
      ex.TextCellValue('payment_method'),
      ex.TextCellValue('place'),
      ex.TextCellValue('shipping_cost'),
      ex.TextCellValue('discount_total'),
      ex.TextCellValue('subtotal_items'),
      ex.TextCellValue('total_sale'),
      ex.TextCellValue('sale_profit'),
      ex.TextCellValue('sale_margin_%'),
      ex.TextCellValue('sku'),
      ex.TextCellValue('product'),
      ex.TextCellValue('qty'),
      ex.TextCellValue('unit_price'),
      ex.TextCellValue('cost'),
      ex.TextCellValue('line_gross'),
      ex.TextCellValue('line_discount'),
      ex.TextCellValue('line_net'),
      ex.TextCellValue('line_profit'),
      ex.TextCellValue('line_margin_%'),
      ex.TextCellValue('row_type'), // HEADER / ITEM / TOTAL
    ]);

    for (final s in sales) {
      final saleId = _toInt(s['id']);
      final date = (s['date'] ?? '').toString();
      final phone = (s['customer_phone'] ?? '').toString();
      final cname = (s['customer_name'] ?? '').toString();
      final pay = (s['payment_method'] ?? '').toString();
      final place = (s['place'] ?? '').toString();
      final shipping = _toDouble(s['shipping_cost']);
      final discountTotal = _toDouble(s['discount']);

      final its = bySale[saleId] ?? const <Map<String, dynamic>>[];

      // subtotal de items (para prorratear descuento)
      double subtotal = 0.0;
      for (final it in its) {
        final qty = _toInt(it['quantity']);
        final unit = _toDouble(it['unit_price']);
        subtotal += qty * unit;
      }

      final totalSale = subtotal + shipping - discountTotal;

      // Header row (misma hoja)
      sheet.appendRow([
        ex.IntCellValue(saleId),
        ex.TextCellValue(date),
        ex.TextCellValue(phone),
        ex.TextCellValue(cname),
        ex.TextCellValue(pay),
        ex.TextCellValue(place),
        ex.DoubleCellValue(shipping),
        ex.DoubleCellValue(discountTotal),
        ex.DoubleCellValue(subtotal),
        ex.DoubleCellValue(totalSale),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue('HEADER'),
      ]);

      // Items
      double saleProfit = 0.0;
      for (final it in its) {
        final sku = (it['sku'] ?? '').toString();
        final pname = (it['product_name'] ?? '').toString();
        final qty = _toInt(it['quantity']);
        final unit = _toDouble(it['unit_price']);
        final cost = _toDouble(it['last_purchase_price']);

        final lineGross = qty * unit;

        // descuento proporcional por renglón (como en sales_page.dart)
        final lineDiscount = (subtotal > 0)
            ? (discountTotal * (lineGross / subtotal))
            : 0.0;

        final lineNet = lineGross - lineDiscount;

        // Envío NO afecta utilidad (como en tu sales_page.dart)
        final lineProfit = ((unit - cost) * qty) - lineDiscount;

        final lineMargin = (lineNet > 0) ? (lineProfit / lineNet) : 0.0;

        saleProfit += lineProfit;

        sheet.appendRow([
          ex.IntCellValue(saleId),
          ex.TextCellValue(date),
          ex.TextCellValue(phone),
          ex.TextCellValue(cname),
          ex.TextCellValue(pay),
          ex.TextCellValue(place),
          ex.DoubleCellValue(shipping),
          ex.DoubleCellValue(discountTotal),
          ex.DoubleCellValue(subtotal),
          ex.DoubleCellValue(totalSale),
          ex.TextCellValue(''),
          ex.TextCellValue(''),
          ex.TextCellValue(sku),
          ex.TextCellValue(pname),
          ex.IntCellValue(qty),
          ex.DoubleCellValue(unit),
          ex.DoubleCellValue(cost),
          ex.DoubleCellValue(lineGross),
          ex.DoubleCellValue(lineDiscount),
          ex.DoubleCellValue(lineNet),
          ex.DoubleCellValue(lineProfit),
          ex.DoubleCellValue(lineMargin * 100.0),
          ex.TextCellValue('ITEM'),
        ]);
      }

      final saleMargin = (subtotal > 0) ? (saleProfit / subtotal) : 0.0;

      // Total row por venta (misma hoja)
      sheet.appendRow([
        ex.IntCellValue(saleId),
        ex.TextCellValue(date),
        ex.TextCellValue(phone),
        ex.TextCellValue(cname),
        ex.TextCellValue(pay),
        ex.TextCellValue(place),
        ex.DoubleCellValue(shipping),
        ex.DoubleCellValue(discountTotal),
        ex.DoubleCellValue(subtotal),
        ex.DoubleCellValue(totalSale),
        ex.DoubleCellValue(saleProfit),
        ex.DoubleCellValue(saleMargin * 100.0),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue('TOTAL'),
      ]);

      // Línea en blanco para separar ventas
      sheet.appendRow(List.generate(23, (_) => ex.TextCellValue('')));
    }

    final bytes = excel.encode();
    if (bytes == null) {
      throw Exception('No se pudo generar el Excel');
    }
    return Uint8List.fromList(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final wrapPad = const EdgeInsets.symmetric(vertical: 4);
    return Scaffold(
      appBar: AppBar(title: const Text('Respaldo / XLSX / BD')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Exportar a XLSX',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            Padding(
              padding: wrapPad,
              child: ElevatedButton(
                onPressed: () => _export(
                  fileName: 'products.xlsx',
                  builder: xio.buildProductsXlsxBytes,
                ),
                child: const Text('Productos'),
              ),
            ),
            Padding(
              padding: wrapPad,
              child: ElevatedButton(
                onPressed: () => _export(
                  fileName: 'clients.xlsx',
                  builder: xio.buildClientsXlsxBytes,
                ),
                child: const Text('Clientes'),
              ),
            ),
            Padding(
              padding: wrapPad,
              child: ElevatedButton(
                onPressed: () => _export(
                  fileName: 'suppliers.xlsx',
                  builder: xio.buildSuppliersXlsxBytes,
                ),
                child: const Text('Proveedores'),
              ),
            ),
            Padding(
              padding: wrapPad,
              child: ElevatedButton(
                // ✅ CAMBIO: ventas con items + utilidad en la MISMA hoja
                onPressed: () => _export(
                  fileName: 'sales.xlsx',
                  builder: _buildSalesWithItemsAndProfitXlsxBytes,
                ),
                child: const Text('Ventas'),
              ),
            ),
            Padding(
              padding: wrapPad,
              child: ElevatedButton(
                onPressed: () => _export(
                  fileName: 'purchases.xlsx',
                  builder: xio.buildPurchasesXlsxBytes,
                ),
                child: const Text('Compras'),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          const Text('Importar desde XLSX (elige archivo)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            OutlinedButton(
              onPressed: () => _pickAndImport(
                  label: 'Productos', importer: xio.importProductsXlsxBytes),
              child: const Text('Productos'),
            ),
            OutlinedButton(
              onPressed: () => _pickAndImport(
                  label: 'Clientes', importer: xio.importClientsXlsxBytes),
              child: const Text('Clientes'),
            ),
            OutlinedButton(
              onPressed: () => _pickAndImport(
                  label: 'Proveedores',
                  importer: xio.importSuppliersXlsxBytes),
              child: const Text('Proveedores'),
            ),
            OutlinedButton(
              // OJO: importador de ventas sigue siendo el tuyo (xio),
              // el XLSX “analítico” NO está pensado para reimportarse.
              onPressed: () => _pickAndImport(
                  label: 'Ventas', importer: xio.importSalesXlsxBytes),
              child: const Text('Ventas'),
            ),
            OutlinedButton(
              onPressed: () => _pickAndImport(
                  label: 'Compras', importer: xio.importPurchasesXlsxBytes),
              child: const Text('Compras'),
            ),
          ]),
          const SizedBox(height: 24),
          const Text('Respaldo de Base de Datos (.db)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _backupDb,
            child: const Text('Respaldar BD (elegir destino)'),
          ),
          OutlinedButton(
            onPressed: _restoreDb,
            child: const Text('Restaurar BD desde archivo'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Nota: El XLSX analítico de ventas es para análisis (incluye items y utilidad). '
            'No se recomienda importarlo de vuelta.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
