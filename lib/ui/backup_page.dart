import 'package:flutter/material.dart';
import '../utils/xlsx_backup.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  Future<void> _run(BuildContext context, String label, Future<void> Function() fn) async {
    try {
      await fn();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label: operación terminada')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label: error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Exportar a XLSX', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => _run(context, 'Ventas', exportSalesXlsx),
              child: const Text('Ventas'),
            ),
            OutlinedButton(
              onPressed: () => _run(context, 'Compras', exportPurchasesXlsx),
              child: const Text('Compras'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Importar desde XLSX', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => _run(context, 'Importar Ventas', importSalesXlsx),
              child: const Text('Ventas (.xlsx)'),
            ),
            OutlinedButton(
              onPressed: () => _run(context, 'Importar Compras', importPurchasesXlsx),
              child: const Text('Compras (.xlsx)'),
            ),
          ],
        ),
        const SizedBox(height: 48),
        const Text(
          'Notas:\n'
          '• Las exportaciones guardan en la carpeta Descargas usando el selector del sistema (SAF).\n'
          '• Las importaciones te pedirán elegir el archivo .xlsx.\n'
          '• Las ventas/compras exportan DOS hojas: cabeceras (sales/purchases) y renglones (sale_items/purchase_items) con SKU.',
        ),
      ],
    );
  }
}