// lib/ui/backup_page.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import '../data/database.dart' as appdb;
import '../utils/xlsx_io.dart' as xio;

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  // ---------- Helpers comunes ----------
  Future<Directory> _downloadsDir() async {
    if (Platform.isAndroid) {
      final d = Directory('/storage/emulated/0/Download');
      if (await d.exists()) return d;
      // fallback
      return await getApplicationDocumentsDirectory();
    }
    return await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _doExportXlsx({
    required String name,
    required Future<List<int>> Function() buildBytes,
  }) async {
    try {
      final bytes = await buildBytes();
      final path = await xio.saveBytesToDownloads(
        context,
        fileName: '$name.xlsx',
        bytes: bytes,
      );
      _snack('Exportado: $path');
    } catch (e) {
      _snack('Error al exportar $name: $e');
    }
  }

  Future<Uint8List?> _readFromDownloads(String fileName) async {
    try {
      final dir = await _downloadsDir();
      final f = File(p.join(dir.path, fileName));
      if (!await f.exists()) {
        _snack('No se encontró ${f.path}');
        return null;
      }
      return await f.readAsBytes();
    } catch (e) {
      _snack('Error leyendo $fileName: $e');
      return null;
    }
  }

  Future<void> _doImportXlsx({
    required String niceName,
    required String fileName,
    required Future<void> Function(Uint8List bytes) importer,
  }) async {
    try {
      final bytes = await _readFromDownloads(fileName);
      if (bytes == null) return;
      await importer(bytes);
      _snack('Importación de $niceName terminada.');
    } catch (e) {
      _snack('Error al importar $niceName: $e');
    }
  }

  // ---------- Respaldo / Restauración de BD ----------
  Future<String> _dbPath() async {
    final base = await getDatabasesPath();
    return p.join(base, 'pdv.db'); // Debe coincidir con DatabaseHelper._dbName
  }

  String _ts() {
    final d = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}-${two(d.hour)}${two(d.minute)}${two(d.second)}';
  }

  Future<void> _backupDbToDownloads() async {
    try {
      final srcPath = await _dbPath();
      final srcFile = File(srcPath);
      if (!await srcFile.exists()) {
        _snack('No existe la BD en $srcPath');
        return;
      }
      final dstDir = await _downloadsDir();
      final dstPath = p.join(dstDir.path, 'pdv-backup-${_ts()}.db');
      await srcFile.copy(dstPath);
      _snack('BD respaldada en: $dstPath');
    } catch (e) {
      _snack('Error al respaldar BD: $e');
    }
  }

  Future<void> _restoreDbFromLatestBackup() async {
    try {
      final dir = await _downloadsDir();
      final list = (await dir.list().toList())
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('pdv-backup-') && f.path.endsWith('.db'))
          .toList();

      if (list.isEmpty) {
        _snack('No se encontró ningún pdv-backup-*.db en Descargas');
        return;
      }

      list.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final newest = list.first;

      // Cerramos si es posible (en este diseño, el getter reabre solo).
      // Forzamos reemplazo del archivo (la app se reinicializa sola al volver a abrir).
      final dstPath = await _dbPath();
      final dstFile = File(dstPath);

      // Por seguridad, copia a un nombre temporal y luego reemplaza.
      final tmpPath = '$dstPath.tmp';
      await newest.copy(tmpPath);
      if (await dstFile.exists()) {
        await dstFile.delete();
      }
      await File(tmpPath).rename(dstPath);

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Restauración completada'),
          content: Text('Se restauró la base de datos desde:\n${newest.path}\n\n'
              'Reinicia la app si no ves los cambios de inmediato.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      _snack('Error al restaurar BD: $e');
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Respaldo / XLSX / BD')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Exportar a XLSX',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => _doExportXlsx(
                  name: 'products',
                  buildBytes: xio.buildProductsXlsxBytes,
                ),
                child: const Text('Productos'),
              ),
              FilledButton(
                onPressed: () => _doExportXlsx(
                  name: 'clients',
                  buildBytes: xio.buildClientsXlsxBytes,
                ),
                child: const Text('Clientes'),
              ),
              FilledButton(
                onPressed: () => _doExportXlsx(
                  name: 'suppliers',
                  buildBytes: xio.buildSuppliersXlsxBytes,
                ),
                child: const Text('Proveedores'),
              ),
              FilledButton(
                onPressed: () => _doExportXlsx(
                  name: 'sales',
                  buildBytes: xio.buildSalesXlsxBytes,
                ),
                child: const Text('Ventas'),
              ),
              FilledButton(
                onPressed: () => _doExportXlsx(
                  name: 'purchases',
                  buildBytes: xio.buildPurchasesXlsxBytes,
                ),
                child: const Text('Compras'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Importar desde XLSX (archivo en Descargas con nombre esperado)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _doImportXlsx(
                  niceName: 'Productos',
                  fileName: 'products.xlsx',
                  importer: xio.importProductsXlsx,
                ),
                child: const Text('Productos'),
              ),
              OutlinedButton(
                onPressed: () => _doImportXlsx(
                  niceName: 'Clientes',
                  fileName: 'clients.xlsx',
                  importer: xio.importClientsXlsx,
                ),
                child: const Text('Clientes'),
              ),
              OutlinedButton(
                onPressed: () => _doImportXlsx(
                  niceName: 'Proveedores',
                  fileName: 'suppliers.xlsx',
                  importer: xio.importSuppliersXlsx,
                ),
                child: const Text('Proveedores'),
              ),
              OutlinedButton(
                onPressed: () => _doImportXlsx(
                  niceName: 'Ventas',
                  fileName: 'sales.xlsx',
                  importer: xio.importSalesXlsx,
                ),
                child: const Text('Ventas'),
              ),
              OutlinedButton(
                onPressed: () => _doImportXlsx(
                  niceName: 'Compras',
                  fileName: 'purchases.xlsx',
                  importer: xio.importPurchasesXlsx,
                ),
                child: const Text('Compras'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          const Text(
            'Respaldo de Base de Datos (.db)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: _backupDbToDownloads,
                child: const Text('Respaldar BD a Descargas'),
              ),
              FilledButton.tonal(
                onPressed: _restoreDbFromLatestBackup,
                child: const Text('Restaurar BD (último backup en Descargas)'),
              ),
              OutlinedButton(
                onPressed: () async {
                  final path = await _dbPath();
                  if (!mounted) return;
                  await showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Ruta de la BD'),
                      content: SelectableText(path),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Ver ruta actual de la BD'),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}