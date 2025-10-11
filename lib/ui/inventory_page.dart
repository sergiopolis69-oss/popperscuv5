import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';
import '../repositories/product_repository.dart';

String generateSku8() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rnd = Random();
  return List.generate(8, (_) => chars[rnd.nextInt(chars.length)]).join();
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _skuCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _catCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  List<Map<String,dynamic>> _list = [];
  final _repo = ProductRepository();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _skuCtrl.dispose(); _nameCtrl.dispose(); _catCtrl.dispose();
    _priceCtrl.dispose(); _costCtrl.dispose(); _stockCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load([String q = '']) async {
    final rows = await _repo.searchByNameOrSku(q, limit: 200);
    setState(()=> _list = rows);
  }

  Future<void> _newSku() async {
    _skuCtrl.text = generateSku8();
  }

  Future<void> _loadBySku() async {
    final sku = _skuCtrl.text.trim();
    if (sku.isEmpty) return;
    final p = await _repo.getBySku(sku);
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SKU no encontrado')));
      return;
    }
    _nameCtrl.text = p['name'] ?? '';
    _catCtrl.text = p['category'] ?? '';
    _priceCtrl.text = (p['default_sale_price'] ?? 0).toString();
    _costCtrl.text = (p['last_purchase_price'] ?? 0).toString();
    _stockCtrl.text = (p['stock'] ?? 0).toString();
  }

  Future<void> _save() async {
    final sku = _skuCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final cat = _catCtrl.text.trim();
    if (sku.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SKU obligatorio'))); return; }
    if (cat.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Categoría obligatoria'))); return; }
    if (name.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nombre obligatorio'))); return; }
    // Upsert por sku (evita duplicados)
    await _repo.upsertBySku({
      'sku': sku,
      'name': name,
      'category': cat,
      'default_sale_price': double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ?? 0.0,
      'last_purchase_price': double.tryParse(_costCtrl.text.replaceAll(',', '.')) ?? 0.0,
      'stock': int.tryParse(_stockCtrl.text) ?? 0,
    });
    await _load(_searchCtrl.text);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Guardado')));
  }

  Future<void> _deleteBySku(String sku) async {
    final db = await DatabaseHelper.instance.db;
    final p = await _repo.getBySku(sku);
    if (p == null) return;
    await db.delete('products', where: 'id = ?', whereArgs: [p['id']]);
    await _load(_searchCtrl.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Eliminado')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          Expanded(child: TextField(controller: _searchCtrl, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nombre, categoría o SKU'), onChanged: _load)),
          const SizedBox(width: 8),
          IconButton(onPressed: ()=>_load(_searchCtrl.text), icon: const Icon(Icons.refresh)),
        ]),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            const ListTile(title: Text('Editar / Agregar producto')),
            Row(children: [
              Expanded(child: TextField(controller: _skuCtrl, decoration: const InputDecoration(labelText: 'SKU *'))),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: _newSku, icon: const Icon(Icons.autorenew), label: const Text('SKU')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _loadBySku, child: const Text('Cargar por SKU')),
            ]),
            const SizedBox(height: 8),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Nombre *')),
            const SizedBox(height: 8),
            TextField(controller: _catCtrl, decoration: const InputDecoration(labelText: 'Categoría *')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Precio venta'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _costCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Último costo'))),
              const SizedBox(width: 8),
              SizedBox(width: 120, child: TextField(controller: _stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock'))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Guardar')),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: (){
                final sku = _skuCtrl.text.trim();
                if (sku.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Indica el SKU a eliminar')));
                } else {
                  _deleteBySku(sku);
                }
              }, icon: const Icon(Icons.delete, color: Colors.red), label: const Text('Eliminar')),
            ]),
            const SizedBox(height: 8),
          ]),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            const ListTile(title: Text('Inventario')),
            ..._list.map((p)=> ListTile(
              title: Text(p['name'] ?? ''),
              subtitle: Text('SKU: ${p['sku']} • Cat: ${p['category'] ?? ''} • Stock: ${p['stock'] ?? 0}'),
              trailing: Text('\$${(p['default_sale_price'] ?? 0).toString()}'),
              onTap: (){
                _skuCtrl.text = p['sku'];
                _loadBySku();
              },
            )),
            if (_list.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Sin productos')),
          ]),
        ),
      ],
    );
  }
}