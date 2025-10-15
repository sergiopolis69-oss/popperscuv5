// lib/ui/backup_page.dart
import 'dart:typed_data';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
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
  // --- Snackbars locales ---
  void showOk(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  void showErr(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(backgroundColor: Colors.red.shade700, content: Text(msg)));

  // --- Helpers de DB / Paths ---
  Future<Database> _db() => appdb.getDb();
  Future<String> _dbPath() async => (await _db()).path;

  // --- IO helpers con File ---
  Future<Uint8List> readBytesFromPath(String path) async =>
      await File(path).readAsBytes();

  Future<void> writeBytesToPath(String path, Uint8List bytes) async {
    final f = File(path);
    await f.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
  }

  // --- Exportar a XLSX (elige destino con picker) ---
  Future<void> _export({
    required String fileName,
    required Future<Uint8List> Function() builder,
  }) async {
    try {
      final bytes = await builder();
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar $fileName',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'], // sin punto
      );
      if (savePath == null) return; // cancelado
      await writeBytesToPath(savePath, bytes);
      showOk('Exportado a:\n$savePath');
    } catch (e) {
      showErr('Error al exportar: $e');
    }
  }

  // --- Importar XLSX (elegir archivo) ---
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

  // --- Respaldo de BD ---
  Future<void> _backupDb() async {
    try {
      final bytes = await readBytesFromPath(await _dbPath());
      final dest = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar respaldo de BD',
        fileName: 'pdv.db',
        type: FileType.custom,
        allowedExtensions: const ['db'],
      );
      if (dest == null) return;
      await writeBytesToPath(dest, bytes);
      showOk('BD guardada en:\n$dest');
    } catch (e) {
      showErr('Error al respaldar BD: $e');
    }
  }

  // --- Restaurar BD (.db) ---
  Future<void> _restoreDb() async {
    try {
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['db'],
        withData: true,
      );
      if (pick == null || pick.files.single.bytes == null) {
        showErr('No seleccionaste archivo .db');
        return;
      }
      await writeBytesToPath(await _dbPath(), pick.files.single.bytes!);
      showOk('BD restaurada. Reinicia la app para ver cambios.');
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
          const Text('Exportar a XLSX',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            ElevatedButton(
              onPressed: () => _export(
                  fileName: 'products.xlsx',
                  builder: xio.buildProductsXlsxBytes),
              child: const Text('Productos'),
            ),
            ElevatedButton(
              onPressed: () => _export(
                  fileName: 'clients.xlsx',
                  builder: xio.buildClientsXlsxBytes),
              child: const Text('Clientes'),
            ),
            ElevatedButton(
              onPressed: () => _export(
                  fileName: 'suppliers.xlsx',
                  builder: xio.buildSuppliersXlsxBytes),
              child: const Text('Proveedores'),
            ),
            ElevatedButton(
              onPressed: () => _export(
                  fileName: 'sales.xlsx', builder: xio.buildSalesXlsxBytes),
              child: const Text('Ventas'),
            ),
            ElevatedButton(
              onPressed: () => _export(
                  fileName: 'purchases.xlsx',
                  builder: xio.buildPurchasesXlsxBytes),
              child: const Text('Compras'),
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