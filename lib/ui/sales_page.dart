import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';
import '../repositories/product_repository.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});
  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _clientCtrl = TextEditingController();
  final _paymentCtrl = TextEditingController(text: 'efectivo');
  final _shippingCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _placeCtrl = TextEditingController();

  final _prodRepo = ProductRepository();

  List<Map<String, dynamic>> _clientOptions = [];
  List<Map<String, dynamic>> _cart = [];

  @override
  void dispose() {
    _clientCtrl.dispose();
    _paymentCtrl.dispose();
    _shippingCtrl.dispose();
    _discountCtrl.dispose();
    _placeCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchClients(String q) async {
    final db = await DatabaseHelper.instance.db;
    final like = '%${q.trim()}%';
    final rows = await db.query(
      'customers',
      where: 'name LIKE ? OR phone LIKE ?',
      whereArgs: [like, like],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: 20,
    );
    setState(()=> _clientOptions = rows);
  }

  Future<List<Map<String, dynamic>>> _searchProducts(String q) async {
    if (q.trim().isEmpty) return [];
    return _prodRepo.searchByNameOrSku(q, limit: 25);
  }

  Future<void> _addQuickClient() async {
    final phoneCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final addrCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo cliente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono / ID *')),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
            TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: 'Dirección')),
          ],
        ),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final phone = phoneCtrl.text.trim();
              if (phone.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El teléfono/ID es obligatorio')));
                return;
              }
              final db = await DatabaseHelper.instance.db;
              await db.insert('customers', {
                'phone': phone,
                'name': nameCtrl.text.trim(),
                'address': addrCtrl.text.trim(),
              }, conflictAlgorithm: ConflictAlgorithm.replace);
              _clientCtrl.text = phone;
              if (context.mounted) Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _promptAddProduct(Map<String, dynamic> p) async {
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController(text: (p['default_sale_price'] as num?)?.toString() ?? '0');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p['name'] ?? ''),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad')),
            const SizedBox(height: 8),
            TextField(controller: priceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio unitario')),
          ],
        ),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final qty = int.tryParse(qtyCtrl.text) ?? 0;
              final price = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0;
              if (qty > 0 && price > 0) {
                setState(() {
                  _cart.add({
                    'product_id': p['id'],
                    'name': p['name'],
                    'quantity': qty,
                    'unit_price': price,
                    'cost': (p['last_purchase_price'] as num?)?.toDouble() ?? 0.0,
                  });
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }

  double get _subtotalItems => _cart.fold(0.0, (a, it) => a + it['quantity'] * it['unit_price']);
  double get _shipping => double.tryParse(_shippingCtrl.text.replaceAll(',', '.')) ?? 0.0;
  double get _discount => double.tryParse(_discountCtrl.text.replaceAll(',', '.')) ?? 0.0;
  double get _totalCobrar => (_subtotalItems - _discount + _shipping).clamp(0.0, double.infinity);

  double get _profit {
    if (_cart.isEmpty) return 0.0;
    final itemsProfit = _cart.fold(0.0, (a, it) {
      final qty = it['quantity'] as int;
      final unit = it['unit_price'] as double;
      final cost = (it['cost'] ?? 0.0) as double;
      return a + (unit - cost) * qty;
    });
    return (itemsProfit - _discount).clamp(0.0, double.infinity);
  }

  Future<void> _saveSale() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Carrito vacío')));
      return;
    }
    if (_totalCobrar <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El total debe ser mayor que 0')));
      return;
    }
    final phone = _clientCtrl.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona o agrega cliente')));
      return;
    }

    final db = await DatabaseHelper.instance.db;
    final batch = db.batch();

    final saleId = await db.insert('sales', {
      'customer_phone': phone,
      'payment_method': _paymentCtrl.text,
      'place': _placeCtrl.text,
      'shipping_cost': _shipping,
      'discount': _discount,
      'date': DateTime.now().toIso8601String(),
    });

    for (final it in _cart) {
      batch.insert('sale_items', {
        'sale_id': saleId,
        'product_id': it['product_id'],
        'quantity': it['quantity'],
        'unit_price': it['unit_price'],
      });
      batch.rawUpdate('UPDATE products SET stock = stock - ? WHERE id = ?', [it['quantity'], it['product_id']]);
    }

    await batch.commit(noResult: true);
    setState(() => _cart.clear());
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venta registrada')));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Cliente (buscar por nombre o teléfono)
        Row(
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Cliente'),
                const SizedBox(height: 4),
                RawAutocomplete<Map<String, dynamic>>(
                  optionsBuilder: (t) async {
                    final q = t.text.trim();
                    if (q.isEmpty) return const Iterable.empty();
                    await _searchClients(q);
                    return _clientOptions;
                  },
                  displayStringForOption: (o)=> '${(o['name'] ?? '').toString()} (${(o['phone'] ?? '').toString()})',
                  fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => TextField(
                    controller: ctrl,
                    decoration: InputDecoration(
                      hintText: 'Nombre o teléfono…',
                      suffixIcon: IconButton(icon: const Icon(Icons.person_add), onPressed: _addQuickClient),
                    ),
                    onChanged: (_) {}, // UI
                  ),
                  optionsViewBuilder: (ctx, onSelect, opts) => Material(
                    elevation: 4,
                    child: ListView(
                      shrinkWrap: true,
                      children: opts.map((o)=> ListTile(
                        title: Text(o['name'] ?? ''),
                        subtitle: Text(o['phone'] ?? ''),
                        onTap: (){
                          onSelect(o);
                          _clientCtrl.text = (o['phone'] ?? '').toString(); // guardar ID
                        },
                      )).toList(),
                    ),
                  ),
                  onSelected: (_) {},
                ),
              ]),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                value: _paymentCtrl.text,
                items: const [
                  DropdownMenuItem(value: 'efectivo', child: Text('Efectivo')),
                  DropdownMenuItem(value: 'tarjeta', child: Text('Tarjeta')),
                  DropdownMenuItem(value: 'transferencia', child: Text('Transferencia')),
                ],
                onChanged: (v)=> setState(()=> _paymentCtrl.text = v ?? 'efectivo'),
                decoration: const InputDecoration(labelText: 'Pago'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Producto (live search con RawAutocomplete)
        const Text('Producto'),
        const SizedBox(height: 4),
        RawAutocomplete<Map<String, dynamic>>(
          optionsBuilder: (t) async {
            final q = t.text.trim();
            if (q.length < 1) return const Iterable.empty();
            final found = await _searchProducts(q);
            return found;
          },
          displayStringForOption: (o)=> o['name']?.toString() ?? '',
          fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => TextField(
            controller: ctrl,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nombre/categoría/SKU…'),
          ),
          optionsViewBuilder: (ctx, onSelect, opts) => Material(
            elevation: 4,
            child: ListView(
              shrinkWrap: true,
              children: opts.map((o)=> ListTile(
                title: Text(o['name'] ?? ''),
                subtitle: Text('SKU: ${o['sku'] ?? '—'}  •  Últ. costo: ${(o['last_purchase_price'] ?? 0).toString()}'),
                trailing: const Icon(Icons.add),
                onTap: (){
                  onSelect(o);
                  _promptAddProduct(o);
                },
              )).toList(),
            ),
          ),
          onSelected: (_){},
        ),

        const SizedBox(height: 12),

        // Carrito
        Card(
          child: Column(
            children: [
              const ListTile(title: Text('Carrito')),
              ..._cart.map((it) => ListTile(
                title: Text(it['name']),
                subtitle: Text('x${it['quantity']}  •  \$${it['unit_price']}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: ()=>setState(()=>_cart.remove(it)),
                ),
              )),
              if (_cart.isEmpty) const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No hay productos agregados'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        TextField(controller: _shippingCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Costo de envío')),
        const SizedBox(height: 8),
        TextField(controller: _discountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Descuento')),
        const SizedBox(height: 8),
        TextField(controller: _placeCtrl, decoration: const InputDecoration(labelText: 'Lugar de venta')),

        const SizedBox(height: 16),

        Card(
          child: Column(
            children: [
              ListTile(title: const Text('Subtotal'), trailing: Text('\$${_subtotalItems.toStringAsFixed(2)}')),
              ListTile(title: const Text('Descuento'), trailing: Text('- \$${_discount.toStringAsFixed(2)}')),
              ListTile(title: const Text('Envío'), trailing: Text('+ \$${_shipping.toStringAsFixed(2)}')),
              const Divider(height: 1),
              ListTile(
                title: const Text('TOTAL A COBRAR'),
                trailing: Text('\$${_totalCobrar.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              ListTile(
                title: const Text('Utilidad estimada'),
                trailing: Text('\$${_profit.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _saveSale, icon: const Icon(Icons.check), label: const Text('Registrar venta')),
      ],
    );
  }
}