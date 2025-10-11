import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/xlsx_io.dart'; // export*/import* + ImportReport
import '../data/db.dart'; // Asegúrate que expone DatabaseHelper.instance.db

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;

  // Último archivo exportado (si el sistema/plug-in nos devolvió una ruta real)
  String? _lastExportPath;
  // Último binario exportado (para compartir si no tenemos ruta)
  Uint8List? _lastExportBytes;
  String? _lastExportName; // ej: productos_20251011.xlsx

  void _snack(String msg, {String? actionLabel, VoidCallback? onAction}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final sb = SnackBar(
      content: Text(msg),
      action: (actionLabel != null && onAction != null)
          ? SnackBarAction(label: actionLabel, onPressed: onAction)
          : null,
    );
    ScaffoldMessenger.of(context).showSnackBar(sb);
  }

  Future<void> _openLast() async {
    final p = _lastExportPath;
    if (p == null || p.isEmpty) {
      _snack('No hay archivo exportado con ruta disponible');
      return;
    }
    await OpenFilex.open(p);
  }

  Future<void> _shareLast() async {
    if (_lastExportPath != null &&
        _lastExportPath!.isNotEmpty &&
        File(_lastExportPath!).existsSync()) {
      await Share.shareXFiles([XFile(_lastExportPath!)]);
      return;
    }
    if (_lastExportBytes == null || _lastExportBytes!.isEmpty) {
      _snack('No hay archivo exportado para compartir');
      return;
    }
    final tmp = await getTemporaryDirectory();
    final name =
        _lastExportName ?? 'export_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(_lastExportBytes!, flush: true);
    await Share.shareXFiles([XFile(f.path)]);
  }

  Future<void> _export(
    BuildContext ctx,
    String what,
    Future<String?> Function() fnCreateAndSave, {
    required Future<Uint8List> Function() fnRebuildBytes,
    required String suggestName,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    _lastExportPath = null;
    _lastExportBytes = null;
    _lastExportName = null;
    try {
      _snack('Exportando $what…');
      final savedAs = await fnCreateAndSave(); // puede devolver ruta o null
      _lastExportName = suggestName;
      try {
        _lastExportBytes = await fnRebuildBytes();
      } catch (_) {}

      if (!mounted) return;
      if (savedAs != null && savedAs.isNotEmpty) {
        _lastExportPath = savedAs;
        _snack('✔ $what exportado:\n$savedAs',
            actionLabel: 'ABRIR', onAction: _openLast);
      } else {
        _snack('✔ $what exportado. Puedes “Compartir” el archivo.',
            actionLabel: 'COMPARTIR', onAction: _shareLast);
      }
      setState(() {});
    } catch (e) {
      _snack('✖ Error al exportar $what: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import(
    BuildContext ctx,
    String what,
    Future<ImportReport> Function(Uint8List) fn,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await pickXlsxBytes();
      if (bytes == null) {
        _snack('Importación cancelada');
        return;
      }
      _snack('Importando $what…');
      final rep = await fn(bytes);
      _snack('✔ $what importado.\n${rep.toString()}');
    } catch (e) {
      _snack('✖ Error al importar $what: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = const EdgeInsets.all(12);
    final hasLast = (_lastExportPath != null && _lastExportPath!.isNotEmpty) ||
        (_lastExportBytes != null);

    return AbsorbPointer(
      absorbing: _busy,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Exportar a Excel (.xlsx)',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: pad,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: () => _export(
                          context,
                          'Productos',
                          exportProductsXlsx,
                          fnRebuildBytes: rebuildProductsXlsxBytes,
                          suggestName: 'productos.xlsx',
                        ),
                        child: const Text('Productos'),
                      ),
                      FilledButton(
                        onPressed: () => _export(
                          context,
                          'Clientes',
                          exportClientsXlsx,
                          fnRebuildBytes: rebuildClientsXlsxBytes,
                          suggestName: 'clientes.xlsx',
                        ),
                        child: const Text('Clientes'),
                      ),
                      FilledButton(
                        onPressed: () => _export(
                          context,
                          'Proveedores',
                          exportSuppliersXlsx,
                          fnRebuildBytes: rebuildSuppliersXlsxBytes,
                          suggestName: 'proveedores.xlsx',
                        ),
                        child: const Text('Proveedores'),
                      ),
                      FilledButton(
                        onPressed: () => _export(
                          context,
                          'Ventas',
                          exportSalesXlsx,
                          fnRebuildBytes: rebuildSalesXlsxBytes,
                          suggestName: 'ventas.xlsx',
                        ),
                        child: const Text('Ventas'),
                      ),
                      FilledButton(
                        onPressed: () => _export(
                          context,
                          'Compras',
                          exportPurchasesXlsx,
                          fnRebuildBytes: rebuildPurchasesXlsxBytes,
                          suggestName: 'compras.xlsx',
                        ),
                        child: const Text('Compras'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (hasLast)
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _openLast,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Abrir último exportado'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _shareLast,
                          icon: const Icon(Icons.share),
                          label: const Text('Compartir último exportado'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Importar desde Excel (.xlsx)',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: pad,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () =>
                        _import(context, 'Productos', importProductsXlsx),
                    child: const Text('Productos'),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        _import(context, 'Clientes', importClientsXlsx),
                    child: const Text('Clientes'),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        _import(context, 'Proveedores', importSuppliersXlsx),
                    child: const Text('Proveedores'),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        _import(context, 'Ventas', importSalesXlsx),
                    child: const Text('Ventas'),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        _import(context, 'Compras', importPurchasesXlsx),
                    child: const Text('Compras'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}