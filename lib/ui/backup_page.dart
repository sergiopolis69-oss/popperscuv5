import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:popperscuv5/utils/xlsx_io.dart' as xio;
import 'package:popperscuv5/utils/toast.dart';
import 'package:popperscuv5/data/database.dart' as appdb;

// ... (tu estado y UI se mantienen; solo pego los métodos clave)

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  Future<void> _export({
    required String fileName,
    required Future<Uint8List> Function() builder,
  }) async {
    try {
      final bytes = await builder();
      final res = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar $fileName',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      if (res == null) return;
      await FilePicker.platform.saveFile( // en Android SAF ignora bytes; usamos write manual por path
        fileName: fileName,
        type: FileType.any,
      );
      await writeBytesToPath(res, bytes); // util tuya si ya la tienes; si no, usa File(res).writeAsBytes(bytes)
      showOk('Exportado a:\n$res');
    } catch (e) {
      showErr('Error al exportar: $e');
    }
  }

  Future<void> _pickAndImport({
    required String label,
    required Future<void> Function(Uint8List) importer,
  }) async {
    try {
      final sel = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
      if (sel == null || sel.files.single.bytes == null) {
        showErr('No seleccionaste archivo.');
        return;
      }
      await importer(sel.files.single.bytes!);
      showOk('Importación de $label completa');
    } catch (e) {
      showErr('Error importando $label: $e');
    }
  }

  Future<void> _backupDb() async {
    try {
      final dbPath = await appdb.getDbPath();
      final saveTo = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar respaldo de BD',
        fileName: 'pdv.db',
        type: FileType.custom,
        allowedExtensions: const ['db'],
      );
      if (saveTo == null) return;
      final bytes = await readBytesFromPath(dbPath);
      await writeBytesToPath(saveTo, bytes);
      showOk('BD guardada en:\n$saveTo');
    } catch (e) {
      showErr('Error al respaldar BD: $e');
    }
  }

  Future<void> _restoreDb() async {
    try {
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['db'], // sin punto
        withData: true,
      );
      if (pick == null || pick.files.single.bytes == null) {
        showErr('No seleccionaste archivo .db');
        return;
      }
      final dest = await appdb.getDbPath();
      await writeBytesToPath(dest, pick.files.single.bytes!);
      showOk('BD restaurada');
    } catch (e) {
      showErr('Error al restaurar BD: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Respaldo / XLSX / BD')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Exportar a XLSX', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            ElevatedButton(
              onPressed: () => _export(fileName: 'products.xlsx', builder: xio.buildProductsXlsxBytes),
              child: const Text('Productos'),
            ),
            ElevatedButton(
              onPressed: () => _export(fileName: 'clients.xlsx', builder: xio.buildClientsXlsxBytes),
              child: const Text('Clientes'),
            ),
            ElevatedButton(
              onPressed: () => _export(fileName: 'suppliers.xlsx', builder: xio.buildSuppliersXlsxBytes),
              child: const Text('Proveedores'),
            ),
            ElevatedButton(
              onPressed: () => _export(fileName: 'sales.xlsx', builder: xio.buildSalesXlsxBytes),
              child: const Text('Ventas'),
            ),
            ElevatedButton(
              onPressed: () => _export(fileName: 'purchases.xlsx', builder: xio.buildPurchasesXlsxBytes),
              child: const Text('Compras'),
            ),
          ]),

          const SizedBox(height: 24),
          const Text('Importar desde XLSX (elige archivo o intenta Descargas con nombre esperado)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            OutlinedButton(
              onPressed: () => _pickAndImport(label: 'Productos', importer: xio.importProductsXlsxBytes),
              child: const Text('Productos'),
            ),
            OutlinedButton(
              onPressed: () => _pickAndImport(label: 'Clientes', importer: xio.importClientsXlsxBytes),
              child: const Text('Clientes'),
            ),
            OutlinedButton(
              onPressed: () => _pickAndImport(label: 'Proveedores', importer: xio.importSuppliersXlsxBytes),
              child: const Text('Proveedores'),
            ),
            OutlinedButton(
              onPressed: () => _pickAndImport(label: 'Ventas', importer: xio.importSalesXlsxBytes),
              child: const Text('Ventas'),
            ),
            OutlinedButton(
              onPressed: () => _pickAndImport(label: 'Compras', importer: xio.importPurchasesXlsxBytes),
              child: const Text('Compras'),
            ),
          ]),

          const SizedBox(height: 24),
          const Text('Respaldo de Base de Datos (.db)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _backupDb,
            child: const Text('Respaldar BD (elegir destino)'),
          ),
          OutlinedButton(
            onPressed: _restoreDb,
            child: const Text('Restaurar BD desde archivo'),
          ),
        ],
      ),
    );
  }
}

/// ===== helpers de IO con paths (reutiliza los tuyos si ya existen) =====
Future<Uint8List> readBytesFromPath(String path) async =>
    await File(path).readAsBytes();

Future<void> writeBytesToPath(String path, Uint8List bytes) async =>
    await File(path).writeAsBytes(bytes, flush: true);