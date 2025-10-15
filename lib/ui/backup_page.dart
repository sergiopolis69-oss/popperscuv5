import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as ex;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:popperscuv5/utils/xlsx_io.dart' as xio;
import 'package:popperscuv5/data/database.dart' as appdb;

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ---------- helpers ----------
  Future<Uint8List?> _pickXlsxBytes({String? suggestedName}) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        dialogTitle: 'Selecciona un archivo XLSX',
        withData: true,
      );
      if (res != null && res.files.single.bytes != null) {
        return res.files.single.bytes!;
      }
      // fallback: intenta /Download/<suggestedName>
      if (suggestedName != null) {
        final file =
            File('/storage/emulated/0/Download/$suggestedName');
        if (await file.exists()) {
          return await file.readAsBytes();
        }
      }
      return null;
    } catch (e) {
      _snack('No se pudo abrir el archivo: $e');
      return null;
    }
  }

  Future<void> _exportXlsx(Future<void> Function() fn,
      {required String nameForToast}) async {
    try {
      await fn();
      _snack('Exportado: $nameForToast → Descargas');
    } catch (e) {
      _snack('Error al exportar: $e');
    }
  }

  // ---------- BD ----------
  Future<void> _backupDbToDownloads() async {
    try {
      final dbPath = p.join(await getDatabasesPath(), 'pdv.db');
      final bytes = await File(dbPath).readAsBytes();
      final out = File('/storage/emulated/0/Download/pdv.db');
      await out.writeAsBytes(bytes, flush: true);
      _snack('BD respaldada en Descargas/pdv.db');
    } catch (e) {
      _snack('Error al respaldar BD: $e');
    }
  }

  Future<void> _restoreDbFromPickerOrDownloads() async {
    try {
      Uint8List? bytes;

      // 1) intentar con file picker
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
        dialogTitle: 'Selecciona respaldo .db',
        withData: true,
      );
      if (picked != null && picked.files.single.bytes != null) {
        bytes = picked.files.single.bytes!;
      }

      // 2) fallback desde Descargas/pdv.db
      bytes ??= await () async {
        final f = File('/storage/emulated/0/Download/pdv.db');
        if (await f.exists()) return await f.readAsBytes();
        return null;
      }();

      if (bytes == null) {
        _snack('No seleccionaste archivo y no existe Descargas/pdv.db');
        return;
      }

      // cerrar y reemplazar
      final path = p.join(await getDatabasesPath(), 'pdv.db');
      try {
        await (await appdb.DatabaseHelper.instance.db).close();
      } catch (_) {}
      await File(path).writeAsBytes(bytes, flush: true);

      // “reabrir” perezosamente: el getter lo abrirá en el siguiente acceso
      _snack('BD restaurada. Reinicia la app para asegurar apertura limpia.');
    } catch (e) {
      _snack('Error al restaurar BD: $e');
    }
  }

  // ---------- IMPORTACIONES ----------
  Future<void> _importProducts() async {
    final bytes = await _pickXlsxBytes(suggestedName: 'products.xlsx');
    if (bytes == null) return;
    try {
      await xio.importProductsXlsx(bytes);
      _snack('Productos importados');
    } catch (e) {
      _snack('Error importando productos: $e');
    }
  }

  Future<void> _importClients() async {
    final bytes = await _pickXlsxBytes(suggestedName: 'clients.xlsx');
    if (bytes == null) return;
    try {
      await xio.importClientsXlsx(bytes);
      _snack('Clientes importados');
    } catch (e) {
      _snack('Error importando clientes: $e');
    }
  }

  Future<void> _importSuppliers() async {
    final bytes = await _pickXlsxBytes(suggestedName: 'suppliers.xlsx');
    if (bytes == null) return;
    try {
      await xio.importSuppliersXlsx(bytes);
      _snack('Proveedores importados');
    } catch (e) {
      _snack('Error importando proveedores: $e');
    }
  }

  Future<void> _importSales() async {
    final bytes = await _pickXlsxBytes(suggestedName: 'sales.xlsx');
    if (bytes == null) return;
    try {
      await xio.importSalesXlsx(bytes);
      _snack('Ventas importadas');
    } catch (e) {
      _snack('Error importando ventas: $e');
    }
  }

  Future<void> _importPurchases() async {
    final bytes = await _pickXlsxBytes(suggestedName: 'purchases.xlsx');
    if (bytes == null) return;
    try {
      await xio.importPurchasesXlsx(bytes);
      _snack('Compras importadas');
    } catch (e) {
      _snack('Error importando compras: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Respaldo / XLSX / BD')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Exportar a XLSX', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            FilledButton(
              onPressed: () => _exportXlsx(xio.exportProductsXlsx, nameForToast: 'products.xlsx'),
              child: const Text('Productos'),
            ),
            FilledButton(
              onPressed: () => _exportXlsx(xio.exportClientsXlsx, nameForToast: 'clients.xlsx'),
              child: const Text('Clientes'),
            ),
            FilledButton(
              onPressed: () => _exportXlsx(xio.exportSuppliersXlsx, nameForToast: 'suppliers.xlsx'),
              child: const Text('Proveedores'),
            ),
            FilledButton(
              onPressed: () => _exportXlsx(xio.exportSalesXlsx, nameForToast: 'sales.xlsx'),
              child: const Text('Ventas'),
            ),
            FilledButton(
              onPressed: () => _exportXlsx(xio.exportPurchasesXlsx, nameForToast: 'purchases.xlsx'),
              child: const Text('Compras'),
            ),
          ]),
          const SizedBox(height: 20),
          Text(
            'Importar desde XLSX (elige archivo o intenta Descargas con nombre esperado)',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            OutlinedButton(onPressed: _importProducts, child: const Text('Productos')),
            OutlinedButton(onPressed: _importClients, child: const Text('Clientes')),
            OutlinedButton(onPressed: _importSuppliers, child: const Text('Proveedores')),
            OutlinedButton(onPressed: _importSales, child: const Text('Ventas')),
            OutlinedButton(onPressed: _importPurchases, child: const Text('Compras')),
          ]),
          const SizedBox(height: 20),
          Text('Respaldo de Base de Datos (.db)', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            FilledButton(
              onPressed: _backupDbToDownloads,
              child: const Text('Respaldar BD a Descargas'),
            ),
            OutlinedButton(
              onPressed: _restoreDbFromPickerOrDownloads,
              child: const Text('Restaurar BD'),
            ),
          ]),
          const SizedBox(height: 24),
          Text(
            'Nota: En Android 10+ puede requerir permitir “Acceso a todos los archivos” para escribir/leer en Descargas.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}