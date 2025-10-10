import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../utils/xlsx_backup.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;

  Future<void> _exportAll() async {
    setState(() => _busy = true);
    try {
      await exportAllToXlsx();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exportado a XLSX (elige la ubicación en el diálogo del sistema).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error exportando: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndImport(Future<void> Function(File) importer) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (res == null || res.files.isEmpty) return;
      final path = res.files.single.path;
      if (path == null) return;
      await importer(File(path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Importación completada.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error importando: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _exportAll,
              icon: const Icon(Icons.download),
              label: const Text('Exportar TODO (XLSX)'),
            ),
            const SizedBox(width: 12),
            if (_busy) const Padding(
              padding: EdgeInsets.only(left: 8.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Importar desde XLSX (elige archivo por catálogo):'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => _pickAndImport(importCustomersXlsx),
              child: const Text('Clientes'),
            ),
            OutlinedButton(
              onPressed: () => _pickAndImport(importProductsXlsx),
              child: const Text('Productos'),
            ),
            OutlinedButton(
              onPressed: () => _pickAndImport(importSuppliersXlsx),
              child: const Text('Proveedores'),
            ),
            OutlinedButton(
              onPressed: () => _pickAndImport(importSalesXlsx),
              child: const Text('Ventas'),
            ),
            OutlinedButton(
              onPressed: () => _pickAndImport(importPurchasesXlsx),
              child: const Text('Compras'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Formato XLSX esperado:\n'
          '• Hoja "products": sku, name, category, default_sale_price, last_purchase_price, stock\n'
          '• Hoja "customers": phone, name, address\n'
          '• Hoja "suppliers": phone, name, address\n'
          '• Hoja "sales": id, customer_phone, payment_method, place, shipping_cost, discount, date\n'
          '• Hoja "sale_items": sale_id, sku, quantity, unit_price\n'
          '• Hoja "purchases": id, supplier_phone, folio, date\n'
          '• Hoja "purchase_items": purchase_id, sku, quantity, unit_cost\n',
        ),
      ],
    );
  }
}