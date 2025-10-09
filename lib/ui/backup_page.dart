import 'package:flutter/material.dart';
import '../utils/xlsx_backup.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  Future<void> _run(BuildContext context, String label, Future<void> Function() action) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label: procesando...'), duration: const Duration(seconds: 1)),
    );
    try {
      await action();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label: listo ✓')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label: error → $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Exportar a XLSX', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton(onPressed: () => _run(context, 'Exportar Clientes', exportClientsXlsx), child: const Text('Clientes')),
            OutlinedButton(onPressed: () => _run(context, 'Exportar Productos', exportProductsXlsx), child: const Text('Productos')),
            OutlinedButton(onPressed: () => _run(context, 'Exportar Proveedores', exportSuppliersXlsx), child: const Text('Proveedores')),
            OutlinedButton(onPressed: () => _run(context, 'Exportar Ventas', exportSalesXlsx), child: const Text('Ventas')),
            OutlinedButton(onPressed: () => _run(context, 'Exportar Compras', exportPurchasesXlsx), child: const Text('Compras')),
          ],
        ),
        const Divider(height: 32),
        const Text('Importar desde XLSX', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton(onPressed: () => _run(context, 'Importar Clientes', importClientsXlsx), child: const Text('Clientes')),
            OutlinedButton(onPressed: () => _run(context, 'Importar Productos', importProductsXlsx), child: const Text('Productos')),
            OutlinedButton(onPressed: () => _run(context, 'Importar Proveedores', importSuppliersXlsx), child: const Text('Proveedores')),
            OutlinedButton(onPressed: () => _run(context, 'Importar Ventas', importSalesXlsx), child: const Text('Ventas')),
            OutlinedButton(onPressed: () => _run(context, 'Importar Compras', importPurchasesXlsx), child: const Text('Compras')),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Notas:\n• No se requiere permiso de almacenamiento: se usa selector del sistema.\n'
          '• En Android, el sistema te pedirá ubicación de guardado (suele ser Descargas).\n'
          '• Los archivos de ventas/compras incluyen SKU en los renglones de detalle.',
        ),
      ],
    );
  }
}