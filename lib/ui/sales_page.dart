
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../models/customer.dart';
import '../repositories/sale_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/customer_repository.dart';
import 'components/search_field.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _saleRepo = SaleRepository();
  final _prodRepo = ProductRepository();
  final _custRepo = CustomerRepository();

  String _productQuery = '';
  String _customerQuery = '';
  String? _selectedCustomerPhone;
  String _paymentMethod = 'Efectivo';
  String _place = 'Tienda';
  double _shipping = 0.0;
  double _discount = 0.0;

  final _items = <SaleItem>[];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: ListView(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Image.asset('assets/images/logo.jpg', width: 48, height: 48, fit: BoxFit.cover),
              FilledButton.icon(
                onPressed: () async {
                  // crear cliente rápido
                  await showDialog(context: context, builder: (ctx){
                    final nameCtrl = TextEditingController();
                    final phoneCtrl = TextEditingController();
                    final addrCtrl = TextEditingController();
                    return AlertDialog(
                      title: const Text('Agregar cliente rápido'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
                          TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Teléfono (ID)')),
                          TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: 'Dirección')),
                        ],
                      ),
                      actions: [
                        TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Cancelar')),
                        FilledButton(onPressed: () async {
                          if (phoneCtrl.text.isNotEmpty){
                            await _custRepo.upsert(
                              Customer(phone: phoneCtrl.text, name: nameCtrl.text, address: addrCtrl.text),
                            );
                            setState(()=>_selectedCustomerPhone = phoneCtrl.text);
                            if (context.mounted) Navigator.pop(ctx);
                          }
                        }, child: const Text('Guardar')),
                      ],
                    );
                  });
                },
                icon: const Icon(Icons.person_add),
                label: const Text('Cliente rápido'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _paymentMethod,
            items: const [
              DropdownMenuItem(value: 'Efectivo', child: Text('Efectivo')),
              DropdownMenuItem(value: 'Tarjeta', child: Text('Tarjeta')),
              DropdownMenuItem(value: 'Transferencia', child: Text('Transferencia')),
            ],
            onChanged: (v){ setState(()=>_paymentMethod=v??'Efectivo'); },
            decoration: const InputDecoration(labelText: 'Forma de pago'),
          ),
          TextFormField(
            initialValue: _place,
            decoration: const InputDecoration(labelText: 'Lugar de venta'),
            onChanged: (v)=>_place=v,
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  decoration: const InputDecoration(labelText: 'Costo de envío'),
                  keyboardType: TextInputType.number,
                  onChanged: (v)=>_shipping = double.tryParse(v) ?? 0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  decoration: const InputDecoration(labelText: 'Descuento total'),
                  keyboardType: TextInputType.number,
                  onChanged: (v)=>_discount = double.tryParse(v) ?? 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SearchField(hint: 'Buscar cliente por nombre/teléfono', onChanged: (v)=> setState(()=>_customerQuery=v)),
          FutureBuilder(
            future: _custRepo.search(_customerQuery),
            builder: (context, snapshot){
              if (!snapshot.hasData) return const SizedBox();
              final data = snapshot.data!;
              return Wrap(
                spacing: 8,
                runSpacing: 4,
                children: data.take(6).map((c)=> ChoiceChip(
                  selected: _selectedCustomerPhone == c.phone,
                  label: Text('${c.name} (${c.phone})'),
                  onSelected: (_){ setState(()=>_selectedCustomerPhone=c.phone); },
                )).toList(),
              );
            },
          ),
          const Divider(),
          SearchField(hint: 'Buscar producto por nombre/categoría', onChanged: (v)=> setState(()=>_productQuery=v)),
          FutureBuilder(
            future: _prodRepo.search(_productQuery),
            builder: (context, snapshot){
              if (!snapshot.hasData) return const SizedBox();
              final data = snapshot.data!;
              return Column(
                children: data.take(8).map((p){
                  return ListTile(
                    title: Text(p.name),
                    subtitle: Text('${p.category}  PV: ${p.salePrice.toStringAsFixed(2)}  ULT.COSTO: ${p.lastPurchasePrice.toStringAsFixed(2)}  Stock: ${p.stock}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.add_circle),
                      onPressed: (){
                        setState(()=>_items.add(SaleItem(saleId: 0, productId: p.id!, quantity: 1, unitPrice: p.salePrice)));
                      },
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const Divider(),
          const Text('Carrito', style: TextStyle(fontWeight: FontWeight.bold)),
          ..._items.asMap().entries.map((e){
            final i = e.key; final it = e.value;
            return ListTile(
              title: Text('Producto ${it.productId}  x${it.quantity}'),
              subtitle: Text('Precio unit: ${it.unitPrice.toStringAsFixed(2)}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.remove), onPressed: (){
                    setState(()=> _items[i] = SaleItem(saleId: 0, productId: it.productId, quantity: (it.quantity>1? it.quantity-1:1), unitPrice: it.unitPrice));
                  }),
                  IconButton(icon: const Icon(Icons.add), onPressed: (){
                    setState(()=> _items[i] = SaleItem(saleId: 0, productId: it.productId, quantity: it.quantity+1, unitPrice: it.unitPrice));
                  }),
                  IconButton(icon: const Icon(Icons.delete), onPressed: (){
                    setState(()=> _items.removeAt(i));
                  }),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () async {
              if (_selectedCustomerPhone == null || _items.isEmpty){
                if (context.mounted){
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Elige cliente y agrega productos')));
                }
                return;
              }
              final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
              final sale = Sale(
                customerPhone: _selectedCustomerPhone!,
                paymentMethod: _paymentMethod,
                datetime: now,
                place: _place,
                shippingCost: _shipping,
                discount: _discount,
              );
              final id = await _saleRepo.createSale(sale, _items);
              if (context.mounted){
                setState(()=>_items.clear());
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Venta registrada (ID $id)')));
              }
            },
            icon: const Icon(Icons.check),
            label: const Text('Registrar venta'),
          ),
        ],
      ),
    );
  }
}
