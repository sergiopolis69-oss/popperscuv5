import 'dart:async';
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

  // Form controllers
  final _skuCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _catCtrl = TextEditingController();

  // Filtro
  String? _filterCategory;
  final _searchCtrl = TextEditingController();

  // Datos UI
  List<Map<String, Object?>> _rows = [];
  List<String> _categories = ['general', 'accesorios', 'consumibles'];
  Timer? _deb;

  @override
  void initState() {
    super.initState();
    _loadList();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _skuCtrl.dispose();
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _catCtrl.dispose();
    _searchCtrl.dispose();
    _deb?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 250), () => _loadList());
  }

  Future<void> _loadList() async {
    final all = await _repo.all(category: _filterCategory);
    final q = _searchCtrl.text.trim().toLowerCase();
    final rows = (q.isEmpty)
        ? all
        : all.where((r) {
            final s = (r['sku'] ?? '').toString().toLowerCase();
            final n = (r['name'] ?? '').toString().toLowerCase();
            return s.contains(q) || n.contains(q);
          }).toList();
    setState(() => _rows = rows);
  }

  Future<void> _loadBySku() async {
    final sku = _skuCtrl.text.trim();
    if (sku.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe un SKU para cargar')),
      );
      return;
    }
    final r = await _repo.findBySku(sku);
    if (r == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No existe el SKU $sku')),
      );
      return;
    }
    _nameCtrl.text = (r['name'] ?? '').toString();
    _priceCtrl.text = ((r['default_sale_price'] as num?) ?? 0).toString();
    _stockCtrl.text = ((r['stock'] as num?) ?? 0).toString();
    _catCtrl.text = (r['category'] ?? 'general').toString();
    if (!_categories.contains(_catCtrl.text)) {
      _categories.add(_catCtrl.text);
    }
    setState(() {});
  }

  Future<void> _save() async {
    var sku = _skuCtrl.text.trim();
    if (sku.isEmpty) {
      sku = generateSku8();
      _skuCtrl.text = sku;
    }
    final name = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text) ?? 0;
    final stock = double.tryParse(_stockCtrl.text) ?? 0;
    final cat = _catCtrl.text.trim().isEmpty ? 'general' : _catCtrl.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nombre requerido')),
      );
      return;
    }
    if (cat.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Categoría requerida')),
      );
      return;
    }

    await _repo.upsert({
      'sku': sku,
      'name': name,
      'category': cat,
      'default_sale_price': price,
      'stock': stock,
    });

    if (!_categories.contains(cat)) _categories.add(cat);

    await _loadList();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Producto guardado (SKU $sku)')),
    );
  }

  Future<void> _delete() async {
    final sku = _skuCtrl.text.trim();
    if (sku.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe un SKU para borrar')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('¿Eliminar definitivamente el SKU $sku?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;

    await _repo.deleteBySku(sku);
    await _loadList();
    _skuCtrl.clear();
    _nameCtrl.clear();
    _priceCtrl.clear();
    _stockCtrl.clear();
    _catCtrl.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('SKU $sku eliminado')),
    );
  }

  Future<void> _newCategoryDialog() async {
    final tmp = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nueva categoría'),
        content: TextField(controller: tmp, decoration: const InputDecoration(labelText: 'Nombre'),),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Agregar')),
        ],
      ),
    );
    if (ok == true && tmp.text.trim().isNotEmpty) {
      _categories.add(tmp.text.trim());
      _catCtrl.text = tmp.text.trim();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _skuCtrl,
                  decoration: InputDecoration(
                    labelText: 'SKU',
                    prefixIcon: IconButton(
                      icon: const Icon(Icons.autorenew),
                      tooltip: 'Generar SKU',
                      onPressed: () => setState(() => _skuCtrl.text = generateSku8()),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.download),
                      tooltip: 'Cargar por SKU',
                      onPressed: _loadBySku,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Precio venta'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _stockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Stock'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _catCtrl.text.isEmpty ? null : _catCtrl.text,
                  items: _categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    _catCtrl.text = v ?? '';
                    setState(() {});
                  },
                  decoration: const InputDecoration(labelText: 'Categoría'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _newCategoryDialog,
                icon: const Icon(Icons.add),
                label: const Text('Nueva categoría'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Guardar')),
            OutlinedButton.icon(onPressed: _delete, icon: const Icon(Icons.delete), label: const Text('Eliminar')),
          ]),

          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Buscar por SKU o nombre',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _filterCategory,
                hint: const Text('Categoría'),
                items: [null, ..._categories].map((c) {
                  return DropdownMenuItem<String?>(
                    value: c,
                    child: Text(c ?? 'Todas'),
                  );
                }).cast<DropdownMenuItem<String>>().toList(),
                onChanged: (v) {
                  setState(() => _filterCategory = v);
                  _loadList();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          _rows.isEmpty
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text('Sin productos'),
                ))
              : DataTable(
                  columns: const [
                    DataColumn(label: Text('SKU')),
                    DataColumn(label: Text('Nombre')),
                    DataColumn(label: Text('Cat')),
                    DataColumn(label: Text('Precio')),
                    DataColumn(label: Text('Stock')),
                    DataColumn(label: Text('Editar')),
                  ],
                  rows: _rows.map((r) {
                    return DataRow(cells: [
                      DataCell(Text('${r['sku']}')),
                      DataCell(Text('${r['name']}')),
                      DataCell(Text('${r['category']}')),
                      DataCell(Text(((r['default_sale_price'] as num?) ?? 0).toStringAsFixed(2))),
                      DataCell(Text(((r['stock'] as num?) ?? 0).toString())),
                      DataCell(IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () {
                          _skuCtrl.text = (r['sku'] ?? '').toString();
                          _nameCtrl.text = (r['name'] ?? '').toString();
                          _priceCtrl.text = ((r['default_sale_price'] as num?) ?? 0).toString();
                          _stockCtrl.text = ((r['stock'] as num?) ?? 0).toString();
                          _catCtrl.text = (r['category'] ?? 'general').toString();
                          setState(() {});
                        },
                      )),
                    ]);
                  }).toList(),
                ),
        ],
      ),
    );
  }
}