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

  List<Map<String, dynamic>> _rows = [];

  Future<void> _load() async {
    final r = await _repo.all();
    setState(()=> _rows = r);
  }

  Future<void> _add() async {
    if (_name.text.trim().isEmpty) return;
    await _repo.insert({
      'name': _name.text.trim(),
      'sku': _sku.text.trim().isEmpty ? null : _sku.text.trim(),
      'category': _cat.text.trim(),
      'stock': 0,
      'last_purchase_price': 0,
      'last_purchase_date': null,
    });
    _name.clear(); _sku.clear(); _cat.clear();
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
        TextField(controller: _cat, decoration: const InputDecoration(labelText: 'Categoría (opcional)')),
        const SizedBox(height: 6),
        FilledButton(onPressed: _add, child: const Text('Guardar')),
        const Divider(),
        const Text('Inventario'),
        const SizedBox(height: 6),
        ..._rows.map((r)=>ListTile(
          title: Text(r['name']?.toString() ?? ''),
          subtitle: Text('SKU: ${r['sku'] ?? '-'}  |  Cat: ${r['category'] ?? ''}\nStock: ${r['stock']}   Último costo: ${r['last_purchase_price']}'),
          trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async {
            await _repo.delete(r['id'] as int);
            _load();
          }),
        )),
      ],
    );
  }
}
