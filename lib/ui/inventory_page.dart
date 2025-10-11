import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database.dart';
import '../repositories/product_repository.dart';
import '../utils/sku.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _skuCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _saleCtrl = TextEditingController(text: '0');
  final _costCtrl = TextEditingController(text: '0');
  final _stockCtrl = TextEditingController(text: '0');

  String? _category;
  bool _newCategory = false;
  final _newCatCtrl = TextEditingController();

  final _repo = ProductRepository();
  List<Map<String,dynamic>> _list = [];
  List<String> _cats = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final db = await DatabaseHelper.instance.db;
    final r = await db.query('products', orderBy: 'name COLLATE NOCASE');
    final cats = await db.rawQuery("SELECT DISTINCT category FROM products WHERE category IS NOT NULL AND category <> '' ORDER BY 1 COLLATE NOCASE");
    setState(() {
      _list = r;
      _cats = cats.map((e) => (e['category'] as String)).toList();
    });
  }

  Future<void> _loadBySku() async {
    final sku = _skuCtrl.text.trim();
    if (sku.isEmpty) return;
    final p = await _repo.getBySku(sku);
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SKU no encontrado, se creará nuevo')));
      _nameCtrl.clear(); _saleCtrl.text='0'; _costCtrl.text='0'; _stockCtrl.text='0'; _category=null;
      return;
    }
    setState(() {
      _nameCtrl.text = p['name'] ?? '';
      _saleCtrl.text = ((p['default_sale_price'] as num?)?.toDouble() ?? 0).toString();
      _costCtrl.text = ((p['last_purchase_price'] as num?)?.toDouble() ?? 0).toString();
      _stockCtrl.text = ((p['stock'] as num?)?.toInt() ?? 0).toString();
      _category = p['category'] as String?;
    });
  }

  Future<void> _save() async {
    final sku = _skuCtrl.text.trim().isEmpty ? generateSku8() : _skuCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final sale = double.tryParse(_saleCtrl.text.replaceAll(',', '.')) ?? 0;
    final cost = double.tryParse(_costCtrl.text.replaceAll(',', '.')) ?? 0;
    final stock = int.tryParse(_stockCtrl.text) ?? 0;
    final category = _newCategory ? _newCatCtrl.text.trim() : _category;

    if (sku.isEmpty || name.isEmpty || sale <= 0 || cost < 0 || stock < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SKU, nombre, precios (>0) y stock (>=0) son obligatorios')));
      return;
    }

    await _repo.upsertBySku({
      'sku': sku,
      'name': name,
      'category': category,
      'default_sale_price': sale,
      'last_purchase_price': cost,
      'stock': stock,
    });

    _skuCtrl.text = sku;
    await _refresh();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto guardado')));
  }

  Future<void> _delete() async {
    final sku = _skuCtrl.text.trim();
    if (sku.isEmpty) return;
    final db = await DatabaseHelper.instance.db;
    final n = await db.delete('products', where: 'sku=?', whereArgs: [sku]);
    if (n > 0) {
      await _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eliminado $sku')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final catWidget = _newCategory
        ? TextField(controller: _newCatCtrl, decoration: const InputDecoration(labelText: 'Nueva categoría'))
        : DropdownButtonFormField<String>(
            value: _category,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Categoría'),
            items: [
              for (final c in _cats) DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v)=> setState(()=> _category = v),
          );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(child: TextField(controller: _skuCtrl, decoration: const InputDecoration(labelText: 'SKU'),)),
          const SizedBox(width: 8),
          FilledButton(onPressed: _loadBySku, child: const Text('Cargar por SKU')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: (){ setState(()=> _skuCtrl.text = generateSku8()); }, child: const Text('Generar SKU')),
        ]),
        const SizedBox(height: 8),
        TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _saleCtrl, decoration: const InputDecoration(labelText: 'Precio venta'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _costCtrl, decoration: const InputDecoration(labelText: 'Último costo compra'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _stockCtrl, decoration: const InputDecoration(labelText: 'Existencias'), keyboardType: TextInputType.number)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: catWidget),
          const SizedBox(width: 8),
          FilterChip(
            label: Text(_newCategory ? 'Escribir nueva' : 'Elegir existente'),
            selected: _newCategory,
            onSelected: (v)=> setState(()=> _newCategory = v),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton(onPressed: _save, child: const Text('Guardar')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _delete, child: const Text('Eliminar')),
        ]),
        const Divider(height: 24),
        Text('Inventario', style: Theme.of(context).textTheme.titleMedium),
        for (final p in _list)
          ListTile(
            title: Text('${p['name']} • ${p['sku']}'),
            subtitle: Text('Cat: ${p['category'] ?? '-'}  • Stock: ${p['stock']}  • Venta: \$${(p['default_sale_price'] as num).toString()}'),
            onTap: (){
              setState(() {
                _skuCtrl.text = p['sku'] ?? '';
                _nameCtrl.text = p['name'] ?? '';
                _saleCtrl.text = (p['default_sale_price'] as num).toString();
                _costCtrl.text = (p['last_purchase_price'] as num).toString();
                _stockCtrl.text = (p['stock'] as num).toString();
                _category = p['category'] as String?;
                _newCategory = false;
              });
            },
          ),
      ],
    );
  }
}