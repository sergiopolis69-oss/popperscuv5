import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../utils/xlsx_io.dart';

class BackupPage extends StatefulWidget {
  /// Provee los bytes del archivo XLSX a importar (ej. usando file_picker en tu app).
  final Future<Uint8List?> Function()? onPickXlsx;

  const BackupPage({super.key, this.onPickXlsx});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _export(
    String titulo,
    Future<String> Function() fnExport,
  ) async {
    _snack('Exportando $titulo…');
    try {
      final path = await fnExport();
      _snack('$titulo exportado: $path');
    } catch (e) {
      _snack('Error al exportar $titulo: $e');
    }
  }

  Future<void> _import(
    String titulo,
    Future<void> Function(Uint8List) fnImport,
  ) async {
    if (widget.onPickXlsx == null) {
      _snack('Selector de archivos no configurado');
      return;
    }
    final bytes = await widget.onPickXlsx!.call();
    if (bytes == null) {
      _snack('Importación cancelada');
      return;
    }
    _snack('Importando $titulo…');
    try {
      await fnImport(bytes);
      _snack('$titulo importado');
    } catch (e) {
      _snack('Error al importar $titulo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Exportar a XLSX', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(onPressed: ()=>_export('Productos', exportProductsXlsx), child: const Text('Productos')),
            FilledButton(onPressed: ()=>_export('Clientes', exportClientsXlsx), child: const Text('Clientes')),
            FilledButton(onPressed: ()=>_export('Proveedores', exportSuppliersXlsx), child: const Text('Proveedores')),
            FilledButton(onPressed: ()=>_export('Ventas', exportSalesXlsx), child: const Text('Ventas')),
            FilledButton(onPressed: ()=>_export('Compras', exportPurchasesXlsx), child: const Text('Compras')),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Importar desde XLSX', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(onPressed: ()=>_import('Productos', importProductsXlsx), child: const Text('Productos')),
            OutlinedButton(onPressed: ()=>_import('Clientes', importClientsXlsx), child: const Text('Clientes')),
            OutlinedButton(onPressed: ()=>_import('Proveedores', importSuppliersXlsx), child: const Text('Proveedores')),
            OutlinedButton(onPressed: ()=>_import('Ventas', importSalesXlsx), child: const Text('Ventas')),
            OutlinedButton(onPressed: ()=>_import('Compras', importPurchasesXlsx), child: const Text('Compras')),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Nota: los archivos se guardan en la carpeta de documentos interna de la app. '
            'Puedes mostrar un acceso directo usando el path devuelto por “Exportar”.'),
      ],
    );
  }
}