// lib/ui/inventory_page.dart
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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

  // Sugerencias de compra (reporte)
  List<PurchaseSuggestion> _purchaseSuggestions = [];
  bool _loadingRecommendations = false;

  // Enriquecido: sugerencias con categoría + agrupación
  final Map<String, List<_SuggestionRow>> _suggestionsByCategory = {};
  List<String> _suggestionCategoryOrder = [];

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

  // ================== SUGERENCIAS (REPORTE) ==================

  Future<void> _loadRecommendations() async {
    if (!_loadingRecommendations) {
      setState(() => _loadingRecommendations = true);
    }

    try {
      final db = await _db();

      // 1) Trae sugerencias (sin tocar la lógica original)
      final suggestions = await fetchPurchaseSuggestions(db); // <- SIN límite

      // 2) Enriquecer con categoría desde products (por SKU)
      final skuToCategory = await _mapSkuToCategory(db, suggestions.map((e) => e.sku).toList());

      // 3) Convertir a filas enriquecidas y agrupar por categoría
      final rows = suggestions.map((s) {
        final cat = _normalizeCategory(skuToCategory[s.sku]);
        return _SuggestionRow(
          category: cat,
          sku: s.sku,
          name: s.name,
          stock: s.stock,
          soldLastPeriod: s.soldLastPeriod,
          suggestedQuantity: s.suggestedQuantity,
          estimatedCost: s.estimatedCost,
        );
      }).toList();

      final grouped = <String, List<_SuggestionRow>>{};
      for (final r in rows) {
        grouped.putIfAbsent(r.category, () => []).add(r);
      }

      // Orden: categorías alfabético, pero "(Sin categoría)" al final
      final cats = grouped.keys.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (cats.contains('(Sin categoría)')) {
        cats.remove('(Sin categoría)');
        cats.add('(Sin categoría)');
      }

      // Dentro de cada categoría: ordenar por "urgencia" (sugerido desc, y luego costo desc)
      for (final c in cats) {
        grouped[c]!.sort((a, b) {
          final q = b.suggestedQuantity.compareTo(a.suggestedQuantity);
          if (q != 0) return q;
          return b.estimatedCost.compareTo(a.estimatedCost);
        });
      }

      if (!mounted) return;
      setState(() {
        _purchaseSuggestions = suggestions;
        _suggestionsByCategory
          ..clear()
          ..addAll(grouped);
        _suggestionCategoryOrder = cats;
        _loadingRecommendations = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadingRecommendations = false);
      }
    }
  }

  String _normalizeCategory(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return '(Sin categoría)';
    return v;
  }

  Future<Map<String, String?>> _mapSkuToCategory(Database db, List<String> skus) async {
    final map = <String, String?>{};
    if (skus.isEmpty) return map;

    // Quitar duplicados
    final uniq = skus.toSet().toList();
    // SQLite tiene límite de parámetros; chunk por seguridad
    const chunkSize = 450;

    for (int i = 0; i < uniq.length; i += chunkSize) {
      final chunk = uniq.sublist(i, (i + chunkSize > uniq.length) ? uniq.length : (i + chunkSize));
      final placeholders = List.filled(chunk.length, '?').join(',');

      final rows = await db.rawQuery('''
        SELECT sku, category
        FROM products
        WHERE sku IN ($placeholders)
      ''', chunk);

      for (final r in rows) {
        final sku = (r['sku'] ?? '').toString();
        final cat = r['category']?.toString();
        map[sku] = cat;
      }
    }

    // Para SKUs no encontrados, regresa null
    for (final sku in uniq) {
      map.putIfAbsent(sku, () => null);
    }

    return map;
  }

  double _totalEstimatedCostAll() {
    double sum = 0.0;
    for (final c in _suggestionsByCategory.values) {
      for (final r in c) {
        sum += r.estimatedCost;
      }
    }
    return sum;
  }

  int _totalSuggestedUnitsAll() {
    int sum = 0;
    for (final c in _suggestionsByCategory.values) {
      for (final r in c) {
        sum += r.suggestedQuantity;
      }
    }
    return sum;
  }

  // Export Excel
  Future<void> _exportSuggestionsToExcel() async {
    try {
      if (_suggestionsByCategory.isEmpty) {
        _snack('No hay sugerencias para exportar');
        return;
      }

      final excel = Excel.createExcel();
      excel.delete('Sheet1');

      final sheet = excel['Sugerencias_compra'];

      // Encabezados
      sheet.appendRow([
        TextCellValue('Categoría'),
        TextCellValue('SKU'),
        TextCellValue('Producto'),
        TextCellValue('Stock'),
        TextCellValue('Ventas recientes'),
        TextCellValue('Sugerido comprar'),
        TextCellValue('Costo estimado'),
      ]);

      // Filas
      for (final cat in _suggestionCategoryOrder) {
        final rows = _suggestionsByCategory[cat] ?? const [];
        for (final r in rows) {
          sheet.appendRow([
            TextCellValue(r.category),
            TextCellValue(r.sku),
            TextCellValue(r.name),
            IntCellValue(r.stock),
            IntCellValue(r.soldLastPeriod),
            IntCellValue(r.suggestedQuantity),
            DoubleCellValue(r.estimatedCost),
          ]);
        }

        // Totales por categoría
        final catUnits = rows.fold<int>(0, (a, b) => a + b.suggestedQuantity);
        final catCost = rows.fold<double>(0.0, (a, b) => a + b.estimatedCost);
        sheet.appendRow([
          TextCellValue('${cat} (TOTAL)'),
          const TextCellValue(''),
          const TextCellValue(''),
          const TextCellValue(''),
          const TextCellValue(''),
          IntCellValue(catUnits),
          DoubleCellValue(catCost),
        ]);

        // Línea en blanco
        sheet.appendRow([
          const TextCellValue(''),
          const TextCellValue(''),
          const TextCellValue(''),
          const TextCellValue(''),
          const TextCellValue(''),
          const TextCellValue(''),
          const TextCellValue(''),
        ]);
      }

      // Totales generales
      sheet.appendRow([
        const TextCellValue('TOTAL GENERAL'),
        const TextCellValue(''),
        const TextCellValue(''),
        const TextCellValue(''),
        const TextCellValue(''),
        IntCellValue(_totalSuggestedUnitsAll()),
        DoubleCellValue(_totalEstimatedCostAll()),
      ]);

      // Guardar y compartir
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

  // ================== CATEGORÍAS / PRODUCTOS ==================

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

  // ================== UI ==================

  @override
  Widget build(BuildContext context) {
    final lowCount = _products.where((p) => (p['stock'] as num? ?? 0) <= 2).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario'),
        actions: [
          IconButton(
            tooltip: 'Exportar sugerencias (Excel)',
            onPressed: _suggestionsByCategory.isEmpty ? null : _exportSuggestionsToExcel,
            icon: const Icon(Icons.download),
          ),
          IconButton(
            tooltip: 'Actualizar todo',
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
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
            // Reporte de sugerencias agrupado
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: _buildSuggestionsReport(),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            // Filtros productos
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

  // ================== REPORTE VISUAL EN APP ==================

  Widget _buildSuggestionsReport() {
    if (_loadingRecommendations) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_suggestionsByCategory.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Reporte de sugerencias de compra', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Inventario saludable: no hay compras urgentes basadas en las ventas recientes.'),
            ],
          ),
        ),
      );
    }

    final totalUnits = _totalSuggestedUnitsAll();
    final totalCost = _totalEstimatedCostAll();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Reporte de sugerencias de compra',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Exportar a Excel',
                  onPressed: _exportSuggestionsToExcel,
                  icon: const Icon(Icons.download),
                ),
                IconButton(
                  tooltip: 'Actualizar sugerencias',
                  onPressed: _loadRecommendations,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _MiniStatChip(
                  icon: Icons.shopping_cart,
                  label: 'Total sugerido',
                  value: '$totalUnits pzas',
                ),
                _MiniStatChip(
                  icon: Icons.payments,
                  label: 'Costo estimado',
                  value: _money.format(totalCost),
                ),
                _MiniStatChip(
                  icon: Icons.category,
                  label: 'Categorías',
                  value: '${_suggestionCategoryOrder.length}',
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 10),

            // Categorías agrupadas
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _suggestionCategoryOrder.length,
              itemBuilder: (_, idx) {
                final cat = _suggestionCategoryOrder[idx];
                final rows = _suggestionsByCategory[cat] ?? const [];

                final catUnits = rows.fold<int>(0, (a, b) => a + b.suggestedQuantity);
                final catCost = rows.fold<double>(0.0, (a, b) => a + b.estimatedCost);

                return _CategorySuggestionSection(
                  category: cat,
                  totalUnits: catUnits,
                  totalCost: catCost,
                  money: _money,
                  rows: rows,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ================== UI helpers ==================

class _MiniStatChip extends StatelessWidget {
  const _MiniStatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    );
  }
}

class _CategorySuggestionSection extends StatelessWidget {
  const _CategorySuggestionSection({
    required this.category,
    required this.totalUnits,
    required this.totalCost,
    required this.money,
    required this.rows,
  });

  final String category;
  final int totalUnits;
  final double totalCost;
  final NumberFormat money;
  final List<_SuggestionRow> rows;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: rows.length <= 6,
      title: Text(category, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('Sugerido: $totalUnits pzas • ${money.format(totalCost)}'),
      children: [
        const Divider(height: 1),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final s = rows[i];
            return ListTile(
              dense: true,
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
                  Text('Comprar ${s.suggestedQuantity}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(money.format(s.estimatedCost)),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ================== Modelo interno enriquecido ==================

class _SuggestionRow {
  _SuggestionRow({
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