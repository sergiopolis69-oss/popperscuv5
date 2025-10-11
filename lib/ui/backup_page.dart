import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../utils/xlsx_io.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _export(
    BuildContext ctx,
    String what,
    Future<String?> Function() fn,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _snack('Exportando $what…');
      final savedAs = await fn();
      if (!mounted) return;
      if (savedAs != null && savedAs.isNotEmpty) {
        _snack('✔ $what exportado: $savedAs');
      } else {
        // Algunas plataformas no devuelven ruta; igual mostramos éxito genérico
        _snack('✔ $what exportado. Revisa la notificación del sistema / Descargas.');
      }
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
    return AbsorbPointer(
      absorbing: _busy,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Exportar a Excel (.xlsx)', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: pad,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: () => _export(context, 'Productos', exportProductsXlsx),
                    child: const Text('Productos'),
                  ),
                  FilledButton(
                    onPressed: () => _export(context, 'Clientes', exportClientsXlsx),
                    child: const Text('Clientes'),
                  ),
                  FilledButton(
                    onPressed: () => _export(context, 'Proveedores', exportSuppliersXlsx),
                    child: const Text('Proveedores'),
                  ),
                  FilledButton(
                    onPressed: () => _export(context, 'Ventas', exportSalesXlsx),
                    child: const Text('Ventas'),
                  ),
                  FilledButton(
                    onPressed: () => _export(context, 'Compras', exportPurchasesXlsx),
                    child: const Text('Compras'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Importar desde Excel (.xlsx)', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: pad,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _import(context, 'Productos', importProductsXlsx),
                    child: const Text('Productos'),
                  ),
                  OutlinedButton(
                    onPressed: () => _import(context, 'Clientes', importClientsXlsx),
                    child: const Text('Clientes'),
                  ),
                  OutlinedButton(
                    onPressed: () => _import(context, 'Proveedores', importSuppliersXlsx),
                    child: const Text('Proveedores'),
                  ),
                  OutlinedButton(
                    onPressed: () => _import(context, 'Ventas', importSalesXlsx),
                    child: const Text('Ventas'),
                  ),
                  OutlinedButton(
                    onPressed: () => _import(context, 'Compras', importPurchasesXlsx),
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