import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import '../repositories/product_repository.dart';
import '../repositories/customer_repository.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _prodRepo = ProductRepository();
  final _custRepo = CustomerRepository();

  // buscadores
  final _prodSearchCtrl = TextEditingController();
  final _custSearchCtrl = TextEditingController();

  // venta
  Map<String, Object?>? _selectedCustomer; // {phone,name,...}
  final List<Map<String, Object?>> _cart = []; // {sku,name,qty,price}
  final _shippingCtrl = TextEditingController(text: '0');
  final _discountCtrl = TextEditingController(text: '0');
  final _placeCtrl = TextEditingController();
  String _payment = 'efectivo';

  @override
  void dispose() {
    _prodSearchCtrl.dispose();
    _custSearchCtrl.dispose();
    _shippingCtrl.dispose();
    _discountCtrl.dispose();
    _placeCtrl.dispose();
    super.dispose();
  }

  Future<List<Map<String, Object?>>> _searchProducts(String q) async {
    if (q.trim().isEmpty) return [];
    return await _prodRepo.searchLite(q); // retorna [{sku,name,default_sale_price,...}]
  }

  Future<List<Map<String, Object?>>> _searchCustomers(String q) async {
    if (q.trim().isEmpty) return [];
    return await _custRepo.searchLite(q); // retorna [{phone,name,address}]
  }

  void _addProduct(Map<String, Object?> p) {
    final sku = (p['sku'] ?? '').toString();
    if (sku.isEmpty) return;
    final idx = _cart.indexWhere((e) => e['sku'] == sku);
    if (idx >= 0) {
      _cart[idx]['qty'] = ( (_cart[idx]['qty'] as num?) ?? 0 ) + 1;
    } else {
      _cart.add({
        'sku': sku,
        'name': p['name'] ?? '',
        'qty': 1,
        'price': (p['default_sale_price'] as num?) ?? 0,
        'last_purchase_price': (p['last_purchase_price'] as num?) ?? 0,
      });
    }
    setState(() {});
  }

  num get _subtotal {
    num s = 0;
    for (final it in _cart) {
      final q = (it['qty'] as num?) ?? 0;
      final pr = (it['price'] as num?) ?? 0;
      s += q * pr;
    }
    return s;
  }

  num get _shipping => num.tryParse(_shippingCtrl.text) ?? 0;
  num get _discount => num.tryParse(_discountCtrl.text) ?? 0;

  num get _total => (_subtotal - _discount + _shipping).clamp(0, double.infinity);

  num get _estimatedProfit {
    // utilidad = sum( (precio_venta - ultimo_costo) * qty ) - (descuento repartido)
    // shipping NO afecta utilidad
    num gross = 0;
    final subtotal = _subtotal;
    final disc = _discount;
    for (final it in _cart) {
      final q = (it['qty'] as num?) ?? 0;
      final price = (it['price'] as num?) ?? 0;
      final cost = (it['last_purchase_price'] as num?) ?? 0;
      final line = price * q;
      final lineDisc = subtotal > 0 ? (disc * (line / subtotal)) : 0;
      gross += (line - lineDisc) - (cost * q);
    }
    return gross;
  }

  Future<void> _saveSale() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Carrito vacío')));
      return;
    }
    // regla: no permitir totales en cero
    if (_total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Total no puede ser cero')));
      return;
    }

    // Persistir venta en tu repositorio de ventas
    // Debes tener un SalesRepository con createSale + createSaleItems (ajústalo si tu firma es distinta)
    // Aquí generamos un resumen para confirmar:
    final lines = _cart.map((e) =>
      "• ${e['name']} (SKU: ${e['sku']})  x${e['qty']}  @\$${e['price']}"
    ).join("\n");

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar venta'),
        content: Text(
          'Cliente: ${_selectedCustomer?['name'] ?? '-'}\n'
          'Pago: $_payment\n'
          'Lugar: ${_placeCtrl.text}\n'
          'Envío: \$${_shipping.toStringAsFixed(2)}\n'
          'Descuento: \$${_discount.toStringAsFixed(2)}\n'
          'Subtotal: \$${_subtotal.toStringAsFixed(2)}\n'
          'TOTAL: \$${_total.toStringAsFixed(2)}\n'
          'Utilidad estimada: \$${_estimatedProfit.toStringAsFixed(2)}\n\n'
          'Productos:\n$lines',
        ),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              // TODO: llama a tu repositorio real de ventas
              // await SalesRepository().insertSale(...); await SalesRepository().insertItems(_cart);
              _cart.clear();
              _prodSearchCtrl.clear();
              _discountCtrl.text = '0';
              _shippingCtrl.text = '0';
              setState(() {});
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venta guardada')));
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Cliente
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cliente', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TypeAheadField<Map<String, Object?>>(
                  suggestionsCallback: _searchCustomers,
                  itemBuilder: (context, c) {
                    final phone = (c['phone'] ?? '').toString();
                    final name  = (c['name'] ?? '').toString();
                    return ListTile(
                      title: Text(name.isEmpty ? phone : name),
                      subtitle: Text(phone),
                    );
                  },
                  onSelected: (c) {
                    _custSearchCtrl.text = (c['name'] ?? c['phone'] ?? '').toString();
                    _selectedCustomer = c;
                    setState(() {});
                  },
                  hideOnEmpty: true,
                  emptyBuilder: (context) => const SizedBox.shrink(),
                  builder: (context, controller, focusNode) {
                    controller.text = _custSearchCtrl.text;
                    controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Buscar cliente (nombre o teléfono)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => _custSearchCtrl.text = v,
                    );
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _payment,
                        decoration: const InputDecoration(labelText: 'Forma de pago'),
                        items: const [
                          DropdownMenuItem(value: 'efectivo', child: Text('Efectivo')),
                          DropdownMenuItem(value: 'tarjeta', child: Text('Tarjeta')),
                          DropdownMenuItem(value: 'transferencia', child: Text('Transferencia')),
                        ],
                        onChanged: (v){ if (v!=null) setState(()=>_payment=v); },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _placeCtrl,
                        decoration: const InputDecoration(labelText: 'Lugar de venta', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Productos
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Productos', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TypeAheadField<Map<String, Object?>>(
                  suggestionsCallback: _searchProducts,
                  itemBuilder: (context, p) {
                    final sku = (p['sku'] ?? '').toString();
                    final name = (p['name'] ?? '').toString();
                    final price = (p['default_sale_price'] as num?) ?? 0;
                    return ListTile(
                      title: Text(name),
                      subtitle: Text('SKU: $sku • \$${price.toStringAsFixed(2)}'),
                    );
                  },
                  onSelected: (p) {
                    _prodSearchCtrl.clear();
                    _addProduct(p);
                  },
                  hideOnEmpty: true,
                  emptyBuilder: (context) => const SizedBox.shrink(),
                  builder: (context, controller, focusNode) {
                    controller.text = _prodSearchCtrl.text;
                    controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Buscar por nombre o SKU',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => _prodSearchCtrl.text = v,
                    );
                  },
                ),
                const SizedBox(height: 12),
                // carrito
                ..._cart.map((e){
                  final qty = (e['qty'] as num?) ?? 0;
                  final price = (e['price'] as num?) ?? 0;
                  return ListTile(
                    title: Text('${e['name']}'),
                    subtitle: Text('SKU: ${e['sku']}'),
                    trailing: SizedBox(
                      width: 180,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(onPressed: (){
                            final n = qty - 1;
                            if (n <= 0) {_cart.remove(e);} else { e['qty'] = n; }
                            setState((){});
                          }, icon: const Icon(Icons.remove_circle_outline)),
                          Text(qty.toString()),
                          IconButton(onPressed: (){
                            e['qty'] = qty + 1; setState((){});
                          }, icon: const Icon(Icons.add_circle_outline)),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 72,
                            child: TextFormField(
                              initialValue: price.toString(),
                              decoration: const InputDecoration(isDense: true, labelText: '\$'),
                              keyboardType: TextInputType.number,
                              onChanged: (v){ e['price'] = num.tryParse(v) ?? price; setState((){}); },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ),

        // Totales
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _shippingCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Costo de envío (NO afecta utilidad)', border: OutlineInputBorder()),
                        onChanged: (_) => setState((){}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _discountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Descuento', border: OutlineInputBorder()),
                        onChanged: (_) => setState((){}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: Text('Subtotal: \$${_subtotal.toStringAsFixed(2)}')),
                    Expanded(child: Text('Envío: \$${_shipping.toStringAsFixed(2)}')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: Text('Descuento: -\$${_discount.toStringAsFixed(2)}')),
                    Expanded(
                      child: Text('Total: \$${_total.toStringAsFixed(2)}',
                        style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('Utilidad estimada: \$${_estimatedProfit.toStringAsFixed(2)}'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saveSale,
                        icon: const Icon(Icons.save),
                        label: const Text('Guardar venta'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
