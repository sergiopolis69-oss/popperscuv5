import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';

import '../utils/xlsx_backup.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  String? _lastPath;

  Future<void> _export(BuildContext ctx, String label, Future<String> Function() fn) async {
    try {
      final savedPath = await fn();
      setState(()=>_lastPath = savedPath);
      if (!mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('$label exportado: $savedPath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('Error exportando $label: $e')),
      );
    }
  }

  Future<void> _import(BuildContext ctx, String label, Future<void> Function(Uint8List) handler) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final bytes = res.files.first.bytes;
      if (bytes == null) throw Exception('No se pudo leer el archivo');
      await handler(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('$label importado correctamente')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('Error importando $label: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Exportar a XLSX (carpeta Descargas)'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: [
            FilledButton(onPressed: ()=>_export(context, 'Clientes', exportClientsXlsx), child: const Text('Clientes')),
            FilledButton(onPressed: ()=>_export(context, 'Productos', exportProductsXlsx), child: const Text('Productos')),
            FilledButton(onPressed: ()=>_export(context, 'Proveedores', exportSuppliersXlsx), child: const Text('Proveedores')),
            FilledButton(onPressed: ()=>_export(context, 'Ventas', exportSalesXlsx), child: const Text('Ventas (con SKU)')),
            FilledButton(onPressed: ()=>_export(context, 'Compras', exportPurchasesXlsx), child: const Text('Compras (con SKU)')),
          ],
        ),
        if (_lastPath != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.file_present),
              title: Text(_lastPath!),
              trailing: IconButton(
                icon: const Icon(Icons.open_in_new),
                onPressed: () => OpenFilex.open(_lastPath!),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        const Text('Importar desde XLSX'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: [
            OutlinedButton(onPressed: ()=>_import(context, 'Clientes', importClientsXlsx), child: const Text('Clientes')),
            OutlinedButton(onPressed: ()=>_import(context, 'Productos', importProductsXlsx), child: const Text('Productos')),
            OutlinedButton(onPressed: ()=>_import(context, 'Proveedores', importSuppliersXlsx), child: const Text('Proveedores')),
            OutlinedButton(onPressed: ()=>_import(context, 'Ventas (+items por SKU)', importSalesXlsx), child: const Text('Ventas')),
            OutlinedButton(onPressed: ()=>_import(context, 'Compras (+items por SKU)', importPurchasesXlsx), child: const Text('Compras')),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Notas:\n'
          '• Cabeceras esperadas:\n'
          '  - productos: sku,name,category,default_sale_price,last_purchase_price,last_purchase_date,stock\n'
          '  - clientes: phone_id,name,address\n'
          '  - proveedores: id,name,phone,address\n'
          '  - ventas: sale_id,date,customer_phone,payment_method,place,shipping_cost,discount + ventas_items: sale_id,product_sku,product_name,quantity,unit_price\n'
          '  - compras: purchase_id,folio,date,supplier_id + compras_items: purchase_id,product_sku,product_name,quantity,unit_cost\n'
          '• Si un SKU no existe, el renglón de detalle se ignora por seguridad.',
        ),
      ],
    );
  }
}