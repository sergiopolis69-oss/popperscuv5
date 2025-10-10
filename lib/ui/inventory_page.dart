import 'dart:math';
import 'package:flutter/material.dart';
import '../repositories/product_repository.dart';

String generateSku8() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rand = Random.secure();
  return List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _repo = ProductRepository();
  late Future<List<Map<String, Object?>>> _future;
  String _categoryFilter = 'Todas';

  // form controls
  final _skuCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _catCtrl = TextEditingController();
  final _saleCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _repo.all();
    setState((){});
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

  Future<void> _startNew() async {
    _skuCtrl.text = generateSku8();
    _nameCtrl.clear();
    _catCtrl.text = 'general';
    _saleCtrl.text = '0';
    _costCtrl.text = '0';
    _stockCtrl.text = '0';
    await _showEditDialog(isEditing: false);
  }

  Future<void> _editBySkuPrompt() async {
    final tmp = TextEditingController();
    await showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: const Text('Editar por SKU'),
        content: TextField(controller: tmp, decoration: const InputDecoration(labelText: 'SKU'),),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () async {
            final sku = tmp.text.trim();
            if (sku.isEmpty) return;
            final p = await _repo.findBySku(sku);
            if (p == null) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No existe ese SKU')));
              }
              return;
            }
            _skuCtrl.text = (p['sku'] ?? '').toString();
            _nameCtrl.text = (p['name'] ?? '').toString();
            _catCtrl.text  = (p['category'] ?? 'general').toString();
            _saleCtrl.text = ((p['default_sale_price'] as num?) ?? 0).toString();
            _costCtrl.text = ((p['last_purchase_price'] as num?) ?? 0).toString();
            _stockCtrl.text = ((p['stock'] as num?) ?? 0).toString();
            if (context.mounted) {
              Navigator.pop(context);
              await _showEditDialog(isEditing: true);
            }
          }, child: const Text('Cargar')),
        ],
      );
    });
  }

  Future<void> _showEditDialog({required bool isEditing}) async {
    await showDialog(context: context, builder: (_) {
      return AlertDialog(
        title: Text(isEditing ? 'Editar producto' : 'Nuevo producto'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _skuCtrl, decoration: const InputDecoration(labelText: 'SKU (obligatorio)')),
              const SizedBox(height: 8),
              TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: _catCtrl, decoration: const InputDecoration(labelText: 'Categoría (obligatorio)'))),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: (){
                  // agrega categoría rápida (solo texto)
                  if (_catCtrl.text.trim().isEmpty) _catCtrl.text = 'general';
                }, child: const Text('Nueva categoría')),
              ]),
              const SizedBox(height: 8),
              TextField(controller: _saleCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio venta (default)')),
              const SizedBox(height: 8),
              TextField(controller: _costCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Último costo')),
              const SizedBox(height: 8),
              TextField(controller: _stockCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Existencia')),
            ],
          ),
        ),
        actions: [
          if (isEditing)
            TextButton(
              onPressed: () async {
                final sku = _skuCtrl.text.trim();
                if (sku.isEmpty) return;
                await _repo.deleteBySku(sku);
                if (context.mounted) {
                  Navigator.pop(context);
                  _reload();
                }
              },
              child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () async {
            final sku = _skuCtrl.text.trim();
            final cat = _catCtrl.text.trim();
            if (sku.isEmpty || cat.isEmpty) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SKU y categoría son obligatorios')));
              }
              return;
            }
            final name = _nameCtrl.text.trim();
            final sale = double.tryParse(_saleCtrl.text.replaceAll(',', '.')) ?? 0;
            final cost = double.tryParse(_costCtrl.text.replaceAll(',', '.')) ?? 0;
            final stock = double.tryParse(_stockCtrl.text.replaceAll(',', '.')) ?? 0;

            await _repo.upsert({
              'sku': sku,
              'name': name,
              'category': cat,
              'default_sale_price': sale,
              'last_purchase_price': cost,
              'stock': stock,
              'last_purchase_date': DateTime.now().toIso8601String(),
            });

            if (context.mounted) {
              Navigator.pop(context);
              _reload();
            }
          }, child: const Text('Guardar')),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filtros / Acciones
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _categoryFilter,
                  items: const [
                    DropdownMenuItem(value: 'Todas', child: Text('Todas las categorías')),
                    DropdownMenuItem(value: 'general', child: Text('general')),
                  ],
                  onChanged: (v){
                    setState(()=>_categoryFilter = v ?? 'Todas');
                  },
                  decoration: const InputDecoration(labelText: 'Filtrar categoría'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: _startNew, icon: const Icon(Icons.add), label: const Text('Nuevo')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _editBySkuPrompt, child: const Text('Editar por SKU')),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, Object?>>>(
            future: _future,
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              final data = (snap.data ?? []).where((p){
                if (_categoryFilter == 'Todas') return true;
                return (p['category'] ?? '').toString() == _categoryFilter;
              }).toList();

              if (data.isEmpty) {
                return const Center(child: Text('No hay productos'));
              }
              return ListView.separated(
                itemCount: data.length,
                separatorBuilder: (_, __)=>const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = data[i];
                  return ListTile(
                    title: Text('${p['name']}'),
                    subtitle: Text('SKU: ${p['sku']}  •  Cat: ${p['category']}  •  Stock: ${p['stock']}'),
                    trailing: Text('\$${((p['default_sale_price'] as num?) ?? 0).toStringAsFixed(2)}'),
                    onTap: () async {
                      _skuCtrl.text = (p['sku'] ?? '').toString();
                      _nameCtrl.text = (p['name'] ?? '').toString();
                      _catCtrl.text  = (p['category'] ?? 'general').toString();
                      _saleCtrl.text = ((p['default_sale_price'] as num?) ?? 0).toString();
                      _costCtrl.text = ((p['last_purchase_price'] as num?) ?? 0).toString();
                      _stockCtrl.text = ((p['stock'] as num?) ?? 0).toString();
                      await _showEditDialog(isEditing: true);
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}