import 'package:flutter/material.dart';
import '../utils/xml_backup.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context) {
    Future<void> _run(Future<dynamic> Function() f, String ok) async {
      try {
        await f();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Exportar XML', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(onPressed: ()=>_run(exportClientsXml, 'Clientes exportados'), child: const Text('Clientes')),
          FilledButton(onPressed: ()=>_run(exportProductsXml, 'Productos exportados'), child: const Text('Productos')),
          FilledButton(onPressed: ()=>_run(exportSuppliersXml, 'Proveedores exportados'), child: const Text('Proveedores')),
          FilledButton(onPressed: ()=>_run(exportSalesXml, 'Ventas exportadas'), child: const Text('Ventas')),
          FilledButton(onPressed: ()=>_run(exportPurchasesXml, 'Compras exportadas'), child: const Text('Compras')),
        ]),
        const SizedBox(height: 24),
        const Text('Importar XML (pendiente UI de selector de archivos)'),
      ],
    );
  }
}
