import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:intl/intl.dart';
import '../repositories/product_repository.dart';
import '../repositories/customer_repository.dart';
import '../repositories/sale_repository.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _custCtrl = TextEditingController();
  final _custPhone = ValueNotifier<String?>(null);

  final _productCtrl = TextEditingController();
  final _items = <Map<String, dynamic>>[]; // {sku,name,qty,price}

  final _payment = ValueNotifier<String>('Efectivo');
  final _placeCtrl = TextEditingController();
  final _shippingCtrl = TextEditingController(text: '0');
  final _discountCtrl = TextEditingController(text: '0');

  final _prodRepo = ProductRepository();
  final _custRepo = CustomerRepository();
  final _saleRepo = SaleRepository();

  double get _subtotalItems {
    return _items.fold(0.0, (a, it) => a + (it['qty'] as double) * (it['price'] as double));
  }

  double get _shipping => double.tryParse(_shippingCtrl.text) ?? 0;
  double get _discount => double.tryParse(_discountCtrl.text) ?? 0;

  // Total que paga el cliente: items - descuento + envío (envío no afecta utilidad)
  double get _total => _subtotalItems - _discount + _shipping;

  Future<void> _addProductFromSuggestion(Map<String, Object?> m) async {
    final sku = m['sku']!.toString();
    final name = m['name']!.toString();
    final price = (m['default_sale_price'] as num?)?.toDouble() ?? 0;
    setState(() {
      _items.add({'sku': sku, 'name': name, 'qty': 1.0, 'price': price});
      _productCtrl.clear();
    });
  }

  Future<void> _saveSale() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Agrega al menos 1 producto')));
      return;
    }
    final nowIso = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final items = _items.map<Map<String, Object?>>((e) => {
      'sku': e['sku'], 'name': e['name'], 'qty': e['qty'], 'price': e['price'],
    }).toList();

    final saleId = await _saleRepo.create(
      dateIso: nowIso,
      customerPhone: _custPhone.value,
      paymentMethod: _payment.value,
      place: _placeCtrl.text.isEmpty ? null : _placeCtrl.text,
      shipping: _shipping,
      discount: _discount,
      items: items,
    );

    // Confirmación con detalle
    showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Venta guardada'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Folio: $saleId'),
              const SizedBox(height: 8),
              ..._items.map((it)=>ListTile(
                dense: true,
                title: Text('${it['name']} (${it['sku']})'),
                subtitle: Text('x${(it['qty'] as double).toStringAsFixed(2)}  \$${(it['price'] as double).toStringAsFixed(2)}'),
                trailing: Text('\$${((it['qty'] as double)*(it['price'] as double)).toStringAsFixed(2)}'),
              )),
              const Divider(),
              _row('Subtotal', _subtotalItems),
              _row('Descuento', -_discount),
              _row('Envío', _shipping),
              const Divider(),
              _row('Total', _total, bold: true),
            ],
          ),
        ),
        actions: [ TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('OK')) ],
      );
    });

    setState(() {
      _items.clear();
      _productCtrl.clear();
      _shippingCtrl.text = '0';
      _discountCtrl.text = '0';
    });
  }

  Widget _row(String label, double value, {bool bold=false}) {
    final style = TextStyle(fontWeight: bold? FontWeight.bold : FontWeight.normal);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [ Text(label, style: style), Text('\$${value.toStringAsFixed(2)}', style: style) ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Cliente
        Row(
          children: [
            Expanded(
              child: TypeAheadField<Map<String, Object?>>(
                textFieldConfiguration: TextFieldConfiguration(
                  controller: _custCtrl,
                  decoration: const InputDecoration(labelText: 'Cliente (nombre o teléfono)'),
                ),
                suggestionsCallback: (q) async {
                  if (q.trim().isEmpty) return const [];
                  return _custRepo.search(q);
                },
                itemBuilder: (ctx, m) => ListTile(
                  dense: true,
                  title: Text(m['name']?.toString() ?? ''),
                  subtitle: Text(m['phone']?.toString() ?? ''),
                ),
                onSuggestionSelected: (m) {
                  _custCtrl.text = m['name']?.toString() ?? '';
                  _custPhone.value = m['phone']?.toString();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: 'Agregar cliente rápido',
              onPressed: () async {
                // Alta mínima: teléfono obligatorio
                final phoneCtrl = TextEditingController();
                final nameCtrl = TextEditingController();
                await showDialog(context: context, builder: (_) {
                  return AlertDialog(
                    title: const Text('Nuevo cliente'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Teléfono (ID obligatorio)')),
                        const SizedBox(height: 8),
                        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
                      ],
                    ),
                    actions: [
                      TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancelar')),
                      FilledButton(onPressed: ()=>Navigator.pop(context, true), child: const Text('Guardar')),
                    ],
                  );
                }).then((ok) async {
                  if (ok == true) {
                    final phone = phoneCtrl.text.trim();
                    if (phone.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Teléfono obligatorio')));
                      return;
                    }
                    await _custRepo.upsert(phone, nameCtrl.text.trim().isEmpty ? phone : nameCtrl.text.trim(), null);
                    _custPhone.value = phone;
                    _custCtrl.text = nameCtrl.text.trim().isEmpty ? phone : nameCtrl.text.trim();
                  }
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Producto
        TypeAheadField<Map<String, Object?>>(
          textFieldConfiguration: TextFieldConfiguration(
            controller: _productCtrl,
            decoration: const InputDecoration(labelText: 'Producto (SKU o nombre)'),
          ),
          suggestionsCallback: (q) async {
            if (q.trim().isEmpty) return const [];
            return _prodRepo.searchLite(q);
          },
          itemBuilder: (ctx, m) => ListTile(
            dense: true,
            title: Text(m['name']?.toString() ?? ''),
            subtitle: Text('SKU: ${m['sku']}  ·  \$${(m['default_sale_price'] ?? 0).toString()}  ·  Stock: ${m['stock'] ?? 0}'),
          ),
          onSuggestionSelected: _addProductFromSuggestion,
        ),

        const SizedBox(height: 12),

        // Carrito
        ..._items.map((it) => Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${it['name']}  ·  ${it['sku']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('P.U. \$${(it['price'] as double).toStringAsFixed(2)}'),
                  ],
                )),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    initialValue: (it['qty'] as double).toStringAsFixed(2),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Cant.'),
                    onChanged: (v){
                      final q = double.tryParse(v) ?? 1;
                      setState(()=>it['qty'] = q <= 0 ? 1.0 : q);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(()=>_items.remove(it)),
                )
              ],
            ),
          ),
        )),

        const Divider(),
        // Totales
        _row('Subtotal', _subtotalItems),
        Row(
          children: [
            Expanded(child: TextField(
              controller: _discountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Descuento'),
              onChanged: (_)=>setState((){}),
            )),
            const SizedBox(width: 8),
            Expanded(child: TextField(
              controller: _shippingCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Envío'),
              onChanged: (_)=>setState((){}),
            )),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _payment.value,
          items: const [
            DropdownMenuItem(value: 'Efectivo', child: Text('Efectivo')),
            DropdownMenuItem(value: 'Tarjeta', child: Text('Tarjeta')),
            DropdownMenuItem(value: 'Transferencia', child: Text('Transferencia')),
          ],
          onChanged: (v){ if (v!=null) setState(()=>_payment.value = v); },
          decoration: const InputDecoration(labelText: 'Forma de pago'),
        ),
        const SizedBox(height: 8),
        TextField(controller: _placeCtrl, decoration: const InputDecoration(labelText: 'Lugar (opcional)')),
        const SizedBox(height: 8),
        _row('Total a cobrar', _total, bold: true),

        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saveSale,
          icon: const Icon(Icons.save),
          label: const Text('Guardar venta'),
        ),
      ],
    );
  }
}