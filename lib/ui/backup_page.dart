import 'package:flutter/material.dart';
import '../utils/xlsx_backup.dart'; // ⬅️ NECESARIO: export*Xlsx e import*Xlsx

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  Future<void> _export(BuildContext ctx, String label, Future<String> Function() fn) async {
    try {
      final uriOrPath = await fn();
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('$label exportado en Descargas'),
        action: SnackBarAction(label: 'Abrir', onPressed: ()=>openUriOrPath(uriOrPath)),
        duration: const Duration(seconds: 6),
      ));
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _import(BuildContext ctx, String label, Future<void> Function() fn) async {
    try {
      await fn();
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$label importado correctamente')));
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Exportar a XLSX (Descargas)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(onPressed: ()=>_export(context, 'Clientes', exportClientsXlsx), child: const Text('Clientes')),
          FilledButton(onPressed: ()=>_export(context, 'Productos', exportProductsXlsx), child: const Text('Productos')),
          FilledButton(onPressed: ()=>_export(context, 'Proveedores', exportSuppliersXlsx), child: const Text('Proveedores')),
          FilledButton(onPressed: ()=>_export(context, 'Ventas', exportSalesXlsx), child: const Text('Ventas')),
          FilledButton(onPressed: ()=>_export(context, 'Compras', exportPurchasesXlsx), child: const Text('Compras')),
          OutlinedButton.icon(
            onPressed: ()=>_export(context, 'Plantilla productos', exportProductsTemplateXlsx),
            icon: const Icon(Icons.download),
            label: const Text('Plantilla productos'),
          ),
        ]),
        const SizedBox(height: 24),
        const Text('Importar desde XLSX', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: ()=>_import(context, 'Clientes', importClientsXlsx), child: const Text('Clientes')),
          OutlinedButton(onPressed: ()=>_import(context, 'Productos', importProductsXlsx), child: const Text('Productos')),
          OutlinedButton(onPressed: ()=>_import(context, 'Proveedores', importSuppliersXlsx), child: const Text('Proveedores')),
          OutlinedButton(onPressed: ()=>_import(context, 'Ventas', importSalesXlsx), child: const Text('Ventas')),
          OutlinedButton(onPressed: ()=>_import(context, 'Compras', importPurchasesXlsx), child: const Text('Compras')),
        ]),
      ],
    );
  }
}
