import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../utils/xlsx_backup.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  Future<void> _export(
    BuildContext ctx,
    String label,
    Future<String> Function() fn,
  ) async {
    try {
      final savedAt = await fn(); // ahora devuelve String
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('$label exportado en: $savedAt')),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Error exportando $label: $e')),
        );
      }
    }
  }

  Future<void> _import(
    BuildContext ctx,
    String label,
    Future<void> Function(Uint8List) fn,
  ) async {
    try {
      // El selector está implementado dentro de xlsx_backup.import* para
      // mantener permisos/lectura consistentes; pero si prefieres hacerlo
      // aquí, puedes revertir a FilePicker con withData:true.
      await showImportFilePicker(ctx, label, fn);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('$label importado correctamente')),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Error importando $label: $e')),
        );
      }
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
            FilledButton(
              onPressed: () => _export(context, 'Clientes', exportClientsXlsx),
              child: const Text('Clientes'),
            ),
            FilledButton(
              onPressed: () => _export(context, 'Productos', exportProductsXlsx),
              child: const Text('Productos'),
            ),
            FilledButton(
              onPressed: () => _export(context, 'Proveedores', exportSuppliersXlsx),
              child: const Text('Proveedores'),
            ),
            FilledButton(
              onPressed: () => _export(context, 'Ventas (con SKU)', exportSalesXlsx),
              child: const Text('Ventas (con SKU)'),
            ),
            FilledButton(
              onPressed: () => _export(context, 'Compras (con SKU)', exportPurchasesXlsx),
              child: const Text('Compras (con SKU)'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Importar desde XLSX'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => _import(context, 'Clientes', importClientsXlsx),
              child: const Text('Clientes'),
            ),
            OutlinedButton(
              onPressed: () => _import(context, 'Productos', importProductsXlsx),
              child: const Text('Productos'),
            ),
            OutlinedButton(
              onPressed: () => _import(context, 'Proveedores', importSuppliersXlsx),
              child: const Text('Proveedores'),
            ),
            OutlinedButton(
              onPressed: () => _import(context, 'Ventas (+items por SKU)', importSalesXlsx),
              child: const Text('Ventas'),
            ),
            OutlinedButton(
              onPressed: () => _import(context, 'Compras (+items por SKU)', importPurchasesXlsx),
              child: const Text('Compras'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Notas:\n'
          '• Los renglones de ventas/compras usan el SKU para enlazar productos.\n'
          '• Si el SKU no existe en productos, ese renglón se ignora.\n'
          '• Flujo recomendado tras reinstalar: Productos → Clientes/Proveedores → Ventas/Compras.',
        ),
      ],
    );
  }
}