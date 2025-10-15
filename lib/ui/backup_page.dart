import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:popperscuv5/utils/xlsx_io.dart' as xio;

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  String? _status;

  Future<void> _pickAndImport({
    required String label,
    required Future<void> Function(Uint8List) importer,
    List<String> allowed = const ['xlsx'],
  }) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowed,
        withData: true,
      );
      final bytes = res?.files.single.bytes;
      if (bytes == null) {
        setState(() => _status = 'Cancelado.');
        return;
      }
      await importer(bytes);
      setState(() => _status = 'Importado $label correctamente.');
    } catch (e) {
      setState(() => _status = 'Error importando $label: $e');
    }
  }

  Future<String?> _saveBytesWithPicker({
    required String fileName,
    required Uint8List bytes,
    required List<String> allowed,
  }) async {
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar como…',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: allowed,
    );
    if (savePath == null) return null;
    final f = File(savePath);
    await f.writeAsBytes(bytes, flush: true);
    return savePath;
  }

  Future<void> _exportXlsx({
    required String fileName,
    required Future<Uint8List> Function() builder,
  }) async {
    try {
      final bytes = await builder();
      final saved = await _saveBytesWithPicker(
        fileName: fileName,
        bytes: bytes,
        allowed: const ['xlsx'],
      );
      setState(() => _status = saved == null ? 'Cancelado.' : 'Guardado en: $saved');
    } catch (e) {
      setState(() => _status = 'Error al exportar: $e');
    }
  }

  Future<void> _backupDbToPicker() async {
    try {
      final dbPath = p.join(await getDatabasesPath(), 'pdv.db');
      final src = File(dbPath);
      if (!await src.exists()) {
        setState(() => _status = 'No se encontró la BD.');
        return;
      }
      final bytes = await src.readAsBytes();
      final saved = await _saveBytesWithPicker(
        fileName: 'pdv.db',
        bytes: bytes,
        allowed: const ['db'],
      );
      setState(() => _status = saved == null ? 'Cancelado.' : 'BD guardada en: $saved');
    } catch (e) {
      setState(() => _status = 'Error al respaldar BD: $e');
    }
  }

  Future<void> _restoreDbFromPicker() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['db'], // sin punto
        withData: true,
      );
      final bytes = picked?.files.single.bytes;
      if (bytes == null) {
        setState(() => _status = 'Cancelado.');
        return;
      }
      final dbPath = p.join(await getDatabasesPath(), 'pdv.db');
      // Cierra DB si está abierta (sqflite la cierra al reemplazar)
      await File(dbPath).writeAsBytes(bytes, flush: true);
      setState(() => _status = 'BD restaurada. Reinicia la app para aplicar.');
    } catch (e) {
      setState(() => _status = 'Error al restaurar BD: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = const EdgeInsets.symmetric(horizontal: 24, vertical: 8);
    return Scaffold(
      appBar: AppBar(title: const Text('Respaldo / XLSX / BD')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            child: Text('Exportar a XLSX', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Wrap(
            spacing: 12, runSpacing: 12, alignment: WrapAlignment.start,
            children: [
              ElevatedButton(
                onPressed: () => _exportXlsx(fileName: 'products.xlsx', builder: xio.buildProductsXlsxBytes),
                child: const Text('Productos'),
              ),
              ElevatedButton(
                onPressed: () => _exportXlsx(fileName: 'clients.xlsx', builder: xio.buildClientsXlsxBytes),
                child: const Text('Clientes'),
              ),
              ElevatedButton(
                onPressed: () => _exportXlsx(fileName: 'suppliers.xlsx', builder: xio.buildSuppliersXlsxBytes),
                child: const Text('Proveedores'),
              ),
              ElevatedButton(
                onPressed: () => _exportXlsx(fileName: 'sales.xlsx', builder: xio.buildSalesXlsxBytes),
                child: const Text('Ventas'),
              ),
              ElevatedButton(
                onPressed: () => _exportXlsx(fileName: 'purchases.xlsx', builder: xio.buildPurchasesXlsxBytes),
                child: const Text('Compras'),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Text('Importar desde XLSX (elige archivo)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: pad,
            child: Wrap(spacing: 12, runSpacing: 12, children: [
              OutlinedButton(
                onPressed: () => _pickAndImport(label: 'Productos', importer: xio.importProductsXlsx),
                child: const Text('Productos'),
              ),
              OutlinedButton(
                onPressed: () => _pickAndImport(label: 'Clientes', importer: xio.importClientsXlsx),
                child: const Text('Clientes'),
              ),
              OutlinedButton(
                onPressed: () => _pickAndImport(label: 'Proveedores', importer: xio.importSuppliersXlsx),
                child: const Text('Proveedores'),
              ),
              OutlinedButton(
                onPressed: () => _pickAndImport(label: 'Ventas', importer: xio.importSalesXlsx),
                child: const Text('Ventas'),
              ),
              OutlinedButton(
                onPressed: () => _pickAndImport(label: 'Compras', importer: xio.importPurchasesXlsx),
                child: const Text('Compras'),
              ),
            ]),
          ),
          const Divider(height: 32),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            child: Text('Respaldo de Base de Datos (.db)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: pad,
            child: Wrap(spacing: 12, runSpacing: 12, children: [
              ElevatedButton(onPressed: _backupDbToPicker, child: const Text('Respaldar BD')),
              OutlinedButton(onPressed: _restoreDbFromPicker, child: const Text('Restaurar BD')),
            ]),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_status!, style: const TextStyle(color: Colors.grey)),
            ),
        ],
      ),
    );
  }
}