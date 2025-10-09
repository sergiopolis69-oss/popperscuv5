import 'dart:async';
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
  final _clientSearchCtrl = TextEditingController();
  final _productSearchCtrl = TextEditingController();
  final _paymentCtrl = TextEditingController(text: 'efectivo');
  final _shippingCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _placeCtrl = TextEditingController();

  List<Map<String, dynamic>> _clientResults = [];
  List<Map<String, dynamic>> _productResults = [];
  String? _selectedClientPhone;
  final _repo = ProductRepository();
  final List<Map<String, dynamic>> _cart = [];

  Timer? _debounceC;
  Timer? _debounceP;

  @override
  void dispose() {
    _clientSearchCtrl.dispose();
    _productSearchCtrl.dispose();
    _paymentCtrl.dispose();
    _shippingCtrl.dispose();
    _discountCtrl.dispose();
    _placeCtrl.dispose();
    _debounceC?.cancel(); _debounceP?.cancel();
    super.dispose();
  }

  void _onClientChanged(String q) {
    _debounceC?.cancel();
    _debounceC = Timer(const Duration(milliseconds: 250), () async {
      final db = await DatabaseHelper.instance.db;
      final like = '%${q.trim()}%';
      final rows = await db.query(
        'customers',
        where: 'name LIKE ? OR phone LIKE ?',
        whereArgs: [like, like],
        orderBy: 'name COLLATE NOCASE ASC',
        limit: 20,
      );
      setState(() => _clientResults = rows);
    });
  }

  void _onProductChanged(String q) {
    _debounceP?.cancel();
    _debounceP = Timer(const Duration(milliseconds: 250), () async {
      if (q.trim().isEmpty) { setState(()=>_productResults=[]); return; }
      final rows = await _repo.searchByNameOrSku(q, limit: 25);
      setState(() => _productResults = rows);
    });
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
              setState(() {
                _selectedClientPhone = phone;
                _clientSearchCtrl.text = phone;
                _clientResults.clear();
              });
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
    final costSum = _cart.fold(0.0, (a, it) => a + (it['cost'] as double) * (it['quantity'] as int));
    final util = _subtotalItems - _discount - costSum; // envío excluido
    return util.clamp(0.0, double.infinity);
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
    if ((_selectedClientPhone ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona o agrega cliente')));
      return;
    }

    final db = await DatabaseHelper.instance.db;
    final batch = db.batch();

    final saleId = await db.insert('sales', {
      'customer_phone': _selectedClientPhone,
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

    // Cuadro de confirmación con detalle
    final lines = _cart.map((it) => '• ${it['name']}  x${it['quantity']}  @ \$${(it['unit_price'] as num).toString()}').join('\n');
    final totalTxt = _totalCobrar.toStringAsFixed(2);
    await showDialog(context: context, builder: (ctx){
      return AlertDialog(
        title: const Text('Venta registrada'),
        content: Text('$lines\n\nDescuento: \$${_discount.toStringAsFixed(2)}\nEnvío: \$${_shipping.toStringAsFixed(2)}\n\nTOTAL: \$${totalTxt}'),
        actions: [ FilledButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('OK')) ],
      );
    });

    setState(() {
      _cart.clear();
      _productSearchCtrl.clear();
      _productResults.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venta registrada')));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Cliente (buscar por nombre o teléfono)'),
        const SizedBox(height: 4),
        TextField(
          controller: _clientSearchCtrl,
          decoration: InputDecoration(
            hintText: 'Ej. Juan / 5512345678',
            suffixIcon: IconButton(icon: const Icon(Icons.person_add), onPressed: _addQuickClient),
          ),
          onChanged: (q) { _selectedClientPhone = null; _onClientChanged(q); },
        ),
        if (_clientResults.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 6),
            child: Column(
              children: _clientResults.map((c) => ListTile(
                dense: true,
                title: Text(c['name']?.toString().isEmpty == true ? c['phone'] : c['name']),
                subtitle: Text(c['phone'] ?? ''),
                onTap: (){
                  setState(() {
                    _selectedClientPhone = c['phone'] as String?;
                    _clientSearchCtrl.text = _selectedClientPhone!;
                    _clientResults.clear();
                  });
                },
              )).toList(),
            ),
          ),

        const SizedBox(height: 12),

        Row(
          children: [
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
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _placeCtrl, decoration: const InputDecoration(labelText: 'Lugar de venta'))),
          ],
        ),

        const SizedBox(height: 16),

        const Text('Producto (buscar por nombre / categoría / SKU)'),
        const SizedBox(height: 4),
        TextField(
          controller: _productSearchCtrl,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Escribe para buscar…'),
          onChanged: _onProductChanged,
        ),
        if (_productResults.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 6),
            child: Column(
              children: _productResults.map((p) => ListTile(
                dense: true,
                title: Text(p['name'] ?? ''),
                subtitle: Text('SKU: ${p['sku'] ?? '—'}  •  Stock: ${p['stock'] ?? 0}  •  Últ. costo: ${(p['last_purchase_price'] ?? 0).toString()}'),
                trailing: const Icon(Icons.add),
                onTap: () => _promptAddProduct(p),
              )).toList(),
            ),
          ),

        const SizedBox(height: 12),

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

        TextField(controller: _shippingCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Costo de envío'), onChanged: (_)=>setState((){})),
        const SizedBox(height: 8),
        TextField(controller: _discountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Descuento'), onChanged: (_)=>setState((){})),

        const SizedBox(height: 16),

        Card(
          child: Column(
            children: [
              ListTile(title: const Text('Subtotal'), trailing: Text('\$${_subtotalItems.toStringAsFixed(2)}')),
              ListTile(title: const Text('Descuento'), trailing: Text('- \$${_discount.toStringAsFixed(2)}')),
              ListTile(title: const Text('Envío'), trailing: Text('+ \$${_shipping.toStringAsFixed(2)}')),
              const Divider(height: 1),
              ListTile(title: const Text('TOTAL A COBRAR'), trailing: Text('\$${_totalCobrar.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              ListTile(title: const Text('Utilidad estimada'), trailing: Text('\$${_profit.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _saveSale, icon: const Icon(Icons.check), label: const Text('Registrar venta')),
      ],
    );
  }
}
