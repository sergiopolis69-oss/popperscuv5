import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../repositories/product_repository.dart';
import '../data/database.dart';
import '../utils/sku.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _formKey = GlobalKey<FormState>();
  final _repo = ProductRepository();

  final _skuCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _catCtrl  = TextEditingController();
  final _saleCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _stockCtrl= TextEditingController(text: '0');

  String _filterCategory = '';
  List<Map<String, dynamic>> _list = [];
  List<String> _cats = [];

  @override
  void initState() {
    super.initState();
    if (_skuCtrl.text.isEmpty) _skuCtrl.text = generateSku8();
    _refresh();
  }

  @override
  void dispose() {
    _skuCtrl.dispose();
    _nameCtrl.dispose();
    _catCtrl.dispose();
    _saleCtrl.dispose();
    _costCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    _cats = await _repo.categories();
    _list = await _repo.all(category: _filterCategory.isEmpty ? null : _filterCategory);
    setState(() {});
  }

  Map<String, dynamic> _productFromForm() {
    return {
      'sku': _skuCtrl.text.trim(),
      'name': _nameCtrl.text.trim(),
      'category': _catCtrl.text.trim(),
      'default_sale_price': double.tryParse(_saleCtrl.text.replaceAll(',', '.')) ?? 0.0,
      'last_purchase_price': double.tryParse(_costCtrl.text.replaceAll(',', '.')) ?? 0.0,
      'stock': int.tryParse(_stockCtrl.text) ?? 0,
    };
  }

  Future<void> _saveNew() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      final data = _productFromForm();
      await _repo.insert(data);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto guardado')));
      await _refresh();
      _skuCtrl.text = generateSku8();
      _nameCtrl.clear(); _saleCtrl.clear(); _costCtrl.clear(); _stockCtrl.text = '0';
    } on DatabaseException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error BD: ${e.resultCode} ${e.isUniqueConstraintError() ? "(SKU duplicado)" : ""}')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _loadBySku() async {
    final sku = _skuCtrl.text.trim();
    if (sku.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pon un SKU para cargar')));
      return;
    }
    final p = await _repo.findBySku(sku);
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No existe ese SKU')));
      return;
    }
    _nameCtrl.text = (p['name'] ?? '').toString();
    _catCtrl.text  = (p['category'] ?? '').toString();
    _saleCtrl.text = (p['default_sale_price'] ?? 0).toString();
    _costCtrl.text = (p['last_purchase_price'] ?? 0).toString();
    _stockCtrl.text= (p['stock'] ?? 0).toString();
    setState(() {});
  }

  Future<void> _updateBySku() async {
    if (!_formKey.currentState!.validate()) return;
    final sku = _skuCtrl.text.trim();
    if (sku.isEmpty) return;
    try {
      await _repo.updateBySku(sku, _productFromForm());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto actualizado')));
      await _refresh();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _deleteBySku() async {
    final sku = _skuCtrl.text.trim();
    if (sku.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('¿Eliminar SKU $sku? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.deleteBySku(sku);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto eliminado')));
    await _refresh();
    _skuCtrl.text = generateSku8();
    _nameCtrl.clear(); _catCtrl.clear(); _saleCtrl.clear(); _costCtrl.clear(); _stockCtrl.text = '0';
  }

  Future<void> _newCategoryDialog() async {
    final tmp = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nueva categoría'),
        content: TextField(controller: tmp, decoration: const InputDecoration(labelText: 'Nombre de categoría')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Agregar')),
        ],
      ),
    );
    if (ok == true && tmp.text.trim().isNotEmpty) {
      _catCtrl.text = tmp.text.trim();
      if (!_cats.contains(_catCtrl.text)) _cats.add(_catCtrl.text);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final catsForDropdown = [''] + _cats;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Form(
          key: _formKey,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _skuCtrl,
                      decoration: InputDecoration(
                        labelText: 'SKU (8)',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.autorenew),
                          onPressed: () => setState(() => _skuCtrl.text = generateSku8()),
                          tooltip: 'Generar SKU',
                        ),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'SKU obligatorio' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(onPressed: _loadBySku, child: const Text('Cargar por SKU')),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Nombre obligatorio' : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      value: catsForDropdown.contains(_catCtrl.text) ? _catCtrl.text : '',
                      items: catsForDropdown.map((e) => DropdownMenuItem(value: e, child: Text(e.isEmpty ? '— sin categoría —' : e))).toList(),
                      onChanged: (v) => setState(() => _catCtrl.text = (v ?? '')),
                      decoration: const InputDecoration(labelText: 'Categoría'),
                      validator: (_) => (_catCtrl.text.trim().isEmpty) ? 'Categoría obligatoria' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _saleCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Precio Venta'),
                      validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) == null) ? 'Num' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _costCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Último Costo'),
                      validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) == null) ? 'Num' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _stockCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Stock'),
                      validator: (v) => (int.tryParse(v ?? '') == null) ? 'Int' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton(onPressed: _saveNew, child: const Text('Guardar nuevo')),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: _updateBySku, child: const Text('Actualizar por SKU')),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: _newCategoryDialog, child: const Text('Nueva categoría')),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _deleteBySku,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Eliminar por SKU'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 24),
        Row(
          children: [
            const Text('Filtrar por categoría:'),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: _filterCategory.isEmpty ? '' : _filterCategory,
              items: ([''] + _cats).map((e) => DropdownMenuItem(value: e, child: Text(e.isEmpty ? 'Todas' : e))).toList(),
              onChanged: (v) async {
                _filterCategory = v ?? '';
                await _refresh();
              },
            ),
            const Spacer(),
            IconButton(onPressed: _refresh, tooltip: 'Recargar', icon: const Icon(Icons.refresh)),
          ],
        ),
        const SizedBox(height: 8),
        ..._list.map((p) => Card(
          child: ListTile(
            title: Text('${p['name']}'),
            subtitle: Text('SKU ${p['sku']}  •  Cat: ${p['category'] ?? "-"}\nP. Venta: ${p['default_sale_price'] ?? 0}  •  Últ. Costo: ${p['last_purchase_price'] ?? 0}  •  Stock: ${p['stock'] ?? 0}'),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                _skuCtrl.text  = (p['sku'] ?? '').toString();
                _nameCtrl.text = (p['name'] ?? '').toString();
                _catCtrl.text  = (p['category'] ?? '').toString();
                _saleCtrl.text = (p['default_sale_price'] ?? 0).toString();
                _costCtrl.text = (p['last_purchase_price'] ?? 0).toString();
                _stockCtrl.text= (p['stock'] ?? 0).toString();
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cargado en el formulario para editar')));
              },
            ),
          ),
        )),
        const SizedBox(height: 24),
      ],
    );
  }
}