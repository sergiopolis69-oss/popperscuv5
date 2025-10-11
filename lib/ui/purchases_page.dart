import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db.dart'; // 👈 usamos DatabaseHelper directo

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _folioCtrl = TextEditingController();
  DateTime _date = DateTime.now();

  // Proveedor
  final _supplierPhoneCtrl = TextEditingController(); // seleccionado (phone = ID)
  final _supplierSearchCtrl = TextEditingController();
  List<Map<String, Object?>> _supplierOptions = [];

  // Producto a agregar
  final _skuCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _costCtrl = TextEditingController();
  final _productSearchCtrl = TextEditingController();
  List<Map<String, Object?>> _productOptions = [];

  final List<_PurchaseItem> _items = [];
  int _pieces = 0;
  double _amount = 0;

  @override
  void initState() {
    super.initState();
    _loadSuppliers('');
    _loadProducts('');
  }

  @override
  void dispose() {
    _folioCtrl.dispose();
    _supplierPhoneCtrl.dispose();
    _supplierSearchCtrl.dispose();
    _skuCtrl.dispose();
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    _productSearchCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _recalc() {
    int p = 0;
    double a = 0;
    for (final it in _items) {
      p += it.qty;
      a += it.qty * it.cost;
    }
    setState(() {
      _pieces = p;
      _amount = a;
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _loadSuppliers(String q) async {
    final db = await DatabaseHelper.instance.db;
    final rows = await db.query(
      'suppliers',
      where: q.isEmpty ? null : '(name LIKE ? OR phone LIKE ?)',
      whereArgs: q.isEmpty ? null : ['%$q%', '%$q%'],
      orderBy: 'name COLLATE NOCASE',
      limit: 25,
    );
    setState(() => _supplierOptions = rows);
  }

  Future<void> _loadProducts(String q) async {
    final db = await DatabaseHelper.instance.db;
    final rows = await db.query(
      'products',
      columns: ['id', 'sku', 'name', 'last_purchase_price'],
      where: q.isEmpty ? null : '(name LIKE ? OR sku LIKE ?)',
      whereArgs: q.isEmpty ? null : ['%$q%', '%$q%'],
      orderBy: 'name COLLATE NOCASE',
      limit: 25,
    );
    setState(() => _productOptions = rows);
  }

  Future<void> _quickAddSupplierDialog() async {
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
            TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono (ID)')),
            const SizedBox(height: 8),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 8),
            TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: 'Dirección')),
          ],
        ),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: ()=>Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );

    if (ok == true) {
      if (phoneCtrl.text.trim().isEmpty) {
        _snack('El teléfono (ID) es obligatorio');
        return;
      }
      try {
        final db = await DatabaseHelper.instance.db;
        await db.insert('suppliers', {
          'phone': phoneCtrl.text.trim(),
          'name': nameCtrl.text.trim(),
          'address': addrCtrl.text.trim(),
        }, conflictAlgorithm: ConflictAlgorithm.abort);
        setState(() {
          _supplierPhoneCtrl.text = phoneCtrl.text.trim();
        });
        await _loadSuppliers('');
        _snack('Proveedor agregado');
      } catch (e) {
        _snack('No se pudo agregar: $e');
      }
    }
  }

  Future<void> _addItemBySku() async {
    final sku = _skuCtrl.text.trim();
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    final cost = double.tryParse(_costCtrl.text.trim().replaceAll(',', '.')) ?? -1;

    if (sku.isEmpty) {
      _snack('Captura SKU');
      return;
    }
    if (qty <= 0) {
      _snack('Cantidad inválida');
      return;
    }
    if (cost < 0) {
      _snack('Costo inválido');
      return;
    }

    final db = await DatabaseHelper.instance.db;
    final prod = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
    if (prod.isEmpty) {
      _snack('SKU no encontrado');
      return;
    }
    final p = prod.first;
    setState(() {
      _items.add(_PurchaseItem(
        productId: p['id'] as int,
        sku: p['sku'] as String,
        name: p['name'] as String,
        qty: qty,
        cost: cost,
      ));
      _skuCtrl.clear();
      _qtyCtrl.text = '1';
      _costCtrl.clear();
    });
    _recalc();
  }

  Future<void> _savePurchase() async {
    if (_folioCtrl.text.trim().isEmpty) {
      _snack('Captura el folio');
      return;
    }
    if (_supplierPhoneCtrl.text.trim().isEmpty) {
      _snack('Selecciona un proveedor');
      return;
    }
    if (_items.isEmpty) {
      _snack('Agrega al menos un producto');
      return;
    }

    final money = NumberFormat.currency(symbol: '\$');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar compra'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(alignment: Alignment.centerLeft, child: Text('Folio: ${_folioCtrl.text}')),
            Align(alignment: Alignment.centerLeft, child: Text('Proveedor: ${_supplierPhoneCtrl.text}')),
            const Divider(),
            ..._items.map((e)=>Align(
              alignment: Alignment.centerLeft,
              child: Text('${e.sku} • ${e.name}  x${e.qty}  @ ${money.format(e.cost)}'),
            )),
            const Divider(),
            Align(alignment: Alignment.centerLeft, child: Text('Piezas: $_pieces')),
            Align(alignment: Alignment.centerLeft, child: Text('Total: ${money.format(_amount)}')),
          ],
        ),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: ()=>Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final db = await DatabaseHelper.instance.db;
      await db.transaction((txn) async {
        final id = await txn.insert('purchases', {
          'folio': _folioCtrl.text.trim(),
          'supplier_phone': _supplierPhoneCtrl.text.trim(),
          'date': DateFormat("yyyy-MM-dd").format(_date),
        });

        for (final it in _items) {
          await txn.insert('purchase_items', {
            'purchase_id': id,
            'product_id': it.productId,
            'quantity': it.qty,
            'unit_cost': it.cost,
          });
          await txn.rawUpdate(
            'UPDATE products SET stock = COALESCE(stock,0)+?, last_purchase_price = ? WHERE id = ?',
            [it.qty, it.cost, it.productId],
          );
        }
      });

      _snack('Compra guardada');
      setState(() {
        _items.clear();
        _pieces = 0;
        _amount = 0;
        _skuCtrl.clear();
        _qtyCtrl.text = '1';
        _costCtrl.clear();
      });
    } catch (e) {
      _snack('Error al guardar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: '\$');

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _folioCtrl,
                    decoration: const InputDecoration(labelText: 'Folio de compra'),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: _pickDate,
                  child: Text(DateFormat('yyyy-MM-dd').format(_date)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Proveedor
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Proveedor'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _supplierSearchCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Buscar proveedor (nombre o teléfono)…',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: _loadSuppliers,
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _supplierPhoneCtrl.text.isEmpty ? null : _supplierPhoneCtrl.text,
                        items: _supplierOptions
                            .map((r) => DropdownMenuItem<String>(
                                  value: r['phone'] as String,
                                  child: Text('${r['name']} — ${r['phone']}'),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _supplierPhoneCtrl.text = v ?? ''),
                        hint: const Text('Selecciona proveedor'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _quickAddSupplierDialog,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Nuevo'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            // Productos
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _productSearchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Buscar producto (nombre o SKU)',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: _loadProducts,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _skuCtrl,
                    decoration: const InputDecoration(labelText: 'SKU'),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Cant.'),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _costCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Costo'),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _addItemBySku,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Sugerencias productos
            SizedBox(
              height: 120,
              child: ListView.builder(
                itemCount: _productOptions.length,
                itemBuilder: (_, i) {
                  final r = _productOptions[i];
                  final sku = r['sku'] as String;
                  final name = r['name'] as String;
                  final lastCost = (r['last_purchase_price'] as num?)?.toDouble() ?? 0;
                  return ListTile(
                    dense: true,
                    title: Text(name),
                    subtitle: Text('SKU: $sku  • último costo: ${money.format(lastCost)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.add_shopping_cart),
                      onPressed: () {
                        _skuCtrl.text = sku;
                        if (_costCtrl.text.trim().isEmpty && lastCost > 0) {
                          _costCtrl.text = lastCost.toStringAsFixed(2);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            // Items agregados
            Expanded(
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final it = _items[i];
                  return ListTile(
                    title: Text('${it.name} (SKU ${it.sku})'),
                    subtitle: Text('x${it.qty}  @ ${money.format(it.cost)}  = ${money.format(it.qty * it.cost)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        setState(() {
                          _items.removeAt(i);
                        });
                        _recalc();
                      },
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            // Totales + Guardar
            Row(
              children: [
                Text('Piezas: $_pieces', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 16),
                Text('Total: ${money.format(_amount)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _savePurchase,
                  icon: const Icon(Icons.save),
                  label: const Text('Guardar compra'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PurchaseItem {
  final int productId;
  final String sku;
  final String name;
  final int qty;
  final double cost;

  _PurchaseItem({
    required this.productId,
    required this.sku,
    required this.name,
    required this.qty,
    required this.cost,
  });
}