import 'package:flutter/material.dart';
import '../repositories/product_repository.dart';
import '../utils/sku.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _repo = ProductRepository();
  final _skuCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _catCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();

  List<Map<String, Object?>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
    _skuCtrl.text = generateSku8();
  }

  Future<void> _load() async {
    final r = await _repo.all();
    setState(()=>_rows = r);
  }

  Future<void> _save() async {
    if (_skuCtrl.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SKU obligatorio'))); return; }
    if (_catCtrl.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Categoría obligatoria'))); return; }
    final price = double.tryParse(_priceCtrl.text) ?? 0;
    final stock = double.tryParse(_stockCtrl.text) ?? 0;
    await _repo.insert({
      'sku': _skuCtrl.text.trim(),
      'name': _nameCtrl.text.trim().isEmpty ? _skuCtrl.text.trim() : _nameCtrl.text.trim(),
      'category': _catCtrl.text.trim(),
      'default_sale_price': price,
      'stock': stock,
    });
    await _load();
    _skuCtrl.text = generateSku8();
    _nameCtrl.clear();
    _catCtrl.clear();
    _priceCtrl.clear();
    _stockCtrl.clear();
  }

  Future<void> _delete(String sku) async {
    await _repo.deleteBySku(sku);
    await _load();
  }

  Future<void> _loadBySku() async {
    final sku = _skuCtrl.text.trim();
    if (sku.isEmpty) return;
    final p = await _repo.findBySku(sku);
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SKU no encontrado, se creará uno nuevo')));
      return;
    }
    _nameCtrl.text = p['name']?.toString() ?? '';
    _catCtrl.text = p['category']?.toString() ?? '';
    _priceCtrl.text = (p['default_sale_price'] ?? '').toString();
    _stockCtrl.text = (p['stock'] ?? '').toString();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          Expanded(child: TextField(controller: _skuCtrl, decoration: const InputDecoration(labelText: 'SKU'), onSubmitted: (_)=>_loadBySku(),)),
          const SizedBox(width: 8),
          FilledButton(onPressed: _loadBySku, child: const Text('Cargar')),
        ]),
        const SizedBox(height: 8),
        TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
        const SizedBox(height: 8),
        TextField(controller: _catCtrl, decoration: const InputDecoration(labelText: 'Categoría')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _priceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio venta (default)'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _stockCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Stock'))),
        ]),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Guardar producto')),
        const SizedBox(height: 16),
        const Text('Inventario'),
        const SizedBox(height: 8),
        ..._rows.map((r)=>Card(child: ListTile(
          title: Text('${r['name']}  ·  ${r['sku']}'),
          subtitle: Text('Cat: ${r['category'] ?? '-'} · \$${(r['default_sale_price'] ?? 0)} · Stock: ${r['stock'] ?? 0}'),
          trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: ()=>_delete(r['sku']!.toString())),
        ))),
      ],
    );
  }
}