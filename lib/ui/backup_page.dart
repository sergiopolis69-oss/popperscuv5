import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/xml_backup.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  Future<File?> _pickXmlAsFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xml']);
    if (res == null) return null;
    final f = res.files.single;
    if (f.path != null) return File(f.path!);
    // Si viene en memoria, lo escribimos a /tmp
    final bytes = f.bytes;
    if (bytes == null) return null;
    final tmp = await getTemporaryDirectory();
    final file = File('${tmp.path}/${f.name}');
    await file.writeAsBytes(bytes);
    return file;
    }

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

    Future<void> _import(void Function(File) importer) async {
      final file = await _pickXmlAsFile();
      if (file == null) return;
      try {
        await importer(file);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Importación completa')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error importando: $e')));
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
        const Text('Importar XML', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: ()=>_import(importClientsXml), child: const Text('Clientes')),
          OutlinedButton(onPressed: ()=>_import(importProductsXml), child: const Text('Productos')),
          OutlinedButton(onPressed: ()=>_import(importSuppliersXml), child: const Text('Proveedores')),
        ]),
      ],
    );
  }
}