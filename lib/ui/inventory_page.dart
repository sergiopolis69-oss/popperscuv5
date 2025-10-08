import 'dart:math';
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
  final _category = TextEditingController();
  final _stock = TextEditingController(text: '0');
  final _salePrice = TextEditingController(text: '0');
  final _initialCost = TextEditingController(text: '0');

  List<Map<String, dynamic>> _rows = [];
  List<String> _categoryOptions = [];
  String? _listFilterCategory; // filtro de la lista

  @override
  void initState() {
    super.initState();
    _loadList();
    _loadCategories();
    _ensureSku();
  }

  void _ensureSku() {
    if (_sku.text.trim().isEmpty) {
      _sku.text = _randomSku8();
    }
  }

  String _randomSku8() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sin confusos
    final rnd = Random.secure();
    return List.generate(8, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> _loadList() async {
    final rows = await _repo.all(limit: 500);
    setState(()=> _rows = rows);
  }

  Future<void> _loadCategories() async {
    final cats = await _repo.categories();
    setState(()=> _categoryOptions = cats);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final sku = _sku.text.trim();
    final cat = _category.text.trim();
    if (sku.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SKU es obligatorio')));
      return;
    }
    if (cat.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Categoría es obligatoria')));
      return;
    }
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nombre es obligatorio')));
      return;
    }
    final stock = int.tryParse(_stock.text) ?? 0;
    final sale = double.tryParse(_salePrice.text.replaceAll(',', '.')) ?? 0.0;
    final cost = double.tryParse(_initialCost.text.replaceAll(',', '.')) ?? 0.0;

    await _repo.upsert(
      sku: sku,
      name: name,
      category: cat,
      stock: stock,
      defaultSalePrice: sale,
      initialCost: cost,
    );
    _name.clear();
    _sku.clear();
    _category.clear();
    _stock.text = '0';
    _salePrice.text = '0';
    _initialCost.text = '0';
    _ensureSku();
    await _loadList();
    await _loadCategories();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto guardado')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _listFilterCategory == null || _listFilterCategory!.isEmpty
        ? _rows
        : _rows.where((r)=> (r['category'] ?? '').toString() == _listFilterCategory).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Filtro por categoría en la lista
        Row(
          children: [
            const Text('Inventario', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            DropdownButton<String>(
              hint: const Text('Filtrar categoría'),
              value: _listFilterCategory?.isEmpty == true ? null : _listFilterCategory,
              items: [
                const DropdownMenuItem(value: '', child: Text('Todas')),
                ..._categoryOptions.map((c)=> DropdownMenuItem(value: c, child: Text(c))),
              ],
              onChanged: (v)=> setState(()=> _listFilterCategory = (v ?? '').isEmpty ? null : v),
            ),
          ],
        ),
        const SizedBox(height: 8),

        ...filtered.map((p)=> ListTile(
          title: Text(p['name'] ?? ''),
          subtitle: Text('SKU: ${p['sku'] ?? '—'} • Cat: ${p['category'] ?? '—'} • Stock: ${p['stock'] ?? 0}'),
          trailing: Text('\$${(p['default_sale_price'] ?? 0).toString()}'),
        )),

        const Divider(),
        const Text('Agregar / editar producto'),
        const SizedBox(height: 6),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre *')),
        const SizedBox(height: 6),
        TextField(controller: _sku, decoration: InputDecoration(
          labelText: 'SKU *',
          suffixIcon: IconButton(icon: const Icon(Icons.refresh), onPressed: (){
            setState(()=> _sku.text = _randomSku8());
          }),
        )),
        const SizedBox(height: 6),

        // Categoría con dropdown + "Nueva"
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: _category.text.isEmpty ? null : _category.text,
                items: _categoryOptions.map((c)=> DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v)=> setState(()=> _category.text = v ?? ''),
                decoration: const InputDecoration(labelText: 'Categoría *'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final ctrl = TextEditingController();
                await showDialog(context: context, builder: (ctx){
                  return AlertDialog(
                    title: const Text('Nueva categoría'),
                    content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Nombre')),
                    actions: [
                      TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Cancelar')),
                      FilledButton(onPressed: (){
                        final v = ctrl.text.trim();
                        if (v.isNotEmpty) {
                          setState(() {
                            if (!_categoryOptions.contains(v)) _categoryOptions.add(v);
                            _category.text = v;
                          });
                        }
                        Navigator.pop(ctx);
                      }, child: const Text('Agregar')),
                    ],
                  );
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Nueva'),
            ),
          ],
        ),

        const SizedBox(height: 6),
        TextField(controller: _stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock')),
        const SizedBox(height: 6),
        TextField(controller: _salePrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio venta')),
        const SizedBox(height: 6),
        TextField(controller: _initialCost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Costo inicial')),
        const SizedBox(height: 10),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}
