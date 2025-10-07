import 'package:flutter/material.dart';
import '../utils/xlsx_backup.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  Future<void> _exportRun(BuildContext context, Future<XlsxExportResult> Function() fn, String okLabel) async {
    try {
      final res = await fn();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$okLabel\nGuardado local: ${res.localPath}'),
          action: SnackBarAction(
            label: 'Abrir',
            onPressed: () => openLocalFile(res.localPath),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _importRun(BuildContext context, Future<void> Function() fn, String okLabel) async {
    try {
      await fn();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(okLabel)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Exportar XLSX', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(onPressed: ()=>_exportRun(context, exportClientsXlsx, 'Clientes exportados'), child: const Text('Clientes')),
          FilledButton(onPressed: ()=>_exportRun(context, exportProductsXlsx, 'Productos exportados'), child: const Text('Productos')),
          FilledButton(onPressed: ()=>_exportRun(context, exportSuppliersXlsx, 'Proveedores exportados'), child: const Text('Proveedores')),
          FilledButton(onPressed: ()=>_exportRun(context, exportSalesXlsx, 'Ventas exportadas'), child: const Text('Ventas')),
          FilledButton(onPressed: ()=>_exportRun(context, exportPurchasesXlsx, 'Compras exportadas'), child: const Text('Compras')),
          OutlinedButton.icon(onPressed: ()=>_exportRun(context, exportProductsTemplateXlsx, 'Plantilla creada'), icon: const Icon(Icons.download), label: const Text('Plantilla productos')),
        ]),
        const SizedBox(height: 24),
        const Text('Importar XLSX', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: ()=>_importRun(context, importClientsXlsx, 'Clientes importados'), child: const Text('Clientes')),
          OutlinedButton(onPressed: ()=>_importRun(context, importProductsXlsx, 'Productos importados'), child: const Text('Productos')),
          OutlinedButton(onPressed: ()=>_importRun(context, importSuppliersXlsx, 'Proveedores importados'), child: const Text('Proveedores')),
          OutlinedButton(onPressed: ()=>_importRun(context, importSalesXlsx, 'Ventas importadas'), child: const Text('Ventas')),
          OutlinedButton(onPressed: ()=>_importRun(context, importPurchasesXlsx, 'Compras importadas'), child: const Text('Compras')),
        ]),
        const SizedBox(height: 12),
        const Text('Notas: usa hojas "clientes", "productos", "proveedores", "ventas/venta_items", "compras/compra_items".'),
      ],
    );
  }
}