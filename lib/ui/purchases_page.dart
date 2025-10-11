import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db.dart'; // DatabaseHelper.instance.db

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _folioCtrl = TextEditingController();
  DateTime _date = DateTime.now();

  // Proveedor
  final _supplierFilterCtrl = TextEditingController();
  String _selectedSupplierPhone = '';

  // Producto
  final _productSearchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _costCtrl = TextEditingController(text: '0');

  // Carrito: cada item = {sku,name, productId, qty(int), cost(double)}
  final List<Map<String, dynamic>> _cart = [];

  final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- PROVEEDORES ----------

  Future<List<Map<String, dynamic>>> _loadSuppliersFiltered(String q) async {
    final db = await DatabaseHelper.instance.db;
    if (q.trim().isEmpty) {
      return db.query('suppliers', orderBy: 'name COLLATE NOCASE');
    } else {
      final like = '%${q.trim()}%';
      return db.query(
        'suppliers',
        where: 'name LIKE ? OR phone LIKE ?',
        whereArgs: [like, like],
        orderBy: 'name COLLATE NOCASE',
      );
    }
  }

  Future<void> _quickAddSupplierDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addrCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nuevo proveedor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 8),
            TextField(
                controller: phoneCtrl,
                decoration:
                    const InputDecoration(labelText: 'Teléfono (ID)')),
            const SizedBox(height: 8),
            TextField(
                controller: addrCtrl,
                decoration: const InputDecoration(labelText: 'Dirección')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;

    final phone = phoneCtrl.text.trim();
    if (phone.isEmpty) {
      _snack('Teléfono requerido');
      return;
    }
    final db = await DatabaseHelper.instance.db;
    await db.insert(
      'suppliers',
      {'phone': phone, 'name': nameCtrl.text.trim(), 'address': addrCtrl.text},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    setState(() => _selectedSupplierPhone = phone);
    _snack('Proveedor agregado');
  }

  // ---------- PRODUCTOS ----------

  Future<Map<String, dynamic>?> _findProductBySku(String sku) async {
    final db = await DatabaseHelper.instance.db;
    final r = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
    if (r.isEmpty) return null;
    final p = r.first;
    return {
      'id': p['id'],
      'sku': p['sku'],
      'name': p['name'],
      'default_sale_price': (p['default_sale_price'] as num?)?.toDouble() ?? 0.0,
      'last_purchase_price': (p['last_purchase_price'] as num?)?.toDouble() ?? 0.0,
    };
  }

  Future<List<Map<String, dynamic>>> _searchProductsLite(String q) async {
    final db = await DatabaseHelper.instance.db;
    final like = '%${q.trim()}%';
    return db.query(
      'products',
      columns: ['id', 'sku', 'name', 'last_purchase_price'],
      where: 'sku LIKE ? OR name LIKE ?',
      whereArgs: [like, like],
      orderBy: 'name COLLATE NOCASE',
      limit: 20,
    );
  }

  Future<void> _addCurrentSelectionToCart() async {
    final sku = _productSearchCtrl.text.trim();
    if (sku.isEmpty) {
      _snack('Escribe o selecciona un producto');
      return;
    }
    final qty = int.tryParse(_qtyCtrl.text.trim());
    final cost = double.tryParse(_costCtrl.text.trim());
    if (qty == null || qty <= 0 || cost == null || cost < 0) {
      _snack('Cantidad y costo deben ser válidos');
      return;
    }
    final p = await _findProductBySku(sku);
    if (p == null) {
      _snack('Producto no encontrado por SKU');
      return;
    }
    setState(() {
      final idx = _cart.indexWhere((e) => e['sku'] == sku);
      if (idx >= 0) {
        _cart[idx]['qty'] = (_cart[idx]['qty'] as int) + qty;
        _cart[idx]['cost'] = cost; // última captura prevalece
      } else {
        _cart.add({
          'sku': p['sku'],
          'name': p['name'],
          'productId': p['id'],
          'qty': qty,
          'cost': cost,
        });
      }
      // limpiar cantidad para agilizar
      _qtyCtrl.text = '1';
      _costCtrl.text = (p['last_purchase_price'] as double? ?? 0).toStringAsFixed(2);
    });
  }

  double get _cartTotal {
    double t = 0;
    for (final it in _cart) {
      t += (it['qty'] as int) * (it['cost'] as double);
    }
    return t;
    // Nota: El costo de envío NO se maneja en compras.
  }

  // ---------- GUARDAR COMPRA ----------

  Future<void> _savePurchase() async {
    if (_folioCtrl.text.trim().isEmpty) {
      _snack('Folio requerido');
      return;
    }
    if (_selectedSupplierPhone.isEmpty) {
      _snack('Selecciona un proveedor');
      return;
    }
    if (_cart.isEmpty) {
      _snack('No hay productos en la compra');
      return;
    }
    final db = await DatabaseHelper.instance.db;

    try {
      await db.transaction((txn) async {
        final pid = await txn.insert('purchases', {
          'folio': _folioCtrl.text.trim(),
          'supplier_phone': _selectedSupplierPhone,
          'date': _date.toIso8601String(),
        });

        for (final it in _cart) {
          final productId = it['productId'] as int;
          final qty = it['qty'] as int;
          final cost = it['cost'] as double;

          await txn.insert('purchase_items', {
            'purchase_id': pid,
            'product_id': productId,
            'quantity': qty,
            'unit_cost': cost,
          });

          // Actualizar inventario y último costo
          // stock += qty; last_purchase_price = cost
          await txn.rawUpdate(
            'UPDATE products SET stock = COALESCE(stock,0) + ?, last_purchase_price = ? WHERE id = ?',
            [qty, cost, productId],
          );
        }
      });

      if (!mounted) return;
      await _showPurchaseSummary();
      setState(() {
        _cart.clear();
        _folioCtrl.clear();
        _productSearchCtrl.clear();
        _qtyCtrl.text = '1';
        _costCtrl.text = '0';
      });
      _snack('Compra guardada');
    } catch (e) {
      _snack('Error al guardar: $e');
    }
  }

  Future<void> _showPurchaseSummary() async {
    final total = _cartTotal;
    final lines = _cart
        .map((e) =>
            '${e['qty']} × ${e['name']} (${e['sku']})  @ ${_money.format(e['cost'])}')
        .join('\n');

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Compra registrada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Folio: ${_folioCtrl.text}'),
            Text('Proveedor: $_selectedSupplierPhone'),
            const SizedBox(height: 8),
            Text(lines),
            const Divider(),
            Text('Total: ${_money.format(total)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  // ---------- UI ----------

  @override
  void dispose() {
    _folioCtrl.dispose();
    _supplierFilterCtrl.dispose();
    _productSearchCtrl.dispose();
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = const EdgeInsets.all(12);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Cabecera: Folio + Fecha
        Card(
          child: Padding(
            padding: pad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nueva compra', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _folioCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Folio',
                          prefixIcon: Icon(Icons.confirmation_number),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.date_range),
                      label: Text(DateFormat('yyyy-MM-dd').format(_date)),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setState(() => _date = picked);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Proveedor: filtro + dropdown + +nuevo
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: _loadSuppliersFiltered(_supplierFilterCtrl.text),
                        builder: (context, snap) {
                          final opts = snap.data ?? const [];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                controller: _supplierFilterCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Buscar proveedor (nombre/teléfono)',
                                  prefixIcon: Icon(Icons.search),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: _selectedSupplierPhone.isEmpty
                                    ? null
                                    : _selectedSupplierPhone,
                                items: opts.map((e) {
                                  final phone = (e['phone'] ?? '').toString();
                                  final name = (e['name'] ?? '').toString();
                                  return DropdownMenuItem<String>(
                                    value: phone,
                                    child: Text('$name  •  $phone',
                                        overflow: TextOverflow.ellipsis),
                                  );
                                }).toList(),
                                decoration: const InputDecoration(
                                  labelText: 'Proveedor',
                                ),
                                onChanged: (v) =>
                                    setState(() => _selectedSupplierPhone = v ?? ''),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Nuevo'),
                      onPressed: () => _quickAddSupplierDialog(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Productos: búsqueda + qty + cost + agregar
        Card(
          child: Padding(
            padding: pad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Productos', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, c) {
                    return Column(
                      children: [
                        // Autocomplete por SKU o nombre
                        RawAutocomplete<Map<String, dynamic>>(
                          textEditingController: _productSearchCtrl,
                          focusNode: FocusNode(),
                          displayStringForOption: (opt) =>
                              '${opt['name']} (${opt['sku']})',
                          optionsBuilder: (TextEditingValue tev) async {
                            final q = tev.text.trim();
                            if (q.isEmpty) return const Iterable.empty();
                            final list = await _searchProductsLite(q);
                            return list;
                          },
                          onSelected: (opt) {
                            _productSearchCtrl.text = opt['sku'].toString();
                            _costCtrl.text = ((opt['last_purchase_price'] as num?)?.toDouble() ?? 0.0)
                                .toStringAsFixed(2);
                            _qtyCtrl.text = '1';
                          },
                          fieldViewBuilder: (context, ctrl, focus, onSubmit) {
                            return TextField(
                              controller: ctrl,
                              focusNode: focus,
                              decoration: const InputDecoration(
                                labelText: 'Buscar producto (SKU o nombre)',
                                prefixIcon: Icon(Icons.search),
                              ),
                            );
                          },
                          optionsViewBuilder:
                              (context, onSelected, Iterable<Map<String, dynamic>> opts) {
                            final list = opts.toList();
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                elevation: 4,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                      maxWidth: c.maxWidth, maxHeight: 240),
                                  child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    itemCount: list.length,
                                    itemBuilder: (_, i) {
                                      final it = list[i];
                                      return ListTile(
                                        dense: true,
                                        title: Text(it['name'].toString()),
                                        subtitle: Text('SKU: ${it['sku']}'),
                                        trailing: Text(
                                          'Últ. costo: ${_money.format((it['last_purchase_price'] as num?)?.toDouble() ?? 0)}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        onTap: () => onSelected(it),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            SizedBox(
                              width: 100,
                              child: TextField(
                                controller: _qtyCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Cantidad',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 140,
                              child: TextField(
                                controller: _costCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true, signed: false),
                                decoration: const InputDecoration(
                                  labelText: 'Costo unit.',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              icon: const Icon(Icons.add_shopping_cart),
                              label: const Text('Agregar'),
                              onPressed: _addCurrentSelectionToCart,
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Carrito
        Card(
          child: Padding(
            padding: pad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Carrito', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_cart.isEmpty)
                  const Text('Sin productos'),
                if (_cart.isNotEmpty)
                  ..._cart.map((e) {
                    final line =
                        '${e['qty']} × ${e['name']} (${e['sku']}) @ ${_money.format(e['cost'])}';
                    return ListTile(
                      dense: true,
                      title: Text(line),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          setState(() => _cart.remove(e));
                        },
                      ),
                    );
                  }),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(_money.format(_cartTotal),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('Guardar compra'),
                    onPressed: _savePurchase,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}