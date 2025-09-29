import 'package:flutter/material.dart';
import '../repositories/product_repository.dart';
import '../repositories/client_repository.dart';
import '../repositories/sales_repository.dart';
import '../models/sale.dart';

class _CartItem {
  final int productId;
  final String name;
  final int qty;
  final double unitPrice;
  final double lastCost;
  _CartItem({required this.productId, required this.name, required this.qty, required this.unitPrice, required this.lastCost});
}

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});
  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _clientCtrl = TextEditingController();
  final _placeCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _shippingCtrl = TextEditingController(text: '0');
  final _discountCtrl = TextEditingController(text: '0');

  String _payment = 'Efectivo';
  String? _clientPhone;
  final _items = <_CartItem>[];

  final _prodRepo = ProductRepository();
  final _cliRepo = ClientRepository();
  final _saleRepo = SalesRepository();

  double get subtotal => _items.fold(0.0, (a, b) => a + b.qty * b.unitPrice);
  double get shipping => double.tryParse(_shippingCtrl.text.replaceAll(',', '.')) ?? 0.0;
  double get discount => double.tryParse(_discountCtrl.text.replaceAll(',', '.')) ?? 0.0;
  double get total => (subtotal + shipping - discount).clamp(0, double.infinity);

  double get liveProfit {
    final gross = subtotal;
    if (gross <= 0) return 0;
    double totalRevenue = 0, totalCost = 0;
    for (final it in _items) {
      final itemGross = it.qty * it.unitPrice;
      final itemDisc = discount * (itemGross / gross);
      totalRevenue += (itemGross - itemDisc); // envío excluido
      totalCost += it.qty * it.lastCost;
    }
    return totalRevenue - totalCost;
  }

  Future<void> _addBySku() async {
    final sku = _skuCtrl.text.trim();
    if (sku.isEmpty) return;
    final p = await _prodRepo.findBySku(sku);
    if (p == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SKU no encontrado')));
      return;
    }
    _promptQtyPriceAndAdd(
      productId: p['id'] as int,
      name: p['name'] as String,
      suggestedPrice: (p['default_sale_price'] as num?)?.toDouble() ?? 0,
      lastCost: (p['last_purchase_price'] as num?)?.toDouble() ?? 0,
    );
  }

  void _promptQtyPriceAndAdd({
    required int productId,
    required String name,
    required double suggestedPrice,
    required double lastCost,
  }) async {
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController(text: suggestedPrice > 0 ? suggestedPrice.toStringAsFixed(2) : '');
    await showDialog(context: context, builder: (ctx){
      return AlertDialog(
        title: Text('Agregar "$name"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Piezas')),
            const SizedBox(height: 8),
            TextField(controller: priceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio unitario')),
          ],
        ),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: (){
            final q = int.tryParse(qtyCtrl.text) ?? 0;
            final p = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0;
            if (q>0 && p>0) {
              setState(()=> _items.add(_CartItem(productId: productId, name: name, qty: q, unitPrice: p, lastCost: lastCost)) );
              Navigator.pop(ctx);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cantidad y precio deben ser > 0')));
            }
          }, child: const Text('Agregar')),
        ],
      );
    });
  }

  Future<void> _save() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Agrega productos')));
      return;
    }
    if (subtotal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Importes deben ser > 0')));
      return;
    }
    final sale = Sale(
      customerPhone: _clientPhone,
      paymentMethod: _payment,
      place: _placeCtrl.text.trim(),
      shippingCost: shipping,
      discount: discount,
      date: DateTime.now(),
      items: _items.map((e)=>SaleItem(productId: e.productId, quantity: e.qty, unitPrice: e.unitPrice)).toList(),
    );
    final id = await _saleRepo.createSale(sale);
    if (!mounted) return;
    setState(() {
      _items.clear();
      _skuCtrl.clear();
      _searchCtrl.clear();
      _shippingCtrl.text = '0';
      _discountCtrl.text = '0';
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Venta guardada #$id')));
  }

  @override
  Widget build(BuildContext context) {
    final utilPct = subtotal > 0 ? (liveProfit / subtotal) * 100 : 0;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _ClientLiveSearch(controller: _clientCtrl, onSelected: (phone){ _clientPhone = phone; }),
        const SizedBox(height: 8),
        TextField(controller: _placeCtrl, decoration: const InputDecoration(labelText: 'Lugar de venta', prefixIcon: Icon(Icons.place))),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _payment,
          items: const ['Efectivo','Tarjeta','Transferencia','Otro'].map((e)=>DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v)=> setState(()=>_payment = v ?? 'Efectivo'),
          decoration: const InputDecoration(labelText: 'Forma de pago', prefixIcon: Icon(Icons.payment)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: TextField(controller: _shippingCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Costo de envío'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _discountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Descuento'))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: TextField(controller: _skuCtrl, decoration: const InputDecoration(labelText: 'Agregar por SKU', prefixIcon: Icon(Icons.qr_code)), onSubmitted: (_)=>_addBySku(),)),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: _addBySku, icon: const Icon(Icons.add), label: const Text('Agregar')),
          ],
        ),
        const SizedBox(height: 8),
        _ProductLiveSearch(
          controller: _searchCtrl,
          onPickProduct: (id, name, lastCost, defaultPrice)=>_promptQtyPriceAndAdd(
            productId: id, name: name, lastCost: lastCost ?? 0, suggestedPrice: defaultPrice ?? 0)),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('Productos de la venta'),
                subtitle: Text('Subtotal: \$${subtotal.toStringAsFixed(2)} | Utilidad: \$${liveProfit.toStringAsFixed(2)} (${utilPct.toStringAsFixed(1)}%) | Total: \$${total.toStringAsFixed(2)}'),
              ),
              const Divider(height: 1),
              ..._items.map((it)=>ListTile(
                dense: true,
                title: Text('${it.name}  x${it.qty}'),
                subtitle: Text('P.U. \$${it.unitPrice.toStringAsFixed(2)}  | Costo \$${it.lastCost.toStringAsFixed(2)}  | Importe \$${(it.unitPrice*it.qty).toStringAsFixed(2)}'),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: ()=> setState(()=> _items.remove(it))),
              )),
              if (_items.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Sin productos aún'))
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Guardar venta')),
      ],
    );
  }
}

class _ClientLiveSearch extends StatefulWidget {
  final TextEditingController controller;
  final void Function(String phone) onSelected;
  const _ClientLiveSearch({required this.controller, required this.onSelected});
  @override
  State<_ClientLiveSearch> createState() => _ClientLiveSearchState();
}
class _ClientLiveSearchState extends State<_ClientLiveSearch> {
  final _repo = ClientRepository();
  List<Map<String, dynamic>> _results = [];

  Future<void> _search(String q) async {
    final r = await _repo.search(q);
    setState(()=> _results = r);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
        children: [
          const Expanded(child: Text('Cliente (ID = teléfono)')),
          IconButton(
            tooltip: 'Importar desde contactos',
            icon: const Icon(Icons.contacts),
            onPressed: () async {
              // implementado en ClientsPage (para permisos/UX más completa)
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ve a Clientes → Importar contacto')));
            },
          )
        ],
      ),
      const SizedBox(height: 6),
      TextField(
        controller: widget.controller,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.person_search), hintText: 'Nombre o teléfono…'),
        onChanged: (q){ if(q.length>=2) _search(q); else setState(()=>_results=[]); },
      ),
      ..._results.take(6).map((r)=>ListTile(
        dense: true,
        title: Text(r['name'] as String? ?? ''),
        subtitle: Text(r['phone'] as String? ?? ''),
        onTap: (){
          widget.controller.text = '${r['name']} (${r['phone']})';
          widget.onSelected(r['phone'] as String);
          setState(()=> _results = []);
        },
        trailing: const Icon(Icons.check),
      )),
    ]);
  }
}

class _ProductLiveSearch extends StatefulWidget {
  final TextEditingController controller;
  final void Function(int id, String name, double? lastCost, double? defaultPrice) onPickProduct;
  const _ProductLiveSearch({required this.controller, required this.onPickProduct});
  @override
  State<_ProductLiveSearch> createState() => _ProductLiveSearchState();
}
class _ProductLiveSearchState extends State<_ProductLiveSearch> {
  final _repo = ProductRepository();
  List<Map<String, dynamic>> _results = [];

  Future<void> _search(String q) async {
    final r = await _repo.searchLite(q);
    setState(()=> _results = r);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Agregar producto (live search)'),
      const SizedBox(height: 6),
      TextField(
        controller: widget.controller,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nombre / categoría / SKU'),
        onChanged: (q){ if(q.length>=2) _search(q); else setState(()=>_results=[]); },
      ),
      ..._results.take(6).map((r)=>ListTile(
        dense: true,
        title: Text(r['name'] as String? ?? ''),
        subtitle: Text('Últ. costo: ${((r['last_purchase_price'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}  |  Precio sug.: ${((r['default_sale_price'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'),
        trailing: IconButton(
          icon: const Icon(Icons.add),
          onPressed: ()=> widget.onPickProduct(
            r['id'] as int,
            r['name'] as String? ?? '',
            (r['last_purchase_price'] as num?)?.toDouble(),
            (r['default_sale_price'] as num?)?.toDouble(),
          ),
        ),
      )),
    ]);
  }
}