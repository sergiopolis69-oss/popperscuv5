// lib/ui/inventory_page.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

// ✅ ALIAS para evitar choque con Border de Flutter
import 'package:excel/excel.dart' as ex;

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

  // Sugerencias de compra (base)
  List<PurchaseSuggestion> _purchaseSuggestions = [];
  bool _loadingRecommendations = false;

  // ===== Reporte (agrupado) =====
  final Map<String, List<_SugRow>> _suggestionsByCategory = {};
  final List<String> _suggestionCategoryOrder = [];

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
    if (!_loadingRecommendations) setState(() => _loadingRecommendations = true);

    try {
      final db = await _db();
      final suggestions = await fetchPurchaseSuggestions(db); // <- SIN límite
      final report = await _buildSuggestionsReport(db, suggestions);

      if (!mounted) return;
      setState(() {
        _purchaseSuggestions = suggestions;
        _suggestionsByCategory
          ..clear()
          ..addAll(report.byCategory);
        _suggestionCategoryOrder
          ..clear()
          ..addAll(report.categoryOrder);
        _loadingRecommendations = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRecommendations = false);
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

    if (_lowStockOnly) where.add("(COALESCE(stock,0) <= 2)");

    final sql = StringBuffer()
      ..write('SELECT id, sku, name, category, default_sale_price, last_purchase_price, stock ')
      ..write('FROM products ');
    if (where.isNotEmpty) sql.write('WHERE ${where.join(' AND ')} ');
    sql.write('ORDER BY name COLLATE NOCASE');

    final rows = await db.rawQuery(sql.toString(), args);
    setState(() => _products = rows);
  }

  void _snack(String msg) {
    if (!mounted) return;
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
      _editingId = (p['id'] as num).toInt();
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

  // ✅ BottomSheet ajustado para nav buttons + teclado
  Future<void> _showProductDialog({required String title}) async {
    if (_categories.isEmpty) await _loadCategories();
    _selectedDialogCategory ??= _categories.isNotEmpty ? _categories.first : '(Sin categoría)';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) {
        final mq = MediaQuery.of(context);
        final keyboard = mq.viewInsets.bottom;
        final bottomSafe = mq.padding.bottom;

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: keyboard + bottomSafe + 16,
          ),
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
                        items: <String>[
                          '(Sin categoría)',
                          ..._categories.where((c) => c != '(Sin categoría)')
                        ].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
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

  // ===========================
  // NUEVO: resumen/historial SKU
  // ===========================
  Future<void> _showSkuHistory(Map<String, dynamic> p) async {
    final db = await _db();
    final productId = (p['id'] as num).toInt();
    final sku = (p['sku'] ?? '').toString();
    final name = (p['name'] ?? '').toString();
    final stock = ((p['stock'] as num?)?.toInt() ?? 0);
    final lastCost = ((p['last_purchase_price'] as num?)?.toDouble() ?? 0.0);

    // Ventas: agregados
    final salesAgg = await db.rawQuery('''
      SELECT
        COALESCE(SUM(si.quantity),0) AS qty,
        COALESCE(SUM(si.quantity * si.unit_price),0) AS revenue
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE si.product_id = ?
    ''', [productId]);

    final soldQty = ((salesAgg.first['qty'] as num?) ?? 0).toInt();
    final revenue = ((salesAgg.first['revenue'] as num?) ?? 0).toDouble();

    // Ventas: últimas 50
    final salesRows = await db.rawQuery('''
      SELECT s.date AS date, si.quantity AS qty, si.unit_price AS unit_price
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE si.product_id = ?
      ORDER BY s.date DESC, si.sale_id DESC
      LIMIT 50
    ''', [productId]);

    // Compras: intentamos unit_cost, si no unit_price
    int boughtQty = 0;
    double boughtCost = 0.0;
    List<Map<String, dynamic>> purchaseRows = [];
    bool hasPurchases = false;

    Future<bool> tryPurchases(String costCol) async {
      try {
        final purAgg = await db.rawQuery('''
          SELECT
            COALESCE(SUM(pi.quantity),0) AS qty,
            COALESCE(SUM(pi.quantity * COALESCE(pi.$costCol,0)),0) AS cost
          FROM purchase_items pi
          JOIN purchases p ON p.id = pi.purchase_id
          WHERE pi.product_id = ?
        ''', [productId]);

        boughtQty = ((purAgg.first['qty'] as num?) ?? 0).toInt();
        boughtCost = ((purAgg.first['cost'] as num?) ?? 0).toDouble();

        final rows = await db.rawQuery('''
          SELECT p.date AS date, pi.quantity AS qty, COALESCE(pi.$costCol,0) AS unit_cost
          FROM purchase_items pi
          JOIN purchases p ON p.id = pi.purchase_id
          WHERE pi.product_id = ?
          ORDER BY p.date DESC, pi.purchase_id DESC
          LIMIT 50
        ''', [productId]);

        purchaseRows = rows.cast<Map<String, dynamic>>();
        return true;
      } catch (_) {
        return false;
      }
    }

    hasPurchases = await tryPurchases('unit_cost') || await tryPurchases('unit_price');

    // Utilidad estimada:
    // - Si hay compras: revenue - boughtCost (ojo: esto es “costo comprado”, si compras más de lo vendido, se infla el costo)
    // - Si no hay compras: revenue - (soldQty * lastCost)
    //
    // Para no “romper” nada, lo dejamos simple, pero mostramos etiqueta "estimado".
    final estCostForSold = hasPurchases ? boughtCost : (soldQty * lastCost);
    final estProfit = revenue - estCostForSold;
    final estMargin = revenue > 0 ? (estProfit / revenue) : 0.0;

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) {
        final mq = MediaQuery.of(context);
        final bottomSafe = mq.padding.bottom;

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottomSafe + 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$sku • $name', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _chipStat('Stock', '$stock'),
                  _chipStat('Vendidas', '$soldQty'),
                  _chipStat('Ingresos', _money.format(revenue)),
                  _chipStat('Costo est.', _money.format(estCostForSold)),
                  _chipStat('Utilidad est.', _money.format(estProfit)),
                  _chipStat('Margen est.', '${(estMargin * 100).toStringAsFixed(1)}%'),
                  if (hasPurchases) _chipStat('Compradas', '$boughtQty'),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              Expanded(
                child: ListView(
                  children: [
                    Text('Historial de ventas', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    if (salesRows.isEmpty)
                      const Text('Sin ventas registradas para este SKU.')
                    else
                      ...salesRows.map((r) {
                        final date = (r['date'] ?? '').toString();
                        final qty = ((r['qty'] as num?) ?? 0).toInt();
                        final unit = ((r['unit_price'] as num?) ?? 0).toDouble();
                        final total = qty * unit;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.trending_up),
                          title: Text('$qty × ${_money.format(unit)}'),
                          subtitle: Text(date),
                          trailing: Text(_money.format(total),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        );
                      }),

                    const SizedBox(height: 12),
                    Text('Historial de compras', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    if (!hasPurchases)
                      const Text('No se pudo leer purchases/purchase_items (tablas/columnas).')
                    else if (purchaseRows.isEmpty)
                      const Text('Sin compras registradas para este SKU.')
                    else
                      ...purchaseRows.map((r) {
                        final date = (r['date'] ?? '').toString();
                        final qty = ((r['qty'] as num?) ?? 0).toInt();
                        final unit = ((r['unit_cost'] as num?) ?? 0).toDouble();
                        final total = qty * unit;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.shopping_cart),
                          title: Text('$qty × ${_money.format(unit)}'),
                          subtitle: Text(date),
                          trailing: Text(_money.format(total),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chipStat(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(v),
        ],
      ),
    );
  }

  // =======================
  // BUILD (✅ DENTRO DE LA CLASE)
  // =======================
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: _buildSuggestionsReportCard(),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
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
                          // ✅ Tap abre resumen/historial SKU
                          onTap: () => _showSkuHistory(p),
                          leading: CircleAvatar(
                            backgroundColor: low ? Colors.red.shade50 : Colors.blue.shade50,
                            child: Icon(
                              low ? Icons.priority_high : Icons.inventory_2,
                              color: low ? Colors.red : Colors.blue,
                            ),
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

  // ===== Reporte visualizable + export ======================================
  Widget _buildSuggestionsReportCard() {
    if (_loadingRecommendations) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_purchaseSuggestions.isEmpty || _suggestionsByCategory.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Reporte de sugerencias de compra', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Inventario saludable: no hay compras urgentes basadas en las ventas recientes.'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loadRecommendations,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar'),
              ),
            ],
          ),
        ),
      );
    }

    final totalUnits = _totalSuggestedUnitsAll();
    final totalCost = _totalEstimatedCostAll();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reporte de sugerencias de compra', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _miniStat('Total sugerido', '$totalUnits pzas'),
                _miniStat('Costo estimado', _money.format(totalCost)),
                OutlinedButton.icon(
                  onPressed: _loadRecommendations,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualizar'),
                ),
                FilledButton.icon(
                  onPressed: _exportSuggestionsToExcel,
                  icon: const Icon(Icons.file_download),
                  label: const Text('Exportar Excel'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 6),
            ..._suggestionCategoryOrder.map((cat) {
              final rows = _suggestionsByCategory[cat] ?? const <_SugRow>[];
              if (rows.isEmpty) return const SizedBox.shrink();

              final catUnits = rows.fold<int>(0, (a, b) => a + b.suggestedQuantity);
              final catCost = rows.fold<double>(0.0, (a, b) => a + b.estimatedCost);

              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Text(cat, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('Sugerido: $catUnits pzas • ${_money.format(catCost)}'),
                  children: [
                    const Divider(height: 1),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 0),
                      itemBuilder: (_, i) {
                        final s = rows[i];
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
                            final line =
                                '${s.category}\t${s.sku}\t${s.name}\tStock:${s.stock}\tVend:${s.soldLastPeriod}\tSug:${s.suggestedQuantity}\t${_money.format(s.estimatedCost)}';
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Copiado: $line')),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(v),
        ],
      ),
    );
  }

  int _totalSuggestedUnitsAll() {
    int total = 0;
    for (final cat in _suggestionCategoryOrder) {
      final rows = _suggestionsByCategory[cat] ?? const <_SugRow>[];
      total += rows.fold<int>(0, (a, b) => a + b.suggestedQuantity);
    }
    return total;
  }

  double _totalEstimatedCostAll() {
    double total = 0.0;
    for (final cat in _suggestionCategoryOrder) {
      final rows = _suggestionsByCategory[cat] ?? const <_SugRow>[];
      total += rows.fold<double>(0.0, (a, b) => a + b.estimatedCost);
    }
    return total;
  }

  Future<_SugReport> _buildSuggestionsReport(Database db, List<PurchaseSuggestion> suggestions) async {
    if (suggestions.isEmpty) {
      return _SugReport(byCategory: {}, categoryOrder: const []);
    }

    final skus = suggestions.map((s) => s.sku).where((e) => e.trim().isNotEmpty).toSet().toList();
    final skuToCategory = <String, String>{};

    if (skus.isNotEmpty) {
      final placeholders = List.filled(skus.length, '?').join(',');
      final rows = await db.rawQuery('''
        SELECT sku, COALESCE(NULLIF(TRIM(category), ''), '(Sin categoría)') AS cat
        FROM products
        WHERE sku IN ($placeholders)
      ''', skus);

      for (final r in rows) {
        final sku = (r['sku'] ?? '').toString();
        final cat = (r['cat'] ?? '(Sin categoría)').toString();
        if (sku.isNotEmpty) skuToCategory[sku] = cat;
      }
    }

    final byCategory = <String, List<_SugRow>>{};
    for (final s in suggestions) {
      final cat = skuToCategory[s.sku] ?? '(Sin categoría)';
      final row = _SugRow(
        category: cat,
        sku: s.sku,
        name: s.name,
        stock: s.stock,
        soldLastPeriod: s.soldLastPeriod,
        suggestedQuantity: s.suggestedQuantity,
        estimatedCost: s.estimatedCost,
      );
      (byCategory[cat] ??= []).add(row);
    }

    final catOrder = byCategory.keys.toList()
      ..sort((a, b) {
        final aCost = (byCategory[a] ?? const []).fold<double>(0.0, (x, y) => x + y.estimatedCost);
        final bCost = (byCategory[b] ?? const []).fold<double>(0.0, (x, y) => x + y.estimatedCost);
        return bCost.compareTo(aCost);
      });

    for (final cat in catOrder) {
      byCategory[cat]!.sort((x, y) => y.estimatedCost.compareTo(x.estimatedCost));
    }

    return _SugReport(byCategory: byCategory, categoryOrder: catOrder);
  }

  Future<void> _exportSuggestionsToExcel() async {
    try {
      if (_suggestionsByCategory.isEmpty) {
        _snack('No hay sugerencias para exportar');
        return;
      }

      final excel = ex.Excel.createExcel();
      excel.delete('Sheet1');

      final sheet = excel['Sugerencias_compra'];

      sheet.appendRow([
        ex.TextCellValue('Categoría'),
        ex.TextCellValue('SKU'),
        ex.TextCellValue('Producto'),
        ex.TextCellValue('Stock'),
        ex.TextCellValue('Ventas recientes'),
        ex.TextCellValue('Sugerido comprar'),
        ex.TextCellValue('Costo estimado'),
      ]);

      for (final cat in _suggestionCategoryOrder) {
        final rows = _suggestionsByCategory[cat] ?? const <_SugRow>[];

        for (final r in rows) {
          sheet.appendRow([
            ex.TextCellValue(r.category),
            ex.TextCellValue(r.sku),
            ex.TextCellValue(r.name),
            ex.IntCellValue(r.stock),
            ex.IntCellValue(r.soldLastPeriod),
            ex.IntCellValue(r.suggestedQuantity),
            ex.DoubleCellValue(r.estimatedCost),
          ]);
        }

        final catUnits = rows.fold<int>(0, (a, b) => a + b.suggestedQuantity);
        final catCost = rows.fold<double>(0.0, (a, b) => a + b.estimatedCost);

        sheet.appendRow([
          ex.TextCellValue('$cat (TOTAL)'),
          ex.TextCellValue(''),
          ex.TextCellValue(''),
          ex.TextCellValue(''),
          ex.TextCellValue(''),
          ex.IntCellValue(catUnits),
          ex.DoubleCellValue(catCost),
        ]);

        sheet.appendRow([
          ex.TextCellValue(''),
          ex.TextCellValue(''),
          ex.TextCellValue(''),
          ex.TextCellValue(''),
          ex.TextCellValue(''),
          ex.TextCellValue(''),
          ex.TextCellValue(''),
        ]);
      }

      sheet.appendRow([
        ex.TextCellValue('TOTAL GENERAL'),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.TextCellValue(''),
        ex.IntCellValue(_totalSuggestedUnitsAll()),
        ex.DoubleCellValue(_totalEstimatedCostAll()),
      ]);

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/reporte_sugerencias_compra.xlsx');

      final bytes = excel.encode();
      if (bytes == null) throw Exception('No se pudo generar el Excel');

      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Reporte de sugerencias de compra',
        text:
            'Reporte exportado: sugerencias de compra agrupadas por categoría.\n'
            'Total sugerido: ${_totalSuggestedUnitsAll()} pzas\n'
            'Costo estimado: ${_money.format(_totalEstimatedCostAll())}',
      );
    } catch (e) {
      _snack('Error exportando Excel: $e');
    }
  }
}

// ======= modelos internos =========
class _SugRow {
  _SugRow({
    required this.category,
    required this.sku,
    required this.name,
    required this.stock,
    required this.soldLastPeriod,
    required this.suggestedQuantity,
    required this.estimatedCost,
  });

  final String category;
  final String sku;
  final String name;
  final int stock;
  final int soldLastPeriod;
  final int suggestedQuantity;
  final double estimatedCost;
}

class _SugReport {
  _SugReport({required this.byCategory, required this.categoryOrder});

  final Map<String, List<_SugRow>> byCategory;
  final List<String> categoryOrder;
}