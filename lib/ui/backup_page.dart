import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/xlsx_backup.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  Future<void> _import(BuildContext context, String titulo, Future<void> Function(File) importer) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
    if (res == null || res.files.isEmpty) return;
    final path = res.files.single.path;
    if (path == null) return;
    await importer(File(path));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$titulo importado')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Exportar XLSX'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: [
            FilledButton(onPressed: exportSalesXlsx, child: const Text('Ventas')),
            FilledButton(onPressed: exportPurchasesXlsx, child: const Text('Compras')),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Importar XLSX'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: [
            OutlinedButton(onPressed: ()=>_import(context, 'Ventas', importSalesXlsx), child: const Text('Ventas')),
            OutlinedButton(onPressed: ()=>_import(context, 'Compras', importPurchasesXlsx), child: const Text('Compras')),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Los XLSX incluyen SKU en items para poder reconstruir la base con exactitud. Se guardan/leen en la carpeta Descargas.'),
      ],
    );
  }
}