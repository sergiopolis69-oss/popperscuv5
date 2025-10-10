import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db.dart';
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

  final _customerCtrl = TextEditingController();
  final _productCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _shippingCtrl = TextEditingController(text: '0');
  final _placeCtrl = TextEditingController();

  String? _selectedCustomerPhone; // id = teléfono
  final List<_CartItem> _cart = [];

  List<Map<String, Object?>> _customerSuggestions = [];
  List<Map<String, Object?>> _productSuggestions = [];

  final _currency = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

  @override
  void dispose() {
    _customerCtrl.dispose();
    _productCtrl.dispose();
    _discountCtrl.dispose();
    _shippingCtrl.dispose();
    _placeCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchCustomers(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _customerSuggestions = []);
      return;
    }
    final r = await _custRepo.searchByPhoneOrName(q, limit: 10);
    setState(() => _customerSuggestions = r);
  }

  Future<void> _searchProducts(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _productSuggestions = []);
      return;
    }
    final r = await _prodRepo.searchLite(q, limit: 12);
    setState(() => _productSuggestions = r);
  }

  Future<void> _addProductBySkuOrNameSelection(Map<String, Object?> row) async {
    final sku = (row['sku'] ?? '').toString();
    final name = (row['name'] ?? '').toString();
    final unitPrice = ((row['default_sale_price'] as num?) ?? 0).toDouble();
    final lastCost = ((row['last_purchase_price'] as num?) ?? 0).toDouble();

    final idx = _cart.indexWhere((e) => e.sku == sku);
    if (idx >= 0) {
      setState(() => _cart[idx].qty += 1);
    } else {
      setState(() => _cart.add(_CartItem(
        sku: sku,
        name: name,
        unitPrice: unitPrice,
        lastCost: lastCost,
      )));
    }
    _productCtrl.clear();
    setState(() => _productSuggestions = []);
  }

  double get _subTotal => _cart.fold(0, (p, e) => p + e.qty * e.unitPrice);
  double get _discount => double.tryParse(_discountCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _shipping => double.tryParse(_shippingCtrl.text.replaceAll(',', '.')) ?? 0;

  // Utilidad en vivo: sum(qty * (precio - costo)) – proporcional de descuento (NO incluye envío)
  double get _liveProfit {
    final subtotal = _subTotal;
    final discount = _discount.clamp(0, subtotal);
    if (subtotal <= 0) return 0;
    double profit = 0;
    for (final it in _cart) {
      final line = it.qty * it.unitPrice;
      final share = line / subtotal;
      final lineDiscount = discount * share;
      final revenueAfterDiscount = line - lineDiscount;
      final cost = it.qty * it.lastCost;
      profit += (revenueAfterDiscount - cost);
    }
    return profit;
  }

  double get _total => (_subTotal - _discount + _shipping).clamp(0, double.infinity);

  Future<void> _saveSale() async {
    if (_cart.isEmpty) {
      _toast('Agrega productos');
      return;
    }
    // No permitir venta en 0
    if (_total <= 0) {
      _toast('La venta no puede ser en 0');
      return;
    }

    final db = await openAppDb();
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final saleId = await txn.insert('sales', {
        'date': now,
        'customer_phone': _selectedCustomerPhone,
        'payment_method': 'efectivo', // podrías elegirlo en UI si quieres
        'place': _placeCtrl.text.trim(),
        'shipping_cost': _shipping,
        'discount': _discount,
      });

      for (final it in _cart) {
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_sku': it.sku,
          'product_name': it.name,
          'quantity': it.qty,
          'unit_price': it.unitPrice,
        });

        // baja de inventario
        await txn.rawUpdate(
          'UPDATE products SET stock = COALESCE(stock,0) - ? WHERE sku = ?',
          [it.qty, it.sku],
        );
      }
    });

    // Confirmación con detalle
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Venta guardada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._cart.map((e) => Text('${e.qty.toStringAsFixed(0)} x ${e.name} (${e.sku}) — ${_currency.format(e.unitPrice)}')),
            const Divider(),
            Text('Subtotal: ${_currency.format(_subTotal)}'),
            Text('Descuento: -${_currency.format(_discount)}'),
            Text('Envío: +${_currency.format(_shipping)}'),
            Text('TOTAL: ${_currency.format(_total)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
            TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('OK'))
        ],
      );
    });

    setState(() {
      _cart.clear();
      _discountCtrl.text = '0';
      _shippingCtrl.text = '0';
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _customerSearch(),
        const SizedBox(height: 8),
        _productSearch(),
        const SizedBox(height: 8),
        _cartList(),
        const SizedBox(height: 8),
        _totalsCard(),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _saveSale,
          icon: const Icon(Icons.save),
          label: const Text('Guardar venta'),
        ),
      ],
    );
  }

  Widget _customerSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Cliente (buscar por nombre o teléfono)'),
        const SizedBox(height: 4),
        TextField(
          controller: _customerCtrl,
          decoration: InputDecoration(
            hintText: 'Escribe nombre o teléfono...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: (_customerCtrl.text.isNotEmpty)
                ? IconButton(icon: const Icon(Icons.clear), onPressed: (){
                    _customerCtrl.clear();
                    _selectedCustomerPhone = null;
                    setState(()=>_customerSuggestions=[]);
                  })
                : null,
          ),
          onChanged: _searchCustomers,
        ),
        if (_customerSuggestions.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 6),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _customerSuggestions.length,
              itemBuilder: (_, i) {
                final c = _customerSuggestions[i];
                final name = (c['name'] ?? '').toString();
                final phone = (c['phone'] ?? '').toString();
                final address = (c['address'] ?? '').toString();
                return ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(name.isNotEmpty ? name : phone),
                  subtitle: Text('$phone  •  $address'),
                  onTap: (){
                    _customerCtrl.text = name.isNotEmpty ? '$name ($phone)' : phone;
                    _selectedCustomerPhone = phone;
                    setState(()=>_customerSuggestions=[]);
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _productSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Producto (buscar por nombre / SKU / categoría)'),
        const SizedBox(height: 4),
        TextField(
          controller: _productCtrl,
          decoration: InputDecoration(
            hintText: 'Escribe para buscar...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: (_productCtrl.text.isNotEmpty)
                ? IconButton(icon: const Icon(Icons.clear), onPressed: (){
                    _productCtrl.clear();
                    setState(()=>_productSuggestions=[]);
                  })
                : null,
          ),
          onChanged: _searchProducts,
          onSubmitted: (v) async {
            // si es un SKU exacto agrega directo
            if (v.trim().isEmpty) return;
            final p = await _prodRepo.findBySku(v.trim());
            if (p != null) {
              await _addProductBySkuOrNameSelection(p);
            } else {
              _toast('No se encontró SKU "$v"');
            }
          },
        ),
        if (_productSuggestions.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 6),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _productSuggestions.length,
              itemBuilder: (_, i) {
                final p = _productSuggestions[i];
                final name = (p['name'] ?? '').toString();
                final sku = (p['sku'] ?? '').toString();
                final price = ((p['default_sale_price'] as num?) ?? 0).toDouble();
                return ListTile(
                  leading: const Icon(Icons.add_shopping_cart),
                  title: Text(name),
                  subtitle: Text('$sku  •  ${_currency.format(price)}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: ()=>_addProductBySkuOrNameSelection(p),
                  ),
                  onTap: ()=>_addProductBySkuOrNameSelection(p),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _cartList() {
    if (_cart.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Carrito vacío'),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          ..._cart.map((e){
            return ListTile(
              title: Text('${e.name}  •  ${e.sku}'),
              subtitle: Text('${_currency.format(e.unitPrice)}  (costo ${_currency.format(e.lastCost)})'),
              leading: IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: (){
                  setState(() {
                    if (e.qty > 1) {
                      e.qty -= 1;
                    } else {
                      _cart.remove(e);
                    }
                  });
                },
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('x${e.qty.toStringAsFixed(0)}'),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: (){
                      setState(()=>e.qty += 1);
                    },
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _totalsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(children: [
              Expanded(child: Text('Subtotal', style: Theme.of(context).textTheme.bodyLarge)),
              Text(_currency.format(_subTotal)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('Descuento')),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _discountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_)=>setState((){}),
                  decoration: const InputDecoration(isDense: true),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('Envío (no afecta utilidad)')),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _shippingCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_)=>setState((){}),
                  decoration: const InputDecoration(isDense: true),
                ),
              ),
            ]),
            const Divider(height: 24),
            Row(children: [
              Expanded(child: Text('Utilidad estimada', style: Theme.of(context).textTheme.titleMedium)),
              Text(_currency.format(_liveProfit), style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('TOTAL', style: Theme.of(context).textTheme.titleLarge)),
              Text(_currency.format(_total), style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _CartItem {
  final String sku;
  final String name;
  final double unitPrice;
  final double lastCost;
  double qty;
  _CartItem({
    required this.sku,
    required this.name,
    required this.unitPrice,
    required this.lastCost,
    this.qty = 1,
  });
}