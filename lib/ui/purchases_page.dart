import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import '../repositories/product_repository.dart';
import '../repositories/supplier_repository.dart'; // catálogo simple para compras

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _prodRepo = ProductRepository();
  final _suppRepo = SupplierRepository();

  final _folioCtrl = TextEditingController();
  final _supplierCtrl = TextEditingController();

  final _prodSearchCtrl = TextEditingController();

  Map<String, Object?>? _selectedSupplier; // {id(phone), name, ...}
  final List<Map<String, Object?>> _items = []; // {sku,name,qty,cost}

  @override
  void dispose() {
    _folioCtrl.dispose();
    _supplierCtrl.dispose();
    _prodSearchCtrl.dispose();
    super.dispose();
  }

  Future<List<Map<String, Object?>>> _searchSuppliers(String q) async {
    if (q.trim().isEmpty) return [];
    return await _suppRepo.searchLite(q); // {id,name,phone,address}
  }

  Future<List<Map<String, Object?>>> _searchProducts(String q) async {
    if (q.trim().isEmpty) return [];
    return await _prodRepo.searchLite(q); // {sku,name,last_purchase_price,...}
  }

  void _addProduct(Map<String, Object?> p) {
    final sku = (p['sku'] ?? '').toString();
    if (sku.isEmpty) return;
    final idx = _items.indexWhere((e) => e['sku'] == sku);
    if (idx >= 0) {
      _items[idx]['qty'] = ( (_items[idx]['qty'] as num?) ?? 0 ) + 1;
    } else {
      _items.add({
        'sku': sku,
        'name': (p['name'] ?? '').toString(),
        'qty': 1,
        'cost': (p['last_purchase_price'] as num?) ?? 0,
      });
    }
    setState((){});
  }

  num get _totalPieces {
    num s = 0;
    for (final it in _items) {
      s += (it['qty'] as num? ?? 0);
    }
    return s;
  }

  num get _totalAmount {
    num s = 0;
    for (final it in _items) {
      s += (it['qty'] as num? ?? 0) * (it['cost'] as num? ?? 0);
    }
    return s;
  }

  Future<void> _savePurchase() async {
    if (_folioCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Folio requerido')));
      return;
    }
    if (_selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Proveedor requerido')));
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sin productos')));
      return;
    }

    final lines = _items.map((e) =>
      "• ${e['name']} (SKU: ${e['sku']}) x${e['qty']} @\$${e['cost']}"
    ).join("\n");

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar compra'),
        content: Text(
          'Folio: ${_folioCtrl.text}\n'
          'Proveedor: ${_selectedSupplier?['name'] ?? _selectedSupplier?['id']}\n'
          'Piezas: $_totalPieces\n'
          'Total: \$${_totalAmount.toStringAsFixed(2)}\n\n'
          'Productos:\n$lines'
        ),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              // TODO: persistir compra + items, y actualizar inventario (stock y last_purchase_price)
              // await PurchaseRepository().insert(...); await InventoryRepository().applyPurchase(_items);
              _items.clear();
              _prodSearchCtrl.clear();
              _folioCtrl.clear();
              setState((){});
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Compra guardada')));
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
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Encabezado de compra', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _folioCtrl,
                        decoration: const InputDecoration(labelText: 'Folio', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TypeAheadField<Map<String, Object?>>(
                        suggestionsCallback: _searchSuppliers,
                        itemBuilder: (context, s) {
                          final name = (s['name'] ?? '').toString();
                          final id   = (s['id'] ?? '').toString();
                          return ListTile(title: Text(name.isEmpty ? id : name), subtitle: Text(id));
                        },
                        onSelected: (s) {
                          _supplierCtrl.text = (s['name'] ?? s['id'] ?? '').toString();
                          _selectedSupplier = s;
                          setState((){});
                        },
                        hideOnEmpty: true,
                        emptyBuilder: (context) => const SizedBox.shrink(),
                        builder: (context, controller, focusNode) {
                          controller.text = _supplierCtrl.text;
                          controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: 'Proveedor (por nombre o teléfono)',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) => _supplierCtrl.text = v,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

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
                    final cost = (p['last_purchase_price'] as num?) ?? 0;
                    return ListTile(
                      title: Text(name),
                      subtitle: Text('SKU: $sku • \$${cost.toStringAsFixed(2)}'),
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
                ..._items.map((e){
                  final qty = (e['qty'] as num?) ?? 0;
                  final cost = (e['cost'] as num?) ?? 0;
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
                            if (n <= 0) {_items.remove(e);} else { e['qty'] = n; }
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
                              initialValue: cost.toString(),
                              decoration: const InputDecoration(isDense: true, labelText: '\$'),
                              keyboardType: TextInputType.number,
                              onChanged: (v){ e['cost'] = num.tryParse(v) ?? cost; setState((){}); },
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

        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Piezas: $_totalPieces')),
                    Expanded(child: Text('Total: \$${_totalAmount.toStringAsFixed(2)}')),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _savePurchase,
                        icon: const Icon(Icons.save),
                        label: const Text('Guardar compra'),
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
