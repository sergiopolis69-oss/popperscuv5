import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/xlsx_io.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;

  Future<void> _export(
    BuildContext ctx,
    String what,
    Future<String> Function() fn,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final savedPath = await fn();

      // Snack con acceso rápido (copiar ruta)
      if (mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('$what exportado a:\n$savedPath'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Copiar ruta',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: savedPath));
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Error exportando $what: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[
      const SizedBox(height: 12),
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
            onPressed: _busy ? null : () => _export(context, 'Productos', exportProductsXlsx),
            child: const Text('Productos'),
          ),
          FilledButton(
            onPressed: _busy ? null : () => _export(context, 'Clientes', exportClientsXlsx),
            child: const Text('Clientes'),
          ),
          FilledButton(
            onPressed: _busy ? null : () => _export(context, 'Proveedores', exportSuppliersXlsx),
            child: const Text('Proveedores'),
          ),
          FilledButton(
            onPressed: _busy ? null : () => _export(context, 'Ventas', exportSalesXlsx),
            child: const Text('Ventas'),
          ),
          FilledButton(
            onPressed: _busy ? null : () => _export(context, 'Compras', exportPurchasesXlsx),
            child: const Text('Compras'),
          ),
        ],
      ),
      const SizedBox(height: 24),
      const Divider(),
      const SizedBox(height: 12),
      const Text(
        'Importar desde XLSX',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      const Text(
        'La importación permanece igual que la versión actual. '
        'Cuando activemos el selector nuevamente, se mostrarán los resultados aquí.',
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Respaldo XLSX')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: widgets),
      ),
    );
  }
}