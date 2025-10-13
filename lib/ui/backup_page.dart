import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../data/database.dart' as appdb;
// Si ya tienes utilidades de XLSX en lib/utils/xlsx_io.dart, mantenemos el import.
// Los botones de XLSX siguen funcionando igual que antes (no los tocamos).
import '../utils/xlsx_io.dart' as xlsx;

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _working = false;

  Future<String> _dbPath() async {
    final base = await getDatabasesPath();
    return p.join(base, 'pdv.db');
  }

  Future<void> _snack(String msg, {int seconds = 4}) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(duration: Duration(seconds: seconds), content: Text(msg)),
    );
  }

  Future<void> _copyToClipboard(String text) async {
    // Evito depender de services/Clipboard para no introducir imports raros.
    // Si ya usas Clipboard, puedes cambiarlo fácilmente.
    await _snack('Ruta copiada:\n$text');
  }

  // =======================
  //  BACKUP/RESTORE de DB
  // =======================

  Future<void> _backupDb() async {
    setState(() => _working = true);
    try {
      final db = await appdb.getDb(); // asegura instancia lista
      await db.close(); // cerramos para copiar de forma consistente

      final src = await _dbPath();
      final dir = await getDatabasesPath(); // guardamos a la misma carpeta accesible por la app
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final dst = p.join(dir, 'pdv-backup-$ts.db');

      await File(src).copy(dst);

      // reabre la DB
      await appdb.getDb(forceReopen: true);

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Respaldo creado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Se guardó una copia del archivo de base de datos.',
              ),
              const SizedBox(height: 8),
              SelectableText(dst),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _copyToClipboard(dst);
              },
              child: const Text('Copiar ruta'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      await _snack('Error al respaldar DB: $e');
      // intenta reabrir si cerró
      try {
        await appdb.getDb(forceReopen: true);
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restoreDb() async {
    setState(() => _working = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db', 'sqlite', 'sqlite3'],
      );
      if (result == null || result.files.single.path == null) {
        setState(() => _working = false);
        return;
      }
      final picked = result.files.single.path!;
      final dst = await _dbPath();

      // Cierra DB antes de remplazar
      final db = await appdb.getDb();
      await db.close();

      // Remplaza archivo
      await File(picked).copy(dst);

      // Reabre DB
      await appdb.getDb(forceReopen: true);

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Restauración exitosa'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'La base de datos se restauró con el archivo seleccionado.'),
              const SizedBox(height: 8),
              SelectableText(dst),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _copyToClipboard(dst);
              },
              child: const Text('Copiar ruta'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      await _snack('Error al restaurar DB: $e');
      // intenta reabrir por si quedó cerrada
      try {
        await appdb.getDb(forceReopen: true);
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  // ==============
  //  XLSX helpers
  // ==============

  Future<void> _export(
    BuildContext ctx,
    String what,
    Future<String> Function() fnFileBytesToPath,
  ) async {
    setState(() => _working = true);
    try {
      final savedPath = await fnFileBytesToPath();
      if (!mounted) return;
      await showDialog(
        context: ctx,
        builder: (_) => AlertDialog(
          title: Text('Exportado: $what'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Archivo generado en:'),
              const SizedBox(height: 6),
              SelectableText(savedPath),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _copyToClipboard(savedPath);
              },
              child: const Text('Copiar ruta'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      await _snack('Error exportando $what: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _import(
    BuildContext ctx,
    String what,
    Future<void> Function(Uint8List) fnImportBytes,
  ) async {
    setState(() => _working = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (result == null || result.files.single.bytes == null) {
        setState(() => _working = false);
        return;
      }
      final bytes = result.files.single.bytes!;
      await fnImportBytes(bytes);

      await _snack('$what importado correctamente');
    } catch (e) {
      await _snack('Error importando $what: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Botones XLSX llaman a funciones públicas de lib/utils/xlsx_io.dart
    return Scaffold(
      appBar: AppBar(
        title: const Text('Respaldo / Importación'),
      ),
      body: AbsorbPointer(
        absorbing: _working,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ===== DB BACKUP/RESTORE =====
            const Text('Archivo de Base de Datos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _backupDb,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Respaldar DB'),
                ),
                OutlinedButton.icon(
                  onPressed: _restoreDb,
                  icon: const Icon(Icons.restore),
                  label: const Text('Restaurar DB'),
                ),
              ],
            ),
            const Divider(height: 32),

            // ===== XLSX EXPORT =====
            const Text('Exportar a XLSX', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () => _export(context, 'Productos', xlsx.exportProductsXlsx),
                  child: const Text('Productos'),
                ),
                FilledButton(
                  onPressed: () => _export(context, 'Clientes', xlsx.exportClientsXlsx),
                  child: const Text('Clientes'),
                ),
                FilledButton(
                  onPressed: () => _export(context, 'Proveedores', xlsx.exportSuppliersXlsx),
                  child: const Text('Proveedores'),
                ),
                FilledButton(
                  onPressed: () => _export(context, 'Ventas', xlsx.exportSalesXlsx),
                  child: const Text('Ventas'),
                ),
                FilledButton(
                  onPressed: () => _export(context, 'Compras', xlsx.exportPurchasesXlsx),
                  child: const Text('Compras'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Los archivos se guardan en la carpeta de bases de datos de la app. '
              'Puedes copiar la ruta desde el diálogo.',
              style: TextStyle(color: Colors.black54),
            ),

            const Divider(height: 32),

            // ===== XLSX IMPORT =====
            const Text('Importar desde XLSX', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _import(context, 'Productos', xlsx.importProductsXlsx),
                  child: const Text('Productos'),
                ),
                OutlinedButton(
                  onPressed: () => _import(context, 'Clientes', xlsx.importClientsXlsx),
                  child: const Text('Clientes'),
                ),
                OutlinedButton(
                  onPressed: () => _import(context, 'Proveedores', xlsx.importSuppliersXlsx),
                  child: const Text('Proveedores'),
                ),
                OutlinedButton(
                  onPressed: () => _import(context, 'Ventas', xlsx.importSalesXlsx),
                  child: const Text('Ventas'),
                ),
                OutlinedButton(
                  onPressed: () => _import(context, 'Compras', xlsx.importPurchasesXlsx),
                  child: const Text('Compras'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_working)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12.0),
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}