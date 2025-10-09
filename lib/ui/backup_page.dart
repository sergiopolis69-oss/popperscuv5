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
            OutlinedButton(onPressed: ()=>_run(context, 'Exportar Ventas', exportSalesXlsx), child: const Text('Ventas')),
            OutlinedButton(onPressed: ()=>_run(context, 'Exportar Compras', exportPurchasesXlsx), child: const Text('Compras')),
            OutlinedButton(onPressed: ()=>_run(context, 'Exportar Productos', exportProductsXlsx), child: const Text('Productos')),
            OutlinedButton(onPressed: ()=>_run(context, 'Exportar Clientes', exportClientsXlsx), child: const Text('Clientes')),
            OutlinedButton(onPressed: ()=>_run(context, 'Exportar Proveedores', exportSuppliersXlsx), child: const Text('Proveedores')),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Importar desde XLSX', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(onPressed: ()=>_run(context, 'Importar Ventas', importSalesXlsx), child: const Text('Ventas (.xlsx)')),
            OutlinedButton(onPressed: ()=>_run(context, 'Importar Compras', importPurchasesXlsx), child: const Text('Compras (.xlsx)')),
            OutlinedButton(onPressed: ()=>_run(context, 'Importar Productos', importProductsXlsx), child: const Text('Productos (.xlsx)')),
            OutlinedButton(onPressed: ()=>_run(context, 'Importar Clientes', importClientsXlsx), child: const Text('Clientes (.xlsx)')),
            OutlinedButton(onPressed: ()=>_run(context, 'Importar Proveedores', importSuppliersXlsx), child: const Text('Proveedores (.xlsx)')),
          ],
        ),
        const SizedBox(height: 48),
        const Text(
          'Formato esperado:\n'
          '• products: id, sku, name, category, default_sale_price, last_purchase_price, stock, last_purchase_date\n'
          '• customers: phone, name, address\n'
          '• suppliers: phone, name, address\n'
          '• sales + sale_items (con SKU)\n'
          '• purchases + purchase_items (con SKU)\n'
          'Nota: La importación hace upsert por SKU (productos) y por teléfono (clientes/proveedores).',
        ),
      ],
    );
  }
}