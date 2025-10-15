import 'dart:typed_data';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:popperscuv5/utils/xlsx_io.dart' as xio;
import 'package:popperscuv5/data/database.dart' as appdb;
import 'package:sqflite/sqflite.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  // snackbars locales
  void showOk(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  void showErr(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red.shade700, content: Text(msg)),
      );

  Future<Database> _db() => appdb.getDb();
  Future<String> _dbPath() async => (await _db()).path;

  // ====== EXPORTAR XLSX ======================================================
  Future<void> _export({
    required String fileName,
    required Future<Uint8List> Function() builder,
  }) async {
    try {
      final bytes = await builder(); // construye el XLSX en memoria

      // Usa el system picker y pásale los bytes (requisito en Android/iOS)
      final savedUriOrPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar $fileName',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes, // <- CLAVE: sin esto aparece “Bytes are required…”
      );

      if (savedUriOrPath == null) return; // usuario canceló
      showOk('Exportado a:\n$savedUriOrPath');
    } catch (e, st) {
      if (kDebugMode) print(st);
      showErr('Error al exportar: $e');
    }
  }

  // ====== IMPORTAR XLSX ======================================================
  Future<void> _pickAndImport({
    required String label,
    required Future<void> Function(Uint8List) importer,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
      if (result == null || result.files.single.bytes == null) {
        showErr('No seleccionaste archivo.');
        return;
      }
      await importer(result.files.single.bytes!);
      showOk('Importación de $label completa');
    } catch (e) {
      showErr('Error importando $label: $e');
    }
  }

  // ====== RESPALDO / RESTAURAR BD ============================================
  Future<void> _backupDb() async {
    try {
      final path = await _dbPath();
      final bytes = await File(path).readAsBytes();

      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar respaldo de BD',
        fileName: 'pdv.db',
        type: FileType.custom,
        // en algunos dispositivos falla el filtro .db; igual pasamos bytes,
        // si el picker ignora la extensión no hay problema
        allowedExtensions: const ['db'],
        bytes: bytes,
      );
      if (saved == null) return;
      showOk('BD guardada en:\n$saved');
    } catch (e) {
      showErr('Error al respaldar BD: $e');
    }
  }

  Future<void> _restoreDb() async {
    try {
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.any, // <- algunos Android rompen con filter .db
        withData: true,
      );
      if (pick == null || pick.files.single.bytes == null) {
        showErr('No seleccionaste archivo .db');
        return;
      }
      final name = (pick.files.single.name).toLowerCase();
      if (!name.endsWith('.db')) {
        showErr('Selecciona un archivo con extensión .db');
        return;
      }
      final dest = await _dbPath();
      await File(dest).writeAsBytes(pick.files.single.bytes!, flush: true);
      showOk('BD restaurada. Reinicia la app para ver los cambios.');
    } catch (e) {
      showErr('Error al restaurar BD: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final wrapPad = const EdgeInsets.symmetric(vertical: 4);
    return Scaffold(
      appBar: AppBar(title: const Text('Respaldo / XLSX / BD')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Exportar a XLSX',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            Padding(
              padding: wrapPad,
              child: ElevatedButton(
                onPressed: () => _export(
                  fileName: 'products.xlsx',
                  builder: xio.buildProductsXlsxBytes,
                ),
                child: const Text('Productos'),
              ),
            ),
            Padding(
              padding: wrapPad,
              child: ElevatedButton(
                onPressed: () => _export(
                  fileName: 'clients.xlsx',
                  builder: xio.buildClientsXlsxBytes,
                ),
                child: const Text('Clientes'),
              ),
            ),
            Padding(
              padding: wrapPad,
              child: ElevatedButton(
                onPressed: () => _export(
                  fileName: 'suppliers.xlsx',
                  builder: xio.buildSuppliersXlsxBytes,
                ),
                child: const Text('Proveedores'),
              ),
            ),
            Padding(
              padding: wrapPad,
              child: ElevatedButton(
                onPressed: () => _export(
                  fileName: 'sales.xlsx',
                  builder: xio.buildSalesXlsxBytes,
                ),
                child: const Text('Ventas'),
              ),
            ),
            Padding(
              padding: wrapPad,
              child: ElevatedButton(
                onPressed: () => _export(
                  fileName: 'purchases.xlsx',
                  builder: xio.buildPurchasesXlsxBytes,
                ),
                child: const Text('Compras'),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          const Text('Importar desde XLSX (elige archivo)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            OutlinedButton(
              onPressed: () => _pickAndImport(
                  label: 'Productos', importer: xio.importProductsXlsxBytes),
              child: const Text('Productos'),
            ),
            OutlinedButton(
              onPressed: () => _pickAndImport(
                  label: 'Clientes', importer: xio.importClientsXlsxBytes),
              child: const Text('Clientes'),
            ),
            OutlinedButton(
              onPressed: () => _pickAndImport(
                  label: 'Proveedores',
                  importer: xio.importSuppliersXlsxBytes),
              child: const Text('Proveedores'),
            ),
            OutlinedButton(
              onPressed: () => _pickAndImport(
                  label: 'Ventas', importer: xio.importSalesXlsxBytes),
              child: const Text('Ventas'),
            ),
            OutlinedButton(
              onPressed: () => _pickAndImport(
                  label: 'Compras', importer: xio.importPurchasesXlsxBytes),
              child: const Text('Compras'),
            ),
          ]),
          const SizedBox(height: 24),
          const Text('Respaldo de Base de Datos (.db)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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