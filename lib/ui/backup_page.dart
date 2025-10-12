import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/xlsx_io.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;

  Future<String> _saveXlsx(String baseName, Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '')
        .replaceAll('-', '')
        .replaceAll('T', '_');
    final file = File('${dir.path}/$baseName-$ts.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _exportBytes({
    required String what,
    required Future<Uint8List> Function() builder,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await builder();
      final path = await _saveXlsx(what.toLowerCase(), bytes);

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Exportación de $what'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Archivo guardado en:'),
              const SizedBox(height: 8),
              SelectableText(
                path,
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: path));
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ruta copiada al portapapeles')),
                );
              },
              child: const Text('Copiar ruta'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error exportando $what: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importXlsx<T>({
    required String what,
    required Future<T> Function(Uint8List) fn,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await pickXlsxBytes();
      final result = await fn(bytes);

      if (!mounted) return;

      // Soportamos ImportReport (definida en xlsx_io.dart)
      String summary;
      if (result is ImportReport) {
        final errCount = result.errors.length;
        summary =
            'Insertados: ${result.inserted}\nActualizados: ${result.updated}\nOmitidos: ${result.skipped}\n${errCount > 0 ? "Errores: $errCount" : ""}';
      } else {
        summary = 'Importación finalizada.';
      }

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Importación de $what'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Text(summary),
            ),
          ),
          actions: [
            if (result is ImportReport && result.errors.isNotEmpty)
              TextButton(
                onPressed: () async {
                  await showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Errores'),
                      content: SizedBox(
                        width: 420,
                        height: 300,
                        child: SingleChildScrollView(
                          child: Text(result.errors.join('\n')),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cerrar'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Ver errores'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error importando $what: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expButtons = [
      FilledButton(
        onPressed: _busy
            ? null
            : () => _exportBytes(
                  what: 'Productos',
                  builder: rebuildProductsXlsxBytes,
                ),
        child: const Text('Productos'),
      ),
      FilledButton(
        onPressed: _busy
            ? null
            : () => _exportBytes(
                  what: 'Clientes',
                  builder: rebuildClientsXlsxBytes,
                ),
        child: const Text('Clientes'),
      ),
      FilledButton(
        onPressed: _busy
            ? null
            : () => _exportBytes(
                  what: 'Proveedores',
                  builder: rebuildSuppliersXlsxBytes,
                ),
        child: const Text('Proveedores'),
      ),
      FilledButton(
        onPressed: _busy
            ? null
            : () => _exportBytes(
                  what: 'Ventas',
                  builder: rebuildSalesXlsxBytes,
                ),
        child: const Text('Ventas'),
      ),
      FilledButton(
        onPressed: _busy
            ? null
            : () => _exportBytes(
                  what: 'Compras',
                  builder: rebuildPurchasesXlsxBytes,
                ),
        child: const Text('Compras'),
      ),
    ];

    final impButtons = [
      OutlinedButton(
        onPressed: _busy
            ? null
            : () => _importXlsx<ImportReport>(
                  what: 'Productos',
                  fn: importProductsXlsx,
                ),
        child: const Text('Productos'),
      ),
      OutlinedButton(
        onPressed: _busy
            ? null
            : () => _importXlsx<ImportReport>(
                  what: 'Clientes',
                  fn: importClientsXlsx,
                ),
        child: const Text('Clientes'),
      ),
      OutlinedButton(
        onPressed: _busy
            ? null
            : () => _importXlsx<ImportReport>(
                  what: 'Proveedores',
                  fn: importSuppliersXlsx,
                ),
        child: const Text('Proveedores'),
      ),
      OutlinedButton(
        onPressed: _busy
            ? null
            : () => _importXlsx<ImportReport>(
                  what: 'Ventas',
                  fn: importSalesXlsx,
                ),
        child: const Text('Ventas'),
      ),
      OutlinedButton(
        onPressed: _busy
            ? null
            : () => _importXlsx<ImportReport>(
                  what: 'Compras',
                  fn: importPurchasesXlsx,
                ),
        child: const Text('Compras'),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Respaldo / XLSX'),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Exportar a XLSX',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: expButtons,
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 24),
                const Text(
                  'Importar desde XLSX',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: impButtons,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Notas:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                    '• Los archivos se guardan en el directorio de documentos de la app. '
                    'Usa “Copiar ruta” para acceder desde un explorador de archivos.\n'
                    '• La importación valida SKU único (productos) y teléfono (clientes/proveedores).'),
              ],
            ),
            if (_busy)
              Container(
                color: Colors.black.withOpacity(0.05),
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}