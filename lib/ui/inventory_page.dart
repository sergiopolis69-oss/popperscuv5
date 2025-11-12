// lib/ui/inventory_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database.dart' as appdb;
import '../utils/purchase_advisor.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({Key? key}) : super(key: key);

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

  // Datos
  List<Map<String, dynamic>> _products = [];
  List<String> _categories = [];
  String? _selectedCategory;
  bool _lowStockOnly = false;

  // Sugerencias de compra
  List<PurchaseSuggestion> _purchaseSuggestions = [];
  bool _loadingRecommendations = false;

  // Búsqueda
  final _qCtrl = TextEditingController();

  // Form de producto
  final _skuCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _salePriceCtrl = TextEditingController(text: '0');
  final _lastCostCtrl = TextEditingController(text: '0');
  final _stockCtrl = TextEditingController(text: '0');

  int? _editingId;
  String? _selectedDialogCategory;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    _skuCtrl.dispose();
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _salePriceCtrl.dispose();
    _lastCostCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<Database> _db() async {
    try {
      return await appdb.getDb();
    } catch (_) {
      return await appdb.DatabaseHelper.instance.db;
    }
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadCategories(),
      _loadProducts(),
      _loadRecommendations(),
    ]);
  }

  Future<void> _loadRecommendations() async {
    if (!_loadingRecommendations) {
      setState(() => _loadingRecommendations = true);
    }
    try {
      final db = await _db();
      final suggestions = await fetchPurchaseSuggestions(db); // <- SIN límite
      if (!mounted) return;
      setState(() {
        _purchaseSuggestions = suggestions;
        _loadingRecommendations = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingRecommendations = false);
      }
    }
  }

  Future<void> _loadCategories() async {
    final db = await _db();
    final rows = await db.rawQuery('''
      SELECT DISTINCT COALESCE(NULLIF(TRIM(category),''), '(Sin categoría)') AS cat
      FROM products
      ORDER BY cat COLLATE NOCASE
    ''');
    final list = rows.map((e) => (e['cat'] as String)).toList();
    setState(() {
      _categories = list;
      if (_selectedCategory != null && !_categories.contains(_selectedCategory)) {
        _selectedCategory = null;
      }
    });
  }

  Future<void> _loadProducts() async {
    final db = await _db();
    final q = _qCtrl.text.trim();
    final where = <String>[];
    final args = <Object?>[];

    if (_selectedCategory != null) {
      if (_selectedCategory == '(Sin categoría)') {
        where.add("(category IS NULL OR TRIM(category) = '')");
      } else {
        where.add("category = ?");
        args.add(_selectedCategory);
      }
    }

    if (q.isNotEmpty) {
      where.add("(sku LIKE ? OR name LIKE ?)");
      args.addAll(['%$q%', '%$q%']);
    }

    if (_lowStockOnly) {
      where.add("(COALESCE(stock,0) <= 2)");
    }

    final sql = StringBuffer()
      ..write('SELECT id, sku, name, category, default_sale_price, last_purchase_price, stock ')
      ..write('FROM products ');
    if (where.isNotEmpty) {
      sql.write('WHERE ${where.join(' AND ')} ');
    }
    sql.write('ORDER BY name COLLATE NOCASE');

    final rows = await db.rawQuery(sql.toString(), args);
    setState(() => _products = rows);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _startCreate() {
    setState(() {
      _editingId = null;
      _skuCtrl.text = '';
      _nameCtrl.text = '';
      _salePriceCtrl.text = '0';
      _lastCostCtrl.text = '0';
      _stockCtrl.text = '0';
      _categoryCtrl.text = '';
      _selectedDialogCategory = null;
    });
    _showProductDialog(title: 'Nuevo producto');
  }

  void _startEdit(Map<String, dynamic> p) {
    setState(() {
      _editingId = p['id'] as int;
      _skuCtrl.text = (p['sku'] ?? '').toString();
      _nameCtrl.text = (p['name'] ?? '').toString();
      _salePriceCtrl.text =
          ((p['default_sale_price'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
      _lastCostCtrl.text =
          ((p['last_purchase_price'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
      _stockCtrl.text = ((p['stock'] as num?)?.toInt() ?? 0).toString();
      _categoryCtrl.text = '';
      _selectedDialogCategory =
          (p['category'] == null || (p['category'] as String).trim().isEmpty)
              ? '(Sin categoría)'
              : (p['category'] as String);
    });
    _showProductDialog(title: 'Editar producto');
  }

  Future<void> _deleteProduct(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: const Text('¿Seguro que deseas eliminar este producto?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;

    final db = await _db();
    await db.delete('products', where: 'id=?', whereArgs: [id]);
    _snack('Producto eliminado');
    await _loadAll();
  }

  Future<void> _showProductDialog({required String title}) async {
    if (_categories.isEmpty) {
      await _loadCategories();
    }
    _selectedDialogCategory ??= _categories.isNotEmpty ? _categories.first : '(Sin categoría)';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, bottom: bottomInset + 16, top: 8),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextField(controller: _skuCtrl, decoration: const InputDecoration(labelText: 'SKU *')),
                const SizedBox(height: 8),
                TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Nombre *')),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedDialogCategory,
                        items: <String>['(Sin categoría)', ..._categories.where((c) => c != '(Sin categoría)')]
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedDialogCategory = v),
                        decoration: const InputDecoration(labelText: 'Categoría'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Agregar nueva categoría',
                      onPressed: () async {
                        final newCat = await _askNewCategory();
                        if (newCat != null && newCat.trim().isNotEmpty) {
                          if (!_categories.contains(newCat)) {
                            setState(() => _categories = [..._categories, newCat]);
                          }
                          setState(() => _selectedDialogCategory = newCat);
                        }
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _salePriceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Precio de venta'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _lastCostCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Último costo de compra'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _stockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Existencia'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (_editingId != null)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _deleteProduct(_editingId!);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Eliminar'),
                      ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _saveProduct,
                      icon: const Icon(Icons.save),
                      label: const Text('Guardar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _askNewCategory() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nueva categoría'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Nombre')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Agregar')),
        ],
      ),
    );
    if (ok == true) return ctrl.text.trim();
    return null;
  }

  Future<void> _saveProduct() async {
    final sku = _skuCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (sku.isEmpty || name.isEmpty) {
      _snack('SKU y nombre son obligatorios');
      return;
    }

    String? category;
    if (_selectedDialogCategory != null && _selectedDialogCategory != '(Sin categoría)') {
      category = _selectedDialogCategory;
    }

    final salePrice = double.tryParse(_salePriceCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;
    final lastCost = double.tryParse(_lastCostCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;
    final stock = int.tryParse(_stockCtrl.text.trim()) ?? 0;

    final db = await _db();
    final data = <String, Object?>{
      'sku': sku,
      'name': name,
      'category': category,
      'default_sale_price': salePrice,
      'last_purchase_price': lastCost,
      'stock': stock,
    };

    try {
      if (_editingId == null) {
        await db.insert('products', data, conflictAlgorithm: ConflictAlgorithm.abort);
        _snack('Producto agregado');
      } else {
        await db.update('products', data, where: 'id=?', whereArgs: [_editingId]);
        _snack('Producto actualizado');
      }
      if (mounted) Navigator.of(context).pop();
      await _loadAll();
    } catch (e) {
      _snack('Error al guardar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lowCount = _products.where((p) => (p['stock'] as num? ?? 0) <= 2).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario'),
        actions: [IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh))],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _qCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar por SKU o nombre…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                suffixIcon: _qCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _qCtrl.clear();
                          _loadProducts();
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
              onChanged: (_) => _loadProducts(),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startCreate,
        icon: const Icon(Icons.add),
        label: const Text('Agregar'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Sugerencias (TODAS)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: _buildSuggestionsCard(),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            // Filtros
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        value: _selectedCategory,
                        isExpanded: true,
                        items: <String?>[null, ..._categories]
                            .map((c) => DropdownMenuItem<String?>(
                                  value: c,
                                  child: Text(c ?? 'Todas las categorías'),
                                ))
                            .toList(),
                        onChanged: (v) {
                          setState(() => _selectedCategory = v);
                          _loadProducts();
                        },
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Filtrar por categoría',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text('Existencia ≤ 2${lowCount > 0 ? ' ($lowCount)' : ''}'),
                      selected: _lowStockOnly,
                      onSelected: (v) {
                        setState(() => _lowStockOnly = v);
                        _loadProducts();
                      },
                      avatar: const Icon(Icons.warning_amber_outlined, size: 18),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: Divider(height: 0)),
            // Lista de productos
            if (_products.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('No hay productos')),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final p = _products[index];
                    final stock = (p['stock'] as num?)?.toInt() ?? 0;
                    final low = stock <= 2;
                    final cat = (p['category'] == null || (p['category'] as String).trim().isEmpty)
                        ? '(Sin categoría)'
                        : (p['category'] as String);
                    return Column(
                      children: [
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: low ? Colors.red.shade50 : Colors.blue.shade50,
                            child: Icon(low ? Icons.priority_high : Icons.inventory_2,
                                color: low ? Colors.red : Colors.blue),
                          ),
                          title: Text(p['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('SKU: ${p['sku']} • $cat • Stock: $stock'),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit),
                            tooltip: 'Editar',
                            onPressed: () => _startEdit(p),
                          ),
                        ),
                        if (index != _products.length - 1) const Divider(height: 0),
                      ],
                    );
                  },
                  childCount: _products.length,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ===== Tarjeta de sugerencias (TODAS) ======================================
  Widget _buildSuggestionsCard() {
    if (_loadingRecommendations) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_purchaseSuggestions.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Sugerencias de compra', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Inventario saludable: no hay compras urgentes basadas en las ventas recientes.'),
            ],
          ),
        ),
      );
    }

    // MUESTRA TODAS LAS SUGERENCIAS, SIN LÍMITE
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sugerencias de compra', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _purchaseSuggestions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final s = _purchaseSuggestions[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.shade100,
                    child: const Icon(Icons.shopping_bag, color: Colors.deepOrange),
                  ),
                  title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('SKU ${s.sku} • Stock ${s.stock} • Ventas recientes ${s.soldLastPeriod}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Comprar ${s.suggestedQuantity}'),
                      Text(_money.format(s.estimatedCost), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  onLongPress: () {
                    final line = '${s.sku}\t${s.name}\tStock:${s.stock}\tSug:${s.suggestedQuantity}\t${_money.format(s.estimatedCost)}';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Copiado: $line')),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}