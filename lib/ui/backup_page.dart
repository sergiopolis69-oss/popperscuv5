import 'package:flutter/material.dart';
import '../utils/xlsx_backup.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  Future<void> _run(BuildContext context, Future<void> Function() f, String ok) async {
    try {
      await f();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
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
          FilledButton(onPressed: ()=>_run(context, exportClientsXlsx, 'Clientes exportados'), child: const Text('Clientes')),
          FilledButton(onPressed: ()=>_run(context, exportProductsXlsx, 'Productos exportados'), child: const Text('Productos')),
          FilledButton(onPressed: ()=>_run(context, exportSuppliersXlsx, 'Proveedores exportados'), child: const Text('Proveedores')),
          FilledButton(onPressed: ()=>_run(context, exportSalesXlsx, 'Ventas exportadas'), child: const Text('Ventas')),
          FilledButton(onPressed: ()=>_run(context, exportPurchasesXlsx, 'Compras exportadas'), child: const Text('Compras')),
          OutlinedButton.icon(onPressed: ()=>_run(context, exportProductsTemplateXlsx, 'Plantilla creada'), icon: const Icon(Icons.download), label: const Text('Plantilla productos')),
        ]),
        const SizedBox(height: 24),
        const Text('Importar XLSX', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: ()=>_run(context, importClientsXlsx, 'Clientes importados'), child: const Text('Clientes')),
          OutlinedButton(onPressed: ()=>_run(context, importProductsXlsx, 'Productos importados'), child: const Text('Productos')),
          OutlinedButton(onPressed: ()=>_run(context, importSuppliersXlsx, 'Proveedores importados'), child: const Text('Proveedores')),
          OutlinedButton(onPressed: ()=>_run(context, importSalesXlsx, 'Ventas importadas'), child: const Text('Ventas')),
          OutlinedButton(onPressed: ()=>_run(context, importPurchasesXlsx, 'Compras importadas'), child: const Text('Compras')),
        ]),
        const SizedBox(height: 16),
        const Text('Notas: usa las hojas exactas "clientes", "productos", "proveedores", "ventas/venta_items", "compras/compra_items".'),
      ],
    );
  }
}
