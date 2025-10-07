import 'package:flutter/material.dart';
import '../utils/xlsx_backup.dart';
import 'package:open_filex/open_filex.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  Future<void> _runExport(BuildContext ctx, String label, Future<File> Function() fn) async {
    try {
      final f = await fn();
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('$label exportado a Descargas\n${f.path}'),
        action: SnackBarAction(label: 'Abrir', onPressed: ()=>OpenFilex.open(f.path)),
      ));
    } catch (e) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _runImport(BuildContext ctx, String label, Future<void> Function() fn) async {
    try {
      await fn();
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$label importado correctamente')));
    } catch (e) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Exportar a XLSX (carpeta Descargas)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(onPressed: ()=>_runExport(context, 'Clientes', exportClientsXlsx), child: const Text('Clientes')),
          FilledButton(onPressed: ()=>_runExport(context, 'Productos', exportProductsXlsx), child: const Text('Productos')),
          FilledButton(onPressed: ()=>_runExport(context, 'Proveedores', exportSuppliersXlsx), child: const Text('Proveedores')),
          FilledButton(onPressed: ()=>_runExport(context, 'Ventas', exportSalesXlsx), child: const Text('Ventas')),
          FilledButton(onPressed: ()=>_runExport(context, 'Compras', exportPurchasesXlsx), child: const Text('Compras')),
          OutlinedButton.icon(onPressed: ()=>_runExport(context, 'Plantilla productos', exportProductsTemplateXlsx),
              icon: const Icon(Icons.download), label: const Text('Plantilla productos')),
        ]),
        const SizedBox(height: 24),
        const Text('Importar desde XLSX', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: ()=>_runImport(context, 'Clientes', importClientsXlsx), child: const Text('Clientes')),
          OutlinedButton(onPressed: ()=>_runImport(context, 'Productos', importProductsXlsx), child: const Text('Productos')),
          OutlinedButton(onPressed: ()=>_runImport(context, 'Proveedores', importSuppliersXlsx), child: const Text('Proveedores')),
          OutlinedButton(onPressed: ()=>_runImport(context, 'Ventas', importSalesXlsx), child: const Text('Ventas')),
          OutlinedButton(onPressed: ()=>_runImport(context, 'Compras', importPurchasesXlsx), child: const Text('Compras')),
        ]),
      ],
    );
  }
}