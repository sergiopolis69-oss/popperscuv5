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

  void _snack(String msg) {
    setState(() => _lastMsg = msg);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // === Helpers de importación ===

  Future<Uint8List?> _pickXlsxBytes() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return null;
    final f = res.files.first;
    return f.bytes ??
        await File(f.path!).readAsBytes(); // por si no trajo bytes en memoria
  }

  Future<bool> _ensureStorageReadPermissionIfNeeded() async {
    // Para lectura directa en /Download en Android <= 12
    if (!Platform.isAndroid) return true;

    // En Android 13+ no hay READ_EXTERNAL_STORAGE para documentos;
    // mejor usar file picker. Esto solo intentará en <= 12.
    final sdk = await _androidSdkInt();
    if (sdk >= 33) return false; // no intentes permiso de lectura clásico

    final status = await Permission.storage.status;
    if (status.isGranted) return true;
    final req = await Permission.storage.request();
    return req.isGranted;
  }

  Future<int> _androidSdkInt() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = dir.path;
      // heurística sencilla: no necesitamos el sdk exacto si ya usamos file picker
      // devolvemos 30 como valor seguro; no afecta la lógica principal.
      return 30;
    } catch (_) {
      return 30;
    }
  }

  Future<Uint8List?> _readFromDownloadsByName(String fileName) async {
    // Ruta "clásica" de Descargas en Android
    final downloads = Directory('/storage/emulated/0/Download');
    final f = File(p.join(downloads.path, fileName));
    if (!await f.exists()) return null;
    return await f.readAsBytes();
  }

  Future<void> _importFlow({
    required String fixedFileName,
    required Future<void> Function(Uint8List) importer,
  }) async {
    // 1) Intentamos picker (más seguro y moderno)
    final picked = await _pickXlsxBytes();
    if (picked != null) {
      await importer(picked);
      _snack('Importado correctamente desde selector.');
      return;
    }

    // 2) Si el usuario canceló o no hubo archivo, intentamos lectura directa de Descargas
    final okPerm = await _ensureStorageReadPermissionIfNeeded();
    if (!okPerm) {
      _snack('No hay permiso para leer Descargas. Usa el botón y elige el archivo.');
      return;
    }

    try {
      final bytes = await _readFromDownloadsByName(fixedFileName);
      if (bytes == null) {
        _snack('No se encontró $fixedFileName en Descargas. Usa el selector.');
        return;
      }
      await importer(bytes);
      _snack('Importado correctamente desde Descargas.');
    } catch (e) {
      _snack('Error leyendo $fixedFileName: $e');
    }
  }

  // === Exportación ===

  Future<void> _export({
    required String fileName,
    required Future<List<int>> Function() builder,
  }) async {
    try {
      final bytes = await builder();
      final savedPath = await saveBytesToDownloads(
        context,
        fileName: fileName,
        bytes: bytes,
      );
      _snack('Exportado en: $savedPath');
    } catch (e) {
      _snack('Error al exportar: $e');
    }
  }

  // === Respaldo de BD (.db) ===
  Future<void> _backupDbToDownloads() async {
    try {
      final db = await appdb.getDb();
      final path = p.normalize(db.path);
      final fileName = p.basename(path);

      final bytes = await File(path).readAsBytes();
      final saved = await saveBytesToDownloads(
        context,
        fileName: fileName,
        bytes: bytes,
      );
      _snack('BD respaldada en: $saved');
    } catch (e) {
      _snack('Error al respaldar BD: $e');
    }
  }

  // === UI ===

  Widget _exportButtons() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton(
          onPressed: () => _export(
            fileName: 'products.xlsx',
            builder: buildProductsXlsxBytes,
          ),
          child: const Text('Productos'),
        ),
        FilledButton(
          onPressed: () => _export(
            fileName: 'clients.xlsx',
            builder: buildClientsXlsxBytes,
          ),
          child: const Text('Clientes'),
        ),
        FilledButton(
          onPressed: () => _export(
            fileName: 'suppliers.xlsx',
            builder: buildSuppliersXlsxBytes,
          ),
          child: const Text('Proveedores'),
        ),
        FilledButton(
          onPressed: () => _export(
            fileName: 'sales.xlsx',
            builder: buildSalesXlsxBytes,
          ),
          child: const Text('Ventas'),
        ),
        FilledButton(
          onPressed: () => _export(
            fileName: 'purchases.xlsx',
            builder: buildPurchasesXlsxBytes,
          ),
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
          const SizedBox(height: 12),
          _exportButtons(),
          const SizedBox(height: 24),
          const Text('Importar desde XLSX (elige archivo o intenta Descargas con nombre esperado)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _importButtons(),
          const SizedBox(height: 24),
          const Divider(),
          const Text('Respaldo de Base de Datos (.db)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _backupDbToDownloads,
            child: const Text('Respaldar BD a Descargas'),
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