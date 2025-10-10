import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/xlsx_backup.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  Future<void> _export(BuildContext ctx, String label, Future<String> Function() fn) async {
    try {
      final path = await fn();
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('$label exportado en: $path')),
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

  Future<void> _import(BuildContext ctx, String label, Future<void> Function(Uint8List) fn) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final bytes = res.files.first.bytes;
      if (bytes == null) throw Exception('No se pudo leer el archivo');
      await fn(bytes);
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
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(onPressed: () => _export(context, 'Clientes', exportClientsXlsx), child: const Text('Clientes')),
            FilledButton(onPressed: () => _export(context, 'Productos', exportProductsXlsx), child: const Text('Productos')),
            FilledButton(onPressed: () => _export(context, 'Proveedores', exportSuppliersXlsx), child: const Text('Proveedores')),
            FilledButton(onPressed: () => _export(context, 'Ventas', exportSalesXlsx), child: const Text('Ventas')),
            FilledButton(onPressed: () => _export(context, 'Compras', exportPurchasesXlsx), child: const Text('Compras')),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Importar desde XLSX'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(onPressed: () => _import(context, 'Clientes', importClientsXlsx), child: const Text('Clientes')),
            OutlinedButton(onPressed: () => _import(context, 'Productos', importProductsXlsx), child: const Text('Productos')),
            OutlinedButton(onPressed: () => _import(context, 'Proveedores', importSuppliersXlsx), child: const Text('Proveedores')),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Notas:\n'
          '• Los archivos se guardan en la carpeta pública de Descargas.\n'
          '• Puedes reinstalar la app y restaurar desde XLSX en orden.\n'
          '• Ventas y compras aún se respaldan sin ítems detallados.',
        ),
      ],
    );
  }
}