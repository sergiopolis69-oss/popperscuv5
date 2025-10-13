import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../utils/xlsx_io.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

  Future<void> _importXlsx({
    required String titulo,
    required Future<ImportReport> Function(Uint8List) fn,
  }) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty || picked.files.first.bytes == null) return;
      final bytes = picked.files.first.bytes!;
      final r = await fn(bytes);

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Importar $titulo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Insertados: ${r.inserted}'),
              Text('Actualizados: ${r.updated}'),
              Text('Saltados: ${r.skipped}'),
              Text('Errores: ${r.errors}'),
              if (r.messages.isNotEmpty) const SizedBox(height: 8),
              if (r.messages.isNotEmpty)
                SizedBox(
                  width: 420,
                  height: 160,
                  child: Scrollbar(
                    child: ListView(
                      children: r.messages.map((e) => Text('• $e')).toList(),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cerrar')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _snack('Error importando $titulo: $e');
    }
  }

  Future<void> _exportXlsx({
    required String titulo,
    required Future<String> Function() fnSaveFile,
  }) async {
    try {
      final path = await fnSaveFile();
      if (!mounted) return;
      await _showPathDialog('Exportar $titulo', path);
    } catch (e) {
      if (!mounted) return;
      _snack('Error exportando $titulo: $e');
    }
  }

  Future<void> _exportDb() async {
    try {
      final path = await exportDatabaseCopyToFile();
      if (!mounted) return;
      await _showPathDialog('Respaldo de Base de Datos (.db)', path);
    } catch (e) {
      if (!mounted) return;
      _snack('Error al respaldar BD: $e');
    }
  }

  Future<void> _restoreDb() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
      );
      if (picked == null || picked.files.isEmpty || picked.files.first.path == null) return;
      final path = picked.files.first.path!;

      // Confirmación (advierte que reemplaza lógicamente todas las tablas)
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Restaurar desde .db'),
          content: const Text(
            'Esto vaciará las tablas actuales y restaurará los registros del archivo seleccionado. '
            'Se preservan relaciones usando SKU (productos) y phone (clientes/proveedores).\n\n'
            '¿Continuar?'
          ),
          actions: [
            TextButton(onPressed: ()=>Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: ()=>Navigator.pop(context, true), child: const Text('Restaurar')),
          ],
        ),
      );
      if (ok != true) return;

      final r = await restoreDatabaseFromFile(path);

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Restauración completada'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Insertados: ${r.inserted}'),
              Text('Actualizados: ${r.updated}'),
              Text('Saltados: ${r.skipped}'),
              Text('Errores: ${r.errors}'),
              if (r.messages.isNotEmpty) const SizedBox(height: 8),
              if (r.messages.isNotEmpty)
                SizedBox(
                  width: 420,
                  height: 160,
                  child: Scrollbar(
                    child: ListView(
                      children: r.messages.map((e) => Text('• $e')).toList(),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cerrar')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _snack('Error restaurando BD: $e');
    }
  }

  Future<void> _showPathDialog(String title, String path) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SelectableText(path),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: path));
              if (mounted) _snack('Ruta copiada al portapapeles');
            },
            child: const Text('Copiar ruta'),
          ),
          TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Respaldo / Importación')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Exportar a XLSX', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12, runSpacing: 12,
            children: [
              FilledButton(
                onPressed: ()=>_exportXlsx(titulo: 'Productos', fnSaveFile: exportProductsXlsxToFile),
                child: const Text('Productos'),
              ),
              FilledButton(
                onPressed: ()=>_exportXlsx(titulo: 'Clientes', fnSaveFile: exportClientsXlsxToFile),
                child: const Text('Clientes'),
              ),
              FilledButton(
                onPressed: ()=>_exportXlsx(titulo: 'Proveedores', fnSaveFile: exportSuppliersXlsxToFile),
                child: const Text('Proveedores'),
              ),
              FilledButton(
                onPressed: ()=>_exportXlsx(titulo: 'Ventas (con partidas)', fnSaveFile: exportSalesXlsxToFile),
                child: const Text('Ventas'),
              ),
              FilledButton(
                onPressed: ()=>_exportXlsx(titulo: 'Compras (con partidas)', fnSaveFile: exportPurchasesXlsxToFile),
                child: const Text('Compras'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Importar desde XLSX', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12, runSpacing: 12,
            children: [
              OutlinedButton(
                onPressed: ()=>_importXlsx(titulo: 'Productos', fn: importProductsFromBytes),
                child: const Text('Productos'),
              ),
              OutlinedButton(
                onPressed: ()=>_importXlsx(titulo: 'Clientes', fn: importClientsFromBytes),
                child: const Text('Clientes'),
              ),
              OutlinedButton(
                onPressed: ()=>_importXlsx(titulo: 'Proveedores', fn: importSuppliersFromBytes),
                child: const Text('Proveedores'),
              ),
              OutlinedButton(
                onPressed: ()=>_importXlsx(titulo: 'Ventas', fn: importSalesFromBytes),
                child: const Text('Ventas'),
              ),
              OutlinedButton(
                onPressed: ()=>_importXlsx(titulo: 'Compras', fn: importPurchasesFromBytes),
                child: const Text('Compras'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Respaldo completo de Base de Datos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12, runSpacing: 12,
            children: [
              FilledButton.tonal(
                onPressed: _exportDb,
                child: const Text('Exportar .db'),
              ),
              OutlinedButton.icon(
                onPressed: _restoreDb,
                icon: const Icon(Icons.restore),
                label: const Text('Restaurar desde .db'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Nota: el respaldo .db copia el archivo SQLite actual. La restauración desde .db '
            'reemplaza lógicamente los datos de todas las tablas usando SKU/phone como claves naturales.',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}