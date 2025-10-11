import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../utils/xlsx_io.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  Future<void> _export(BuildContext ctx, String what, Future<void> Function() fn) async {
    try {
      await fn();
      if (!mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Exportado $what a Descargas')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error al exportar $what: $e')));
    }
  }

  Future<void> _import(BuildContext ctx, String what, Future<ImportReport> Function(Uint8List) fn) async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
      if (res == null || res.files.single.bytes == null) return;
      final report = await fn(res.files.single.bytes!);
      if (!mounted) return;
      final msg = 'Importado $what: ${report.ok} ok'
          '${report.errors.isEmpty ? '' : ' • ${report.errors.length} errores'}';
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error al importar $what: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chip = (String text, VoidCallback onPressed, {bool filled = true}) => Padding(
      padding: const EdgeInsets.all(8.0),
      child: filled
          ? FilledButton(onPressed: onPressed, child: Text(text))
          : OutlinedButton(onPressed: onPressed, child: Text(text)),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Exportar a XLSX (carpeta Descargas)', style: Theme.of(context).textTheme.titleMedium),
        Wrap(spacing: 8, runSpacing: 8, children: [
          chip('Productos', () => _export(context, 'Productos', exportProductsXlsx)),
          chip('Clientes',  () => _export(context, 'Clientes',  exportClientsXlsx)),
          chip('Proveedores', () => _export(context, 'Proveedores', exportSuppliersXlsx)),
          chip('Ventas', () => _export(context, 'Ventas', exportSalesXlsx)),
          chip('Compras', () => _export(context, 'Compras', exportPurchasesXlsx)),
        ]),
        const SizedBox(height: 16),
        Text('Importar desde XLSX', style: Theme.of(context).textTheme.titleMedium),
        Wrap(spacing: 8, runSpacing: 8, children: [
          chip('Productos', () => _import(context, 'Productos', importProductsXlsx), filled: false),
          chip('Clientes',  () => _import(context, 'Clientes',  importClientsXlsx), filled: false),
          chip('Proveedores', () => _import(context, 'Proveedores', importSuppliersXlsx), filled: false),
          chip('Ventas', () => _import(context, 'Ventas', importSalesXlsx), filled: false),
          chip('Compras', () => _import(context, 'Compras', importPurchasesXlsx), filled: false),
        ]),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(16),
          child: const Text(
            'Plantillas esperadas (hojas y columnas mínimas):\n'
            '• productos: sku, name, category, default_sale_price, last_purchase_price, stock\n'
            '• clientes: phone, name, address\n'
            '• proveedores: phone, name, address\n'
            '• ventas: id, customer_phone, payment_method, place, shipping_cost, discount, date\n'
            '• venta_items: sale_id, product_sku, quantity, unit_price\n'
            '• compras: id, folio, supplier_id, date\n'
            '• compra_items: purchase_id, product_sku, quantity, unit_cost',
          ),
        ),
      ],
    );
  }
}