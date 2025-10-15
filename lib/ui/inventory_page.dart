import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:popperscuv5/data/database.dart' as appdb;

class InventoryPage extends StatefulWidget {
  const InventoryPage({Key? key}) : super(key: key);

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _qCtrl = TextEditingController();
  final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

  List<Map<String, dynamic>> _rows = [];
  List<String> _categories = []; // categorías existentes en DB (distintas)
  String? _catFilter; // null = todas; '' = (sin categoría); otro = categoría
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _load(); // carga inicial
    _qCtrl.addListener(_onQChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _qCtrl.removeListener(_onQChanged);
    _qCtrl.dispose();
    super.dispose();
  }

  void _onQChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _load(q: _qCtrl.text.trim(), category: _catFilter);
    });
  }

  Future<void> _loadCategories() async {
    final db = await appdb.DatabaseHelper.instance.db;
    final rows = await db.rawQuery('''
      SELECT DISTINCT TRIM(category) AS c
      FROM products
      WHERE category IS NOT NULL AND TRIM(category) <> ''
      ORDER BY c COLLATE NOCASE
    ''');
    final list = rows
        .map((r) => (r['c'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toList();
    if (!mounted) return;
    setState(() {
      _categories = list;
    });
  }

  Future<void> _load({String? q, String? category}) async {
    final db = await appdb.DatabaseHelper.instance.db;

    final hasQ = q != null && q.isNotEmpty;
    final hasCat = category != null; // null = todas
    final catIsNull = hasCat && category == ''; // '' => (sin categoría)

    final whereParts = <String>[];
    final args = <Object?>[];

    if (hasQ) {
      whereParts.add('(sku LIKE ? OR name LIKE ?)');
      args.add('%$q%');
      args.add('%$q%');
    }
    if (hasCat) {
      if (catIsNull) {
        whereParts.add('(category IS NULL OR TRIM(category) = "")');
      } else {
        whereParts.add('TRIM(category) = ?');
        args.add(category);
      }
    }

    final where = whereParts.isEmpty ? '' : 'WHERE ${whereParts.join(' AND ')}';

    final rows = await db.rawQuery('''
      SELECT id, sku, name, category,
             default_sale_price, last_purchase_price, stock
      FROM products
      $where
      ORDER BY name COLLATE NOCASE
    ''', args);

    if (!mounted) return;
    setState(() => _rows = rows);
  }

  Future<void> _openEdit({Map<String, dynamic>? product}) async {
    final isEdit = product != null;
    final skuCtrl = TextEditingController(text: (product?['sku'] ?? '').toString());
    final nameCtrl = TextEditingController(text: (product?['name'] ?? '').toString());
    final saleCtrl = TextEditingController(
        text: ((product?['default_sale_price'] as num?)?.toString() ?? '0'));
    final stockCtrl =
        TextEditingController(text: ((product?['stock'] as num?)?.toString() ?? '0'));
    final lastCostCtrl = TextEditingController(
        text: ((product?['last_purchase_price'] as num?)?.toString() ?? '0'));

    // Categoría seleccionada en el formulario
    String? selectedCat = (product?['category'] as String?)?.trim();
    // Asegura que, si la categoría del producto no está en la lista, la incluimos temporalmente
    final localCats = <String>[..._categories];
    if (selectedCat != null && selectedCat.isNotEmpty && !localCats.contains(selectedCat)) {
      localCats.add(selectedCat);
      localCats.sort(
        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
      );
    }

    Future<void> addNewCategoryFlow(BuildContext ctx) async {
      final cCtrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: ctx,
        builder: (_) => AlertDialog(
          title: const Text('Nueva categoría'),
          content: TextField(
            controller: cCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre de la categoría',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Agregar'),
            ),
          ],
        ),
      );
      if (ok == true) {
        final name = cCtrl.text.trim();
        if (name.isEmpty) return;
        // Evita duplicados (case-insensitive)
        final exists = localCats.any((e) => e.toLowerCase() == name.toLowerCase());
        if (!exists) {
          setState(() {
            localCats.add(name);
            localCats.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          });
        }
        selectedCat = name;
      }
    }

    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isEdit ? 'Editar producto' : 'Nuevo producto',
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      icon: const Icon(Icons.close),
                    )
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: skuCtrl,
                  decoration: const InputDecoration(
                    labelText: 'SKU * (único)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre *',
                  ),
                ),
                const SizedBox(height: 8),

                // Categoría: Dropdown + botón "Nueva"
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: (selectedCat == null || selectedCat!.isEmpty)
                            ? '' // mapeamos null/empty -> '' para mostrar "(Sin categoría)"
                            : selectedCat,
                        decoration: const InputDecoration(
                          labelText: 'Categoría',
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: '',
                            child: Text('(Sin categoría)'),
                          ),
                          ...localCats.map((c) => DropdownMenuItem<String>(
                                value: c,
                                child: Text(c),
                              )),
                        ],
                        onChanged: (v) {
                          selectedCat = (v == null || v.isEmpty) ? null : v;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Nueva categoría',
                      onPressed: () => addNewCategoryFlow(ctx),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                TextField(
                  controller: saleCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Precio de venta (default)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: lastCostCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Último costo de compra',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: stockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Stock',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    final sku = skuCtrl.text.trim();
                    final name = nameCtrl.text.trim();
                    final sale = double.tryParse(saleCtrl.text.trim().replaceAll(',', '.')) ?? 0;
                    final last = double.tryParse(lastCostCtrl.text.trim().replaceAll(',', '.')) ?? 0;
                    final stock = int.tryParse(stockCtrl.text.trim()) ?? 0;

                    if (sku.isEmpty || name.isEmpty) {
                      _snack('SKU y Nombre son obligatorios');
                      return;
                    }
                    try {
                      final db = await appdb.DatabaseHelper.instance.db;
                      final map = {
                        'sku': sku,
                        'name': name,
                        'category': (selectedCat == null || selectedCat!.isEmpty) ? null : selectedCat,
                        'default_sale_price': sale,
                        'last_purchase_price': last,
                        'stock': stock,
                      };

                      if (isEdit) {
                        await db.update(
                          'products',
                          map,
                          where: 'id = ?',
                          whereArgs: [product!['id']],
                          conflictAlgorithm: ConflictAlgorithm.abort,
                        );
                      } else {
                        await db.insert(
                          'products',
                          map,
                          conflictAlgorithm: ConflictAlgorithm.abort,
                        );
                      }

                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    } on DatabaseException catch (e) {
                      if (e.isUniqueConstraintError()) {
                        _snack('El SKU ya existe.');
                      } else {
                        _snack('Error al guardar: $e');
                      }
                    } catch (e) {
                      _snack('Error al guardar: $e');
                    }
                  },
                  icon: const Icon(Icons.save),
                  label: Text(isEdit ? 'Guardar cambios' : 'Crear'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (res == true) {
      // refresca categorías (por si se creó/seleccionó una nueva)
      await _loadCategories();
      await _load(q: _qCtrl.text.trim(), category: _catFilter);
      _snack(isEdit ? 'Producto actualizado' : 'Producto creado');
    }
  }

  Future<void> _delete(Map<String, dynamic> product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text(
            '¿Eliminar "${product['name']}" (SKU: ${product['sku']})?\n\n'
            'Si ya fue usado en ventas o compras, no se podrá eliminar.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final db = await appdb.DatabaseHelper.instance.db;
      final id = product['id'] as int;

      final usedInSales = Sqflite.firstIntValue(await db
              .rawQuery('SELECT COUNT(*) FROM sale_items WHERE product_id = ?', [id])) ??
          0;
      final usedInPurchases = Sqflite.firstIntValue(await db
              .rawQuery('SELECT COUNT(*) FROM purchase_items WHERE product_id = ?', [id])) ??
          0;

      if (usedInSales > 0 || usedInPurchases > 0) {
        _snack('No se puede eliminar: el producto tiene movimientos.');
        return;
      }

      await db.delete('products', where: 'id = ?', whereArgs: [id]);
      await _loadCategories();
      await _load(q: _qCtrl.text.trim(), category: _catFilter);
      _snack('Producto eliminado');
    } catch (e) {
      _snack('Error al eliminar: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario'),
        actions: [
          IconButton(
            onPressed: () => _openEdit(),
            tooltip: 'Nuevo producto',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _qCtrl,
              decoration: InputDecoration(
                labelText: 'Buscar por SKU o nombre',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: (_qCtrl.text.isEmpty)
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _qCtrl.clear();
                          _load(q: '', category: _catFilter);
                        },
                      ),
              ),
            ),
          ),
          // Filtro por categoría
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _catFilter, // null = todas
                    decoration: const InputDecoration(
                      labelText: 'Filtrar por categoría',
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Todas'),
                      ),
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('(Sin categoría)'),
                      ),
                      ..._categories.map((c) => DropdownMenuItem<String>(
                            value: c,
                            child: Text(c),
                          )),
                    ],
                    onChanged: (v) {
                      setState(() => _catFilter = v);
                      _load(q: _qCtrl.text.trim(), category: v);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Actualizar categorías',
                  onPressed: () async {
                    await _loadCategories();
                    _snack('Categorías actualizadas');
                  },
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Expanded(
            child: _rows.isEmpty
                ? const Center(child: Text('Sin productos'))
                : ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 0),
                    itemBuilder: (ctx, i) {
                      final r = _rows[i];
                      final sale = (r['default_sale_price'] as num?)?.toDouble() ?? 0;
                      final last = (r['last_purchase_price'] as num?)?.toDouble() ?? 0;
                      final stock = (r['stock'] as num?)?.toInt() ?? 0;

                      return ListTile(
                        title: Text('${r['name']}'),
                        subtitle: Text(
                          'SKU: ${r['sku']}  ·  Cat: ${r['category'] ?? '-'}\n'
                          'PV: ${_money.format(sale)}  ·  Últ. costo: ${_money.format(last)}  ·  Stock: $stock',
                        ),
                        isThreeLine: true,
                        onTap: () => _openEdit(product: r),
                        trailing: IconButton(
                          tooltip: 'Eliminar',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(r),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Agregar'),
      ),
    );
  }
}