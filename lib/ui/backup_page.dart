import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/xlsx_io.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  Future<void> _export(BuildContext ctx, String what, Future Function() fn) async {
    try {
      final file = await fn();
      if (!mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$what exportado: ${file.path.split('/').last}')));
    } catch (e) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error al exportar $what: $e')));
    }
  }

  Future<void> _import(BuildContext ctx, String what, Future<ImportReport> Function(Uint8List) fn) async {
    try {
      final pick = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
      if (pick == null || pick.files.single.bytes == null) return;
      final rep = await fn(pick.files.single.bytes!);
      if (!mounted) return;
      final msg = '${rep.ok} filas OK' + (rep.errors.isEmpty ? '' : ' • Errores: ${rep.errors.length}');
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Importación $what: $msg')));
    } catch (e) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error al importar $what: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Exportar a XLSX (carpeta Descargas)'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(onPressed: ()=>_export(context, 'Productos', exportProductsXlsx), child: const Text('Productos')),
          FilledButton(onPressed: ()=>_export(context, 'Clientes', exportClientsXlsx), child: const Text('Clientes')),
          FilledButton(onPressed: ()=>_export(context, 'Proveedores', exportSuppliersXlsx), child: const Text('Proveedores')),
          FilledButton(onPressed: ()=>_export(context, 'Ventas', exportSalesXlsx), child: const Text('Ventas')),
          FilledButton(onPressed: ()=>_export(context, 'Compras', exportPurchasesXlsx), child: const Text('Compras')),
        ]),

        const SizedBox(height: 24),
        const Text('Importar desde XLSX'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: ()=>_import(context, 'Productos', importProductsXlsx), child: const Text('Productos')),
          OutlinedButton(onPressed: ()=>_import(context, 'Clientes', importClientsXlsx), child: const Text('Clientes')),
          OutlinedButton(onPressed: ()=>_import(context, 'Proveedores', importSuppliersXlsx), child: const Text('Proveedores')),
          OutlinedButton(onPressed: ()=>_import(context, 'Ventas', importSalesXlsx), child: const Text('Ventas')),
          OutlinedButton(onPressed: ()=>_import(context, 'Compras', importPurchasesXlsx), child: const Text('Compras')),
        ]),

        const SizedBox(height: 16),
        const Text('Plantillas esperadas (hojas y columnas mínimas):\n\n'
            '• productos: sku, name, category, default_sale_price, last_purchase_price, stock\n'
            '• clientes: phone, name, address\n'
            '• proveedores: phone, name, address\n'
            '• ventas: id, customer_phone, payment_method, place, shipping_cost, discount, date\n'
            '• venta_items: sale_id, product_sku, quantity, unit_price\n'
            '• compras: id, folio, supplier_id, date\n'
            '• compra_items: purchase_id, product_sku, quantity, unit_cost'),
      ],
    );
  }
}