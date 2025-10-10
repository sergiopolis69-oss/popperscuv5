import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../repositories/product_repository.dart';
import '../repositories/sales_repository.dart';
import '../data/db.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});
  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _prodRepo = ProductRepository();
  final _salesRepo = SalesRepository();

  // Cliente live search (por nombre/teléfono)
  final _clientCtrl = TextEditingController();
  List<Map<String, Object?>> _clientSug = [];
  Timer? _clientDebounce;
  String? _customerPhone;

  // Producto live search
  final _prodCtrl = TextEditingController();
  List<Map<String, Object?>> _prodSug = [];
  Timer? _prodDebounce;

  // Precio/cantidad actuales del “renglon”
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();

  // Carrito
  final List<Map<String, Object?>> _items = [];

  // Otros campos
  String _payment = 'efectivo';
  final _placeCtrl = TextEditingController();
  final _shippingCtrl = TextEditingController(text: '0');
  final _discountCtrl = TextEditingController(text: '0');

  @override
  void dispose() {
    _clientCtrl.dispose();
    _prodCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _placeCtrl.dispose();
    _shippingCtrl.dispose();
    _discountCtrl.dispose();
    _clientDebounce?.cancel();
    _prodDebounce?.cancel();
    super.dispose();
  }

  // ---------- CLIENTES ----------
  Future<void> _searchClients(String q) async {
    final db = await openAppDb();
    final qq = '%${q.trim()}%';
    final rows = await db.query(
      'customers',
      where: 'phone LIKE ? OR name LIKE ?',
      whereArgs: [qq, qq],
      orderBy: 'name',
      limit: 20,
    );
    setState(() => _clientSug = rows);
  }

  void _onClientChanged() {
    _clientDebounce?.cancel();
    _clientDebounce = Timer(const Duration(milliseconds: 200), () {
      _searchClients(_clientCtrl.text);
    });
  }

  // ---------- PRODUCTOS ----------
  Future<void> _searchProducts(String q) async {
    final rows = await _prodRepo.searchLite(q, limit: 20);
    setState(() => _prodSug = rows);
  }

  void _onProdChanged() {
    _prodDebounce?.cancel();
    _prodDebounce = Timer(const Duration(milliseconds: 200), () {
      _searchProducts(_prodCtrl.text);
    });
  }

  void _selectProduct(Map<String, Object?> p) {
    _prodCtrl.text = '${p['sku']} — ${p['name']}';
    _priceCtrl.text = ((p['default_sale_price'] as num?) ?? 0).toStringAsFixed(2);
    setState(() {});
  }

  void _selectClient(Map<String, Object?> c) {
    _clientCtrl.text = '${c['name']} (${c['phone']})';
    _customerPhone = (c['phone'] ?? '').toString();
    setState(() {});
  }

  void _addToCart() {
    // Extrae SKU del campo (antes de “ — ”) o usa tal cual si solo es SKU
    final sku = _prodCtrl.text.contains('—')
        ? _prodCtrl.text.split('—').first.trim()
        : _prodCtrl.text.trim();

    if (sku.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un producto')),
      );
      return;
    }
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    final price = double.tryParse(_priceCtrl.text) ?? 0;
    if (qty <= 0 || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cantidad y precio deben ser > 0')),
      );
      return;
    }

    // Si el SKU existe ya en el carrito, acumula
    final idx = _items.indexWhere((e) => e['product_sku'] == sku);
    if (idx >= 0) {
      _items[idx]['quantity'] = (( _items[idx]['quantity'] as num?) ?? 0).toDouble() + qty;
      _items[idx]['unit_price'] = price; // último precio
    } else {
      // nombre: intenta tomar lo escrito “— Nombre”; si no, deja el SKU como nombre provisional
      final name = _prodCtrl.text.contains('—')
          ? _prodCtrl.text.split('—').last.trim()
          : sku;
      _items.add({
        'product_sku': sku,
        'product_name': name,
        'quantity': qty,
        'unit_price': price,
      });
    }

    _prodCtrl.clear();
    _qtyCtrl.text = '1';
    _priceCtrl.clear();
    setState(() {});
  }

  double get _subtotal {
    return _items.fold<double>(0, (s, it) =>
      s + ((it['quantity'] as num?) ?? 0).toDouble() * ((it['unit_price'] as num?) ?? 0).toDouble()
    );
  }

  double get _shipping => double.tryParse(_shippingCtrl.text) ?? 0;
  double get _discount => double.tryParse(_discountCtrl.text) ?? 0;
  double get _total => _subtotal + _shipping - _discount;

  Future<void> _saveSale() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un producto')),
      );
      return;
    }
    // Confirmación con resumen
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar venta'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ..._items.map((it) => ListTile(
                dense: true,
                title: Text('${it['product_name']}'),
                subtitle: Text('SKU: ${it['product_sku']} • Cant: ${it['quantity']} • Precio: ${((it['unit_price'] as num?) ?? 0).toString()}'),
              )),
              const Divider(),
              Align(alignment: Alignment.centerLeft, child: Text('Subtotal: ${_subtotal.toStringAsFixed(2)}')),
              Align(alignment: Alignment.centerLeft, child: Text('Envío: ${_shipping.toStringAsFixed(2)}')),
              Align(alignment: Alignment.centerLeft, child: Text('Descuento: ${_discount.toStringAsFixed(2)}')),
              Align(alignment: Alignment.centerLeft, child: Text('Total: ${_total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;

    final nowIso = DateFormat("yyyy-MM-ddTHH:mm:ss").format(DateTime.now());
    final saleId = await _salesRepo.createSale({
      'date': nowIso,
      'customer_phone': _customerPhone,
      'payment_method': _payment,
      'place': _placeCtrl.text.trim(),
      'shipping_cost': _shipping,
      'discount': _discount,
    }, _items);

    setState(() {
      _items.clear();
      _shippingCtrl.text = '0';
      _discountCtrl.text = '0';
      _clientCtrl.clear();
      _customerPhone = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Venta #$saleId guardada')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _clientCtrl.addListener(_onClientChanged);
    _prodCtrl.addListener(_onProdChanged);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Cliente
          TextField(
            controller: _clientCtrl,
            decoration: const InputDecoration(
              labelText: 'Cliente (buscar por nombre o teléfono)',
              prefixIcon: Icon(Icons.person_search),
            ),
          ),
          if (_clientSug.isNotEmpty)
            Card(
              margin: const EdgeInsets.only(top: 4, bottom: 8),
              child: Column(
                children: _clientSug.map((c) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.person),
                  title: Text('${c['name']}'),
                  subtitle: Text('${c['phone']}'),
                  onTap: () => _selectClient(c),
                )).toList(),
              ),
            ),

          // Producto + qty + precio
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _prodCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Producto (buscar por nombre o SKU)',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Cant.'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Precio'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _addToCart,
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Agregar'),
              ),
            ],
          ),
          if (_prodSug.isNotEmpty)
            Card(
              margin: const EdgeInsets.only(top: 4, bottom: 8),
              child: Column(
                children: _prodSug.map((p) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.inventory_2),
                  title: Text('${p['name']}'),
                  subtitle: Text('SKU: ${p['sku']} • \$${((p['default_sale_price'] as num?) ?? 0).toStringAsFixed(2)}'),
                  onTap: () => _selectProduct(p),
                )).toList(),
              ),
            ),

          const SizedBox(height: 8),
          // Carrito
          Card(
            child: Column(
              children: [
                const ListTile(
                  title: Text('Carrito'),
                ),
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text('Sin productos'),
                  )
                else
                  ..._items.asMap().entries.map((e) {
                    final i = e.key;
                    final it = e.value;
                    final line = ((it['quantity'] as num?) ?? 0).toDouble() *
                        ((it['unit_price'] as num?) ?? 0).toDouble();
                    return ListTile(
                      title: Text('${it['product_name']}'),
                      subtitle: Text('SKU: ${it['product_sku']} • Cant: ${it['quantity']} • \$${((it['unit_price'] as num?) ?? 0)}'),
                      trailing: Text('\$${line.toStringAsFixed(2)}'),
                      onLongPress: () {
                        setState(() => _items.removeAt(i));
                      },
                    );
                  }).toList(),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('Subtotal', style: Theme.of(context).textTheme.bodyLarge)),
                          Text('\$${_subtotal.toStringAsFixed(2)}'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _shippingCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Costo de envío (no afecta utilidad)',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _discountCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Descuento',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: Text('Total', style: Theme.of(context).textTheme.titleMedium)),
                          Text('\$${_total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Pago y lugar
          Row(
            children: [
              DropdownButton<String>(
                value: _payment,
                items: const [
                  DropdownMenuItem(value: 'efectivo', child: Text('efectivo')),
                  DropdownMenuItem(value: 'tarjeta', child: Text('tarjeta')),
                  DropdownMenuItem(value: 'transferencia', child: Text('transferencia')),
                ],
                onChanged: (v) => setState(() => _payment = v ?? 'efectivo'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _placeCtrl,
                  decoration: const InputDecoration(labelText: 'Lugar de venta'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saveSale,
            icon: const Icon(Icons.save),
            label: const Text('Guardar venta'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}