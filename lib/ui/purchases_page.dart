import 'package:flutter/material.dart';
import '../repositories/supplier_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/purchase_repository.dart';
import '../models/purchase.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});
  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _folioCtrl = TextEditingController();
  final _supplierCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _prodSearchCtrl = TextEditingController();

  int? _supplierId;
  String? _supplierLabel;

  final _supRepo = SupplierRepository();
  final _prodRepo = ProductRepository();
  final _purRepo  = PurchaseRepository();

  final _items = <PurchaseItem>[];

  int get totalPiezas => _items.fold(0, (a, b) => a + b.quantity);
  double get totalMonto => _items.fold(0.0, (a, b) => a + (b.quantity * b.unitCost));

  Future<void> _addProductBySku() async {
    final sku = _skuCtrl.text.trim();
    if (sku.isEmpty) return;
    final p = await _prodRepo.findBySku(sku);
    if (p == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SKU no encontrado')));
      return;
    }
    final last = (p['last_purchase_price'] as num?)?.toDouble() ?? 0.0;
    _promptQtyPriceAndAdd(productId: p['id'] as int, suggestedCost: last);
  }

  void _promptQtyPriceAndAdd({required int productId, required double suggestedCost}) async {
    final qtyCtrl = TextEditingController(text: '1');
    final costCtrl = TextEditingController(text: suggestedCost > 0 ? suggestedCost.toStringAsFixed(2) : '');
    await showDialog(context: context, builder: (ctx){
      return AlertDialog(
        title: const Text('Cantidad y costo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Piezas')),
            const SizedBox(height: 8),
            TextField(controller: costCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Costo unitario')),
          ],
        ),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: (){
            final q = int.tryParse(qtyCtrl.text) ?? 0;
            final c = double.tryParse(costCtrl.text.replaceAll(',', '.')) ?? 0;
            if (q>0 && c>0) {
              setState(() {
                _items.add(PurchaseItem(productId: productId, quantity: q, unitCost: c));
              });
              Navigator.pop(ctx);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cantidad y costo deben ser > 0')));
            }
          }, child: const Text('Agregar')),
        ],
      );
    });
  }

  Future<void> _save() async {
    final folio = _folioCtrl.text.trim();
    if (folio.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Folio requerido')));
      return;
    }
    if (_supplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona proveedor')));
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Agrega al menos un producto')));
      return;
    }
    final id = await _purRepo.createPurchase(Purchase(
      folio: folio,
      supplierId: _supplierId!,
      date: DateTime.now(),
      items: List.from(_items),
    ));
    setState(() {
      _items.clear();
      _folioCtrl.clear();
      _supplierCtrl.clear();
      _supplierId = null;
      _supplierLabel = null;
      _skuCtrl.clear();
      _prodSearchCtrl.clear();
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compra guardada #$id. Inventario actualizado.')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          TextField(controller: _folioCtrl, decoration: const InputDecoration(labelText: 'Folio de compra', prefixIcon: Icon(Icons.tag))),
          const SizedBox(height: 12),
          _SupplierLiveSearch(
            controller: _supplierCtrl,
            onSelected: (id, label) { _supplierId = id; _supplierLabel = label; setState((){}); },
            onQuickAdd: (name, phone, address) async {
              final id = await _supRepo.upsertByPhone(phone: phone, name: name, address: address);
              _supplierId = id;
              _supplierLabel = '$name ($phone)';
              _supplierCtrl.text = _supplierLabel!;
              setState((){});
            },
          ),
          if (_supplierLabel != null) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Proveedor: $_supplierLabel', style: const TextStyle(fontStyle: FontStyle.italic)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _skuCtrl, decoration: const InputDecoration(labelText: 'Agregar por SKU', prefixIcon: Icon(Icons.qr_code)), onSubmitted: (_)=>_addProductBySku())),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: _addProductBySku, icon: const Icon(Icons.add), label: const Text('Agregar'))
          ]),
          const SizedBox(height: 8),
          _ProductLiveSearch(controller: _prodSearchCtrl, onPickProduct: (prodId, lastCost)=> _promptQtyPriceAndAdd(productId: prodId, suggestedCost: lastCost ?? 0)),
          const SizedBox(height: 12),
          Card(child: Column(children: [
            ListTile(title: const Text('Productos agregados'), subtitle: Text('Piezas: $totalPiezas   |   Total: \$${totalMonto.toStringAsFixed(2)}')),
            const Divider(height: 1),
            ..._items.map((it)=> ListTile(
              dense: true,
              title: Text('ID ${it.productId}  x${it.quantity}'),
              subtitle: Text('Costo: \$${it.unitCost.toStringAsFixed(2)}   Importe: \$${(it.quantity*it.unitCost).toStringAsFixed(2)}'),
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: ()=> setState(()=> _items.remove(it))),
            )),
            if (_items.isEmpty) const Padding(padding: EdgeInsets.all(12.0), child: Text('Sin productos aún')),
          ])),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Guardar compra y actualizar inventario')),
        ],
      ),
    );
  }
}

class _SupplierLiveSearch extends StatefulWidget {
  final TextEditingController controller;
  final void Function(int supplierId, String label) onSelected;
  final Future<void> Function(String name, String phone, String address) onQuickAdd;
  const _SupplierLiveSearch({required this.controller, required this.onSelected, required this.onQuickAdd});

  @override
  State<_SupplierLiveSearch> createState() => _SupplierLiveSearchState();
}

class _SupplierLiveSearchState extends State<_SupplierLiveSearch> {
  final _repo = SupplierRepository();
  final FocusNode _focus = FocusNode();
  List<Supplier> _options = [];

  @override
  void dispose() { _focus.dispose(); super.dispose(); }

  Future<void> _search(String q) async {
    final res = await _repo.searchByNameOrPhone(q);
    setState(()=>_options = res);
  }

  Future<void> _quickAddDialog() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    await showDialog(context: context, builder: (ctx) {
      return AlertDialog(
        title: const Text('Nuevo proveedor'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre')),
          const SizedBox(height: 8),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono (ID)')),
          const SizedBox(height: 8),
          TextField(controller: address, decoration: const InputDecoration(labelText: 'Dirección')),
        ]),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () async {
            if (name.text.trim().isEmpty || phone.text.trim().isEmpty) return;
            await widget.onQuickAdd(name.text.trim(), phone.text.trim(), address.text.trim());
            if (mounted) Navigator.pop(ctx);
          }, child: const Text('Guardar')),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
        children: [
          const Expanded(child: Text('Proveedor')),
          TextButton.icon(onPressed: _quickAddDialog, icon: const Icon(Icons.add), label: const Text('Nuevo')),
        ],
      ),
      RawAutocomplete<Supplier>(
        textEditingController: widget.controller,
        focusNode: _focus,
        optionsBuilder: (t) async {
          final q = t.text.trim();
          if (q.isEmpty) return const Iterable.empty();
          await _search(q);
          return _options;
        },
        displayStringForOption: (o)=>'${o.name} (${o.phone})',
        fieldViewBuilder: (ctx, ctrl, focus, onFieldSubmitted) {
          return TextField(
            controller: ctrl,
            focusNode: focus,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.store), hintText: 'Nombre o teléfono…'),
          );
        },
        optionsViewBuilder: (ctx, onSelect, opts) => Material(
          elevation: 4,
          child: ListView(
            shrinkWrap: true,
            children: opts.map((o)=>ListTile(
              title: Text(o.name),
              subtitle: Text(o.phone),
              onTap: (){ onSelect(o); widget.onSelected(o.id!, '${o.name} (${o.phone})'); },
            )).toList(),
          ),
        ),
        onSelected: (_){ },
      ),
    ]);
  }
}

class _ProductLiveSearch extends StatefulWidget {
  final TextEditingController controller;
  final void Function(int productId, double? lastCost) onPickProduct;
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
      const SizedBox(height: 6),
      ..._results.take(6).map((row){
        final id = row['id'] as int;
        final name = row['name'] as String? ?? '';
        final lastCost = (row['last_purchase_price'] as num?)?.toDouble();
        return ListTile(
          dense: true,
          title: Text(name),
          subtitle: Text('Último costo: ${lastCost==null||lastCost==0 ? '—' : '\$'+lastCost.toStringAsFixed(2)}'),
          trailing: IconButton(icon: const Icon(Icons.add), onPressed: (){ widget.onPickProduct(id, lastCost); }),
        );
      }),
    ]);
  }
}