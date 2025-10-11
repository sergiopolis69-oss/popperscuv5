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

  Future<void> _export(BuildContext ctx, String what, Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
      if (!mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('$what exportado correctamente (.xlsx)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('Error al exportar $what: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import(BuildContext ctx, String what, Future<ImportReport> Function(Uint8List) fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await pickXlsxBytes();
      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Importación cancelada')),
        );
        return;
      }
      final rep = await fn(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('$what importado: ${rep.toString()}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('Error al importar $what: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = const EdgeInsets.symmetric(vertical: 6, horizontal: 8);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          const ListTile(
            leading: Icon(Icons.import_export),
            title: Text('Exportar / Importar (.xlsx)'),
            subtitle: Text('Usa estos botones para respaldar y restaurar por catálogo'),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Exportar', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Padding(
                        padding: pad,
                        child: FilledButton(
                          onPressed: _busy ? null : () => _export(context, 'Productos', exportProductsXlsx),
                          child: const Text('Productos'),
                        ),
                      ),
                      Padding(
                        padding: pad,
                        child: FilledButton(
                          onPressed: _busy ? null : () => _export(context, 'Clientes', exportClientsXlsx),
                          child: const Text('Clientes'),
                        ),
                      ),
                      Padding(
                        padding: pad,
                        child: FilledButton(
                          onPressed: _busy ? null : () => _export(context, 'Proveedores', exportSuppliersXlsx),
                          child: const Text('Proveedores'),
                        ),
                      ),
                      Padding(
                        padding: pad,
                        child: FilledButton(
                          onPressed: _busy ? null : () => _export(context, 'Ventas', exportSalesXlsx),
                          child: const Text('Ventas'),
                        ),
                      ),
                      Padding(
                        padding: pad,
                        child: FilledButton(
                          onPressed: _busy ? null : () => _export(context, 'Compras', exportPurchasesXlsx),
                          child: const Text('Compras'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Importar', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Padding(
                        padding: pad,
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => _import(context, 'Productos', importProductsXlsx),
                          child: const Text('Productos'),
                        ),
                      ),
                      Padding(
                        padding: pad,
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => _import(context, 'Clientes', importClientsXlsx),
                          child: const Text('Clientes'),
                        ),
                      ),
                      Padding(
                        padding: pad,
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => _import(context, 'Proveedores', importSuppliersXlsx),
                          child: const Text('Proveedores'),
                        ),
                      ),
                      Padding(
                        padding: pad,
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => _import(context, 'Ventas', importSalesXlsx),
                          child: const Text('Ventas'),
                        ),
                      ),
                      Padding(
                        padding: pad,
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => _import(context, 'Compras', importPurchasesXlsx),
                          child: const Text('Compras'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Notas:\n• Encabezados requeridos por hoja:'
                    '\n  - products: sku, name, category, default_sale_price, last_purchase_price, stock'
                    '\n  - customers: phone, name, address'
                    '\n  - suppliers: phone, name, address'
                    '\n  - sales: id, customer_phone, payment_method, place, shipping_cost, discount, date'
                    '\n  - sale_items: sale_id, product_sku, quantity, unit_price'
                    '\n  - purchases: id, folio, supplier_id, date'
                    '\n  - purchase_items: purchase_id, product_sku, quantity, unit_cost'
                    '\n• SKU es clave única de producto; no se permiten vacíos ni duplicados.'
                    '\n• En Android 10+ el sistema pedirá ubicación al exportar (política de almacenamiento).',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}