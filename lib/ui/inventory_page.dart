import 'package:flutter/material.dart';
import '../repositories/product_repository.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _repo = ProductRepository();
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _cat = TextEditingController();
  final _initialCost = TextEditingController(text: '0');
  final _defaultSale = TextEditingController(text: '0');
  final _initialStock = TextEditingController(text: '0');

  List<Map<String, dynamic>> _rows = [];

  Future<void> _load() async {
    final r = await _repo.all();
    setState(()=> _rows = r);
  }

  Future<void> _add() async {
    if (_name.text.trim().isEmpty) return;
    final initCost = double.tryParse(_initialCost.text.replaceAll(',', '.')) ?? 0;
    final defSale = double.tryParse(_defaultSale.text.replaceAll(',', '.')) ?? 0;
    final initStock = int.tryParse(_initialStock.text) ?? 0;
    await _repo.insert({
      'name': _name.text.trim(),
      'sku': _sku.text.trim().isEmpty ? null : _sku.text.trim(),
      'category': _cat.text.trim(),
      'stock': initStock,
      'last_purchase_price': initCost,
      'last_purchase_date': DateTime.now().toIso8601String(),
      'default_sale_price': defSale,
      'initial_cost': initCost,
    });
    _name.clear(); _sku.clear(); _cat.clear();
    _initialCost.text = '0'; _defaultSale.text = '0'; _initialStock.text = '0';
    _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Agregar producto'),
        const SizedBox(height: 6),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre')), const SizedBox(height: 6),
        TextField(controller: _sku, decoration: const InputDecoration(labelText: 'SKU (opcional)')), const SizedBox(height: 6),
        TextField(controller: _cat, decoration: const InputDecoration(labelText: 'Categoría (opcional)')), const SizedBox(height: 6),
        Row(children: [
          Expanded(child: TextField(controller: _initialCost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Costo inicial'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _defaultSale, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio venta sugerido'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _initialStock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock inicial'))),
        ]),
        const SizedBox(height: 8),
        FilledButton(onPressed: _add, child: const Text('Guardar')),
        const Divider(),
        const Text('Inventario'),
        const SizedBox(height: 6),
        ..._rows.map((r)=>ListTile(
          title: Text(r['name']?.toString() ?? ''),
          subtitle: Text('SKU: ${r['sku'] ?? '-'}  |  Cat: ${r['category'] ?? ''}\n'
              'Stock: ${r['stock']}   Últ. costo: ${r['last_purchase_price']}   Precio sug.: ${r['default_sale_price']}'),
          trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async {
            await _repo.delete(r['id'] as int);
            _load();
          }),
        )),
      ],
    );
  }
}