import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';
import '../utils/sku.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  List<Map<String, dynamic>> _rows = [];
  List<String> _categories = [];
  String? _filterCategory;

  // Form (alta/edición)
  final _skuCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String? _category;
  final _stockCtrl = TextEditingController(text: '0');
  final _priceCtrl = TextEditingController(text: '0');
  final _costCtrl = TextEditingController(text: '0');

  int? _editingId; // si es edición, id del producto

  @override
  void initState() {
    super.initState();
    _reload();
    if (_skuCtrl.text.isEmpty) _skuCtrl.text = generateSku8();
  }

  Future<void> _reload() async {
    final db = await DatabaseHelper.instance.db;
    final rows = await db.query(
      'products',
      where: _filterCategory == null ? null : 'category = ?',
      whereArgs: _filterCategory == null ? null : [_filterCategory],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    final catsRaw = await db.rawQuery('SELECT DISTINCT IFNULL(category,"") AS c FROM products ORDER BY c COLLATE NOCASE;');
    final cats = catsRaw.map((e) => (e['c'] as String?)?.trim() ?? '')
      .where((c) => c.isNotEmpty).toList();
    setState(() {
      _rows = rows;
      _categories = cats;
      // si no hay categoría seleccionada y existe al menos una, deja null (=todas)
    });
  }

  Future<void> _newCategoryDialog() async {
    final ctrl = TextEditingController();
    await showDialog(context: context, builder: (ctx) {
      return AlertDialog(
        title: const Text('Nueva categoría'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Nombre de categoría')),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: (){
            final v = ctrl.text.trim();
            if (v.isNotEmpty && !_categories.contains(v)) {
              setState(()=>_categories = [..._categories, v]);
              _category ??= v;
            }
            Navigator.pop(ctx);
          }, child: const Text('Agregar')),
        ],
      );
    });
  }

  Future<void> _save() async {
    final sku = _skuCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final cat = (_category ?? '').trim();
    if (sku.isEmpty || name.isEmpty || cat.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SKU, Nombre y Categoría son obligatorios')));
      return;
    }
    final db = await DatabaseHelper.instance.db;
    final stock = int.tryParse(_stockCtrl.text) ?? 0;
    final price = double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ?? 0.0;
    final cost = double.tryParse(_costCtrl.text.replaceAll(',', '.')) ?? 0.0;

    final data = {
      'sku': sku,
      'name': name,
      'category': cat,
      'stock': stock,
      'default_sale_price': price,
      'initial_cost': cost,
      'last_purchase_price': cost == 0 ? null : cost,
      'last_purchase_date': DateTime.now().toIso8601String(),
    };

    if (_editingId == null) {
      await db.insert('products', data);
    } else {
      await db.update('products', data, where: 'id = ?', whereArgs: [_editingId]);
    }

    _clearForm();
    await _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto guardado')));
    }
  }

  Future<void> _deleteEditing() async {
    if (_editingId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx)=> AlertDialog(
        title: const Text('Eliminar producto'),
        content: const Text('¿Seguro que deseas eliminar este producto? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: ()=>Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;

    final db = await DatabaseHelper.instance.db;
    await db.delete('products', where: 'id = ?', whereArgs: [_editingId]);
    _clearForm();
    await _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto eliminado')));
    }
  }

  void _clearForm() {
    _editingId = null;
    _skuCtrl.text = generateSku8();
    _nameCtrl.clear();
    _category = null;
    _stockCtrl.text = '0';
    _priceCtrl.text = '0';
    _costCtrl.text = '0';
  }

  Future<void> _loadBySku() async {
    final sku = _skuCtrl.text.trim();
    if (sku.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escribe un SKU para cargar')));
      return;
    }
    final db = await DatabaseHelper.instance.db;
    final rows = await db.query('products', where: 'sku = ?', whereArgs: [sku], limit: 1);
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se encontró producto con ese SKU')));
      return;
    }
    final p = rows.first;
    setState(() {
      _editingId = p['id'] as int?;
      _nameCtrl.text = (p['name'] ?? '').toString();
      _category = (p['category'] ?? '').toString().isEmpty ? null : (p['category'] as String);
      _stockCtrl.text = (p['stock'] ?? 0).toString();
      _priceCtrl.text = ((p['default_sale_price'] as num?)?.toString() ?? '0');
      _costCtrl.text = ((p['initial_cost'] as num?)?.toString() ?? '0');
      if (_category != null && !_categories.contains(_category!)) {
        _categories.add(_category!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Filtro por categoría
        Row(
          children: [
            const Text('Inventario', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                value: _filterCategory,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todas las categorías')),
                  ..._categories.map((c)=>DropdownMenuItem(value: c, child: Text(c))),
                ],
                onChanged: (v){ setState(()=>_filterCategory=v); _reload(); },
                decoration: const InputDecoration(isDense: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        ..._rows.map((p)=>ListTile(
          title: Text(p['name'] ?? ''),
          subtitle: Text('SKU: ${p['sku'] ?? '—'} • Cat: ${p['category'] ?? '—'} • Stock: ${p['stock'] ?? 0}'),
          trailing: Text('\$${(p['default_sale_price'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
          onTap: (){
            // Cargar al formulario para edición rápida al tocar un item
            setState(() {
              _editingId = p['id'] as int?;
              _skuCtrl.text = (p['sku'] ?? '').toString();
              _nameCtrl.text = (p['name'] ?? '').toString();
              _category = (p['category'] ?? '').toString().isEmpty ? null : (p['category'] as String);
              _stockCtrl.text = (p['stock'] ?? 0).toString();
              _priceCtrl.text = ((p['default_sale_price'] as num?)?.toString() ?? '0');
              _costCtrl.text = ((p['initial_cost'] as num?)?.toString() ?? '0');
              if (_category != null && !_categories.contains(_category!)) {
                _categories.add(_category!);
              }
            });
          },
        )),
        if (_rows.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Sin productos')),

        const Divider(height: 24),

        // Editar por SKU
        const Text('Editar por SKU', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: TextField(controller: _skuCtrl, decoration: const InputDecoration(labelText: 'SKU *'))),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: _loadBySku, icon: const Icon(Icons.search), label: const Text('Cargar')),
          ],
        ),

        const SizedBox(height: 16),
        const Text('Formulario de producto'),
        const SizedBox(height: 6),
        TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Nombre *')),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: _category,
                items: _categories.map((c)=>DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v)=> setState(()=> _category = v),
                decoration: const InputDecoration(labelText: 'Categoría *'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: _newCategoryDialog, icon: const Icon(Icons.add), label: const Text('Nueva')),
          ],
        ),
        const SizedBox(height: 6),
        TextField(controller: _stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock')),
        const SizedBox(height: 6),
        TextField(controller: _costCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Costo inicial')),
        const SizedBox(height: 6),
        TextField(controller: _priceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio venta (default)')),

        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton(onPressed: _save, child: Text(_editingId == null ? 'Guardar' : 'Actualizar')),
            const SizedBox(width: 8),
            if (_editingId != null)
              OutlinedButton.icon(
                onPressed: _deleteEditing,
                icon: const Icon(Icons.delete, color: Colors.red),
                label: const Text('Eliminar'),
              ),
            const Spacer(),
            OutlinedButton(onPressed: _clearForm, child: const Text('Limpiar')),
          ],
        ),
      ],
    );
  }
}