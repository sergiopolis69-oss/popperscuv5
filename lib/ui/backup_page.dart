import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/xlsx_io.dart';
import '../data/database.dart' as appdb;

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  String? _lastMsg;
  void _snack(String m) {
    setState(() => _lastMsg = m);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // --------- helpers comunes ----------
  Future<Uint8List?> _pickXlsxBytes() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return null;
    final f = res.files.first;
    if (f.bytes != null) return f.bytes!;
    if (f.path != null) return await File(f.path!).readAsBytes();
    return null;
  }

  Future<bool> _ensureStorageReadPermissionIfNeeded() async {
    if (!Platform.isAndroid) return true;
    // En Android 13+ el permiso de lectura “clásico” ya no aplica a Descargas -> usa selector.
    final status = await Permission.storage.status;
    if (status.isGranted) return true;
    final req = await Permission.storage.request();
    return req.isGranted;
  }

  Future<Uint8List?> _readFromDownloadsByName(String fileName) async {
    final dir = Directory('/storage/emulated/0/Download');
    final f = File(p.join(dir.path, fileName));
    if (!await f.exists()) return null;
    return await f.readAsBytes();
  }

  Future<void> _importFlow({
    required String fixedFileName,
    required Future<void> Function(Uint8List) importer,
  }) async {
    // 1) Selector (recomendado y sin permisos)
    final picked = await _pickXlsxBytes();
    if (picked != null) {
      try {
        await importer(picked);
        _snack('Importado correctamente (selector).');
      } catch (e) {
        _snack('Error al importar: $e');
      }
      return;
    }

    // 2) Fallback: Descargas con nombre fijo
    final ok = await _ensureStorageReadPermissionIfNeeded();
    if (!ok) {
      _snack('No hay permiso para leer Descargas. Usa el selector de archivos.');
      return;
    }
    try {
      final bytes = await _readFromDownloadsByName(fixedFileName);
      if (bytes == null) {
        _snack('No se encontró $fixedFileName en Descargas.');
        return;
      }
      await importer(bytes);
      _snack('Importado correctamente (Descargas).');
    } catch (e) {
      _snack('Error leyendo $fixedFileName: $e');
    }
  }

  Future<void> _export({
    required String fileName,
    required Future<List<int>> Function() builder,
  }) async {
    try {
      final bytes = await builder();
      final savedPath = await saveBytesWithSystemPicker(
        fileName: fileName,
        bytes: bytes,
      );
      _snack('Exportado: $savedPath');
    } catch (e) {
      _snack('Error al exportar: $e');
    }
  }

  // ---------- Respaldo / Restauración de BD ----------
  Future<String> _dbFilePath() async {
    final db = await appdb.getDb();
    return p.normalize(db.path);
  }

  Future<void> _backupDbToDownloads() async {
    try {
      final path = await _dbFilePath();
      final bytes = await File(path).readAsBytes();
      final saved = await saveBytesWithSystemPicker(
        fileName: p.basename(path),
        bytes: bytes,
      );
      _snack('BD respaldada en: $saved');
    } catch (e) {
      _snack('Error al respaldar BD: $e');
    }
  }

  Future<void> _restoreDbFromPicker() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['db'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final file = res.files.first;
      final bytes =
          file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null) {
        _snack('No se pudo leer el archivo .db.');
        return;
      }

      // Cierra BD actual, reemplaza archivo y vuelve a abrir.
      final db = await appdb.getDb();
      await db.close();
      final dst = await _dbFilePath();
      await File(dst).writeAsBytes(bytes, flush: true);
      // Fuerza reapertura inmediata
      await appdb.getDb();

      _snack('Base de datos restaurada. (Si algo no se refleja, reinicia la app)');
    } catch (e) {
      _snack('Error al restaurar BD: $e');
    }
  }

  // ---------- UI ----------
  Widget _exportButtons() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton(
          onPressed: () => _export(fileName: 'products.xlsx', builder: buildProductsXlsxBytes),
          child: const Text('Productos'),
        ),
        FilledButton(
          onPressed: () => _export(fileName: 'clients.xlsx', builder: buildClientsXlsxBytes),
          child: const Text('Clientes'),
        ),
        FilledButton(
          onPressed: () => _export(fileName: 'suppliers.xlsx', builder: buildSuppliersXlsxBytes),
          child: const Text('Proveedores'),
        ),
        FilledButton(
          onPressed: () => _export(fileName: 'sales.xlsx', builder: buildSalesXlsxBytes),
          child: const Text('Ventas'),
        ),
        FilledButton(
          onPressed: () => _export(fileName: 'purchases.xlsx', builder: buildPurchasesXlsxBytes),
          child: const Text('Compras'),
        ),
      ],
    );
  }

  Widget _importButtons() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        OutlinedButton(
          onPressed: () => _importFlow(
            fixedFileName: 'products.xlsx',
            importer: importProductsXlsx,
          ),
          child: const Text('Productos'),
        ),
        OutlinedButton(
          onPressed: () => _importFlow(
            fixedFileName: 'clients.xlsx',
            importer: importClientsXlsx,
          ),
          child: const Text('Clientes'),
        ),
        OutlinedButton(
          onPressed: () => _importFlow(
            fixedFileName: 'suppliers.xlsx',
            importer: importSuppliersXlsx,
          ),
          child: const Text('Proveedores'),
        ),
        OutlinedButton(
          onPressed: () => _importFlow(
            fixedFileName: 'sales.xlsx',
            importer: importSalesXlsx,
          ),
          child: const Text('Ventas'),
        ),
        OutlinedButton(
          onPressed: () => _importFlow(
            fixedFileName: 'purchases.xlsx',
            importer: importPurchasesXlsx,
          ),
          child: const Text('Compras'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Respaldo / XLSX / BD')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Exportar a XLSX', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _exportButtons(),
          const SizedBox(height: 24),
          const Text(
            'Importar desde XLSX (elige archivo o intenta Descargas con nombre esperado)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          _importButtons(),
          const SizedBox(height: 24),
          const Divider(),
          const Text('Respaldo de Base de Datos (.db)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: _backupDbToDownloads,
                child: const Text('Respaldar BD a Descargas'),
              ),
              OutlinedButton(
                onPressed: _restoreDbFromPicker,
                child: const Text('Restaurar BD desde archivo'),
              ),
            ],
          ),
          if (_lastMsg != null) ...[
            const SizedBox(height: 16),
            Text(_lastMsg!, style: const TextStyle(color: Colors.black54)),
          ],
        ],
      ),
    );
  }
}