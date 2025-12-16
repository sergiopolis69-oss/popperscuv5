import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

final _money = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});
  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  // Selección de cliente
  String? _customerPhone;
  String? _customerName;

  // Pago / lugar
  String _paymentMethod = 'efectivo';
  final _placeCtrl = TextEditingController();

  // Envío / descuento
  final _shippingCtrl = TextEditingController(text: '0');
  final _discountCtrl = TextEditingController(text: '0');

  // Live search
  final _customerSearchCtrl = TextEditingController();
  final _productSearchCtrl = TextEditingController();

  List<Map<String, Object?>> _customerResults = [];
  List<Map<String, Object?>> _productResults = [];

  // Carrito: product_id, sku, name, quantity, unit_price, last_purchase_price
  final List<Map<String, dynamic>> _cart = [];

  bool _saving = false;

  @override
  void dispose() {
    _placeCtrl.dispose();
    _shippingCtrl.dispose();
    _discountCtrl.dispose();
    _customerSearchCtrl.dispose();
    _productSearchCtrl.dispose();
    super.dispose();
  }

  // -----------------------
  // BÚSQUEDAS
  // -----------------------
  Future<void> _searchCustomers(String q) async {
    final db = await DatabaseHelper.instance.db;
    final like = '%${q.trim()}%';
    final rows = await db.query(
      'customers',
      where: 'phone LIKE ? OR name LIKE ?',
      whereArgs: [like, like],
      orderBy: 'name COLLATE NOCASE',
      limit: 20,
    );
    setState(() => _customerResults = rows);
  }

  Future<void> _searchProducts(String q) async {
    final db = await DatabaseHelper.instance.db;
    final like = '%${q.trim()}%';
    final rows = await db.query(
      'products',
      where: 'sku LIKE ? OR name LIKE ? OR category LIKE ?',
      whereArgs: [like, like, like],
      orderBy: 'name COLLATE NOCASE',
      limit: 30,
    );
    setState(() => _productResults = rows);
  }

  // -----------------------
  // CARRITO
  // -----------------------
  void _addProductToCart(Map<String, Object?> p) {
    final unit = (p['default_sale_price'] as num?)?.toDouble() ?? 0.0;
    final cost = (p['last_purchase_price'] as num?)?.toDouble() ?? 0.0;

    final existingIdx = _cart.indexWhere((e) => e['product_id'] == p['id']);
    if (existingIdx >= 0) {
      setState(() => _cart[existingIdx]['quantity'] += 1);
      return;
    }

    setState(() {
      _cart.add({
        'product_id': p['id'],
        'sku': p['sku'],
        'name': p['name'],
        'quantity': 1,
        'unit_price': unit,
        'last_purchase_price': cost,
      });
    });
  }

  void _removeFromCart(int index) {
    setState(() => _cart.removeAt(index));
  }

  // -----------------------
  // TOTALES / UTILIDAD EN VIVO
  // -----------------------
  double get _shipping =>
      double.tryParse(_shippingCtrl.text.replaceAll(',', '.')) ?? 0.0;
  double get _discount =>
      double.tryParse(_discountCtrl.text.replaceAll(',', '.')) ?? 0.0;

  double get subtotal => _cart.fold<double>(
        0.0,
        (sum, e) => sum + (e['quantity'] as int) * (e['unit_price'] as double),
      );

  double get total => max(0.0, subtotal + _shipping - _discount);

  // NUEVO: ventas netas de ARTÍCULOS (sin envío) para margen %
  double get _netItemsSales => max(0.0, subtotal - _discount);

  /// Descuento proporcional por renglón, utilidad por renglón y utilidad total
  Map<String, dynamic> _liveProfit() {
    final details = <Map<String, dynamic>>[];
    final sub = subtotal;
    double totalProfit = 0;

    for (final e in _cart) {
      final qty = e['quantity'] as int;
      final unit = e['unit_price'] as double;
      final cost = (e['last_purchase_price'] as num?)?.toDouble() ?? 0.0;
      final lineGross = unit * qty;

      // Distribución proporcional del descuento respecto al subtotal
      final lineDiscount = sub > 0 ? _discount * (lineGross / sub) : 0.0;
      // Envío no afecta utilidad
      final lineProfit = (unit - cost) * qty - lineDiscount;

      details.add({
        'name': e['name'],
        'sku': e['sku'],
        'qty': qty,
        'unit': unit,
        'cost': cost,
        'lineDiscount': lineDiscount,
        'profit': lineProfit,
      });
      totalProfit += lineProfit;
    }

    return {
      'details': details,
      'profit': totalProfit,
    };
  }

  // NUEVO: margen de utilidad en vivo (%), basado en netItemsSales (sin envío)
  double get _liveMarginPct {
    final profit = (_liveProfit()['profit'] as double?) ?? 0.0;
    final base = _netItemsSales;
    if (base <= 0) return 0.0;
    return profit / base; // 0.25 = 25%
  }

  // -----------------------
  // GUARDAR VENTA
  // -----------------------
  Future<void> _saveSale() async {
    if (_saving) return;
    if (_customerPhone == null || _customerPhone!.isEmpty) {
      _snack('Selecciona un cliente');
      return;
    }
    if (_cart.isEmpty) {
      _snack('Carrito vacío');
      return;
    }
    if (subtotal <= 0) {
      _snack('Subtotal no puede ser 0');
      return;
    }
    if (_discount < 0 || _shipping < 0) {
      _snack('Descuento/Envío no válidos');
      return;
    }

    setState(() => _saving = true);
    final db = await DatabaseHelper.instance.db;

    try {
      await db.transaction((txn) async {
        final saleId = await txn.insert('sales', {
          'customer_phone': _customerPhone,
          'payment_method': _paymentMethod,
          'place': _placeCtrl.text.trim().isEmpty ? null : _placeCtrl.text.trim(),
          'shipping_cost': _shipping,
          'discount': _discount,
          'date': DateTime.now().toIso8601String(),
        });

        for (final e in _cart) {
          final productId = e['product_id'] as int;
          final qty = e['quantity'] as int;
          final unit = e['unit_price'] as double;

          await txn.insert('sale_items', {
            'sale_id': saleId,
            'product_id': productId,
            'quantity': qty,
            'unit_price': unit,
          });

          await txn.rawUpdate(
            'UPDATE products SET stock = MAX(stock - ?, 0) WHERE id = ?',
            [qty, productId],
          );
        }
      });

      // Diálogo de confirmación con desglose y utilidad
      final profitData = _liveProfit();
      final profit = profitData['profit'] as double;
      final items = profitData['details'] as List<Map<String, dynamic>>;

      // NUEVO: margen %
      final marginPct = _netItemsSales > 0 ? (profit / _netItemsSales) : 0.0;

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Venta guardada'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_customerName != null) Text('Cliente: $_customerName'),
                Text('Tel: ${_customerPhone ?? ''}'),
                const SizedBox(height: 8),
                Text('Pago: $_paymentMethod'),
                if (_placeCtrl.text.isNotEmpty) Text('Lugar: ${_placeCtrl.text}'),
                const Divider(),
                ...items.map((e) => ListTile(
                      dense: true,
                      title: Text('${e['name']}'),
                      subtitle: Text(
                        'SKU: ${e['sku']}  •  Cant: ${e['qty']}  •  PU: ${_money.format(e['unit'])}  •  Costo: ${_money.format(e['cost'])}',
                      ),
                      trailing: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Desc: ${_money.format(e['lineDiscount'])}'),
                          Text(
                            'Util: ${_money.format(e['profit'])}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    )),
                const Divider(),
                _kv('Subtotal', _money.format(subtotal)),
                _kv('Envío (no afecta utilidad)', _money.format(_shipping)),
                _kv('Descuento total', '- ${_money.format(_discount)}'),
                const SizedBox(height: 4),
                _kv('Total', _money.format(total), bold: true),

                // NUEVO: utilidad y margen %
                _kv('Utilidad (en vivo)', _money.format(profit), bold: true),
                _kv('Margen (utilidad %)', '${(marginPct * 100).toStringAsFixed(1)}%', bold: true),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );

      setState(() {
        _cart.clear();
        _shippingCtrl.text = '0';
        _discountCtrl.text = '0';
      });
      _snack('Venta registrada');
    } catch (e) {
      _snack('Error al guardar: $e');
    } finally {
      setState(() => _saving = false);
    }
  }

  // -----------------------
  // UI
  // -----------------------
  @override
  Widget build(BuildContext context) {
    final profit = _liveProfit()['profit'] as double;

    // NUEVO: margen %
    final marginPct = _liveMarginPct;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          _clientSearchBar(),
          const SizedBox(height: 8),
          _productSearchBar(),
          const SizedBox(height: 12),
          _cartCard(),
          const SizedBox(height: 12),

          // NUEVO: le paso también el margen %
          _totalsCard(profit, marginPct),

          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _saveSale,
            icon: const Icon(Icons.check),
            label: const Text('Guardar venta'),
          ),
        ],
      ),
    );
  }

  Widget _clientSearchBar() {
    return SearchAnchor.bar(
      barHintText: _customerPhone == null
          ? 'Buscar cliente por nombre o teléfono'
          : 'Cliente: $_customerName ($_customerPhone)',
      barLeading: const Icon(Icons.person_search),
      isFullScreen: false,
      barElevation: const MaterialStatePropertyAll(0),
      barShape: MaterialStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      suggestionsBuilder: (context, controller) async {
        if (_customerSearchCtrl != controller) {
          _customerSearchCtrl.text = controller.text;
        }
        await _searchCustomers(controller.text);

        return _customerResults.map((c) {
          final name = (c['name'] ?? '').toString();
          final phone = (c['phone'] ?? '').toString();
          final address = (c['address'] ?? '').toString();
          return ListTile(
            leading: const Icon(Icons.person),
            title: Text(name.isEmpty ? phone : name),
            subtitle: Text(phone + (address.isNotEmpty ? '  •  $address' : '')),
            onTap: () {
              setState(() {
                _customerPhone = phone;
                _customerName = name.isEmpty ? phone : name;
              });
              controller.closeView(phone); // CORREGIDO
            },
          );
        });
      },
      viewHintText: 'Escribe nombre o teléfono…',
      viewLeading: IconButton(
        icon: const Icon(Icons.add),
        tooltip: 'Agregar cliente rápido',
        onPressed: () => _quickAddCustomerDialog(context),
      ),
    );
  }

  Widget _productSearchBar() {
    return SearchAnchor.bar(
      barHintText: 'Buscar producto por SKU, nombre o categoría',
      barLeading: const Icon(Icons.search),
      isFullScreen: false,
      barElevation: const MaterialStatePropertyAll(0),
      barShape: MaterialStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      suggestionsBuilder: (context, controller) async {
        if (_productSearchCtrl != controller) {
          _productSearchCtrl.text = controller.text;
        }
        await _searchProducts(controller.text);

        return _productResults.map((p) {
          final name = (p['name'] ?? '').toString();
          final sku = (p['sku'] ?? '').toString();
          final price = (p['default_sale_price'] as num?)?.toDouble() ?? 0.0;
          final stock = (p['stock'] as num?)?.toInt() ?? 0;

          return ListTile(
            leading: const Icon(Icons.inventory_2),
            title: Text(name),
            subtitle: Text('SKU: $sku • Stock: $stock • ${_money.format(price)}'),
            onTap: () {
              _addProductToCart(p);
              controller.closeView(sku); // CORREGIDO
            },
          );
        });
      },
      viewHintText: 'Escribe SKU o nombre…',
    );
  }

  Widget _cartCard() {
    if (_cart.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.shopping_basket_outlined),
              SizedBox(width: 8),
              Text('Carrito vacío'),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          const ListTile(leading: Icon(Icons.shopping_cart), title: Text('Carrito')),
          const Divider(height: 1),
          ..._cart.asMap().entries.map((entry) {
            final idx = entry.key;
            final e = entry.value;

            return ListTile(
              title: Text('${e['name']}'),
              subtitle: Text('SKU: ${e['sku']}'),
              trailing: SizedBox(
                width: 240,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Menos',
                      onPressed: () {
                        setState(() {
                          e['quantity'] = max(1, (e['quantity'] as int) - 1);
                        });
                      },
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('${e['quantity']}'),
                    IconButton(
                      tooltip: 'Más',
                      onPressed: () {
                        setState(() {
                          e['quantity'] = (e['quantity'] as int) + 1;
                        });
                      },
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 90,
                      child: TextFormField(
                        initialValue: (e['unit_price'] as double).toStringAsFixed(2),
                        textAlign: TextAlign.end,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(isDense: true, labelText: 'PU'),
                        onChanged: (v) {
                          final val = double.tryParse(v.replaceAll(',', '.')) ?? (e['unit_price'] as double);
                          setState(() => e['unit_price'] = max(0.0, val));
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Quitar',
                      onPressed: () => _removeFromCart(idx),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // CAMBIO MÍNIMO: ahora recibe marginPct también
  Widget _totalsCard(double liveProfit, double marginPct) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _paymentMethod,
                    decoration: const InputDecoration(labelText: 'Forma de pago'),
                    items: const [
                      DropdownMenuItem(value: 'efectivo', child: Text('efectivo')),
                      DropdownMenuItem(value: 'tarjeta', child: Text('tarjeta')),
                      DropdownMenuItem(value: 'transferencia', child: Text('transferencia')),
                      DropdownMenuItem(value: 'otros', child: Text('otros')),
                    ],
                    onChanged: (v) => setState(() => _paymentMethod = v ?? 'efectivo'),
                  ),
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
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _shippingCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Costo de envío'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _discountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Descuento'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _kv('Subtotal', _money.format(subtotal)),
            _kv('Envío (no afecta utilidad)', _money.format(_shipping)),
            _kv('Descuento', '- ${_money.format(_discount)}'),
            const Divider(),
            _kv('Total', _money.format(total), bold: true, big: true),
            const SizedBox(height: 6),
            _kv('Utilidad (en vivo)', _money.format(liveProfit), bold: true, big: true),

            // NUEVO: margen %
            _kv('Margen (utilidad %)', '${(marginPct * 100).toStringAsFixed(1)}%', bold: true),
          ],
        ),
      ),
    );
  }

  // -----------------------
  // Cliente rápido
  // -----------------------
  Future<void> _quickAddCustomerDialog(BuildContext context) async {
    final phoneCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final addrCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nuevo cliente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono (ID obligatorio)'),
            ),
            const SizedBox(height: 8),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 8),
            TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: 'Dirección')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );

    if (ok != true) return;

    final phone = phoneCtrl.text.trim();
    if (phone.isEmpty) {
      _snack('El teléfono es obligatorio');
      return;
    }

    final db = await DatabaseHelper.instance.db;
    await db.insert(
      'customers',
      {
        'phone': phone,
        'name': nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
        'address': addrCtrl.text.trim().isEmpty ? null : addrCtrl.text.trim(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    setState(() {
      _customerPhone = phone;
      _customerName = nameCtrl.text.trim().isEmpty ? phone : nameCtrl.text.trim();
    });

    _snack('Cliente guardado');
  }

  // -----------------------
  // Helpers
  // -----------------------
  static Widget _kv(String k, String v, {bool bold = false, bool big = false}) {
    final styleV = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      fontSize: big ? 18 : 16,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          Expanded(child: Text(k)),
          Text(v, style: styleV),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}