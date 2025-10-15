import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:popperscuv5/data/database.dart' as appdb;
import 'package:popperscuv5/ui/purchases_history_page.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({Key? key}) : super(key: key);

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _folioCtrl = TextEditingController();
  DateTime _date = DateTime.now();

  // Proveedor
  int? _supplierId;
  List<Map<String, dynamic>> _suppliers = [];

  // Búsqueda de productos
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _productResults = [];
  Map<String, dynamic>? _selectedProduct;
  Timer? _debouncer;

  // Captura de renglón
  final _qtyCtrl = TextEditingController(text: '1');
  final _costCtrl = TextEditingController(text: '0');

  // Carrito
  final List<_PurchaseItemRow> _cart = [];

  final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
    _prepareAutoFolio();
  }

  @override
  void dispose() {
    _folioCtrl.dispose();
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    _debouncer?.cancel();
    super.dispose();
  }

  Future<void> _prepareAutoFolio() async {
    try {
      final db = await appdb.getDb();
      final r =
          await db.rawQuery('SELECT IFNULL(MAX(id),0)+1 AS n FROM purchases');
      final n = (r.first['n'] as int?) ?? 1;
      final d = DateTime.now();
      final folio =
          'C-${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}-${n.toString().padLeft(4, '0')}';
      if (mounted) _folioCtrl.text = folio;
    } catch (_) {
      // editable si falla
    }
  }

  Future<void> _loadSuppliers() async {
    final db = await appdb.getDb();
    final rows = await db.query('suppliers',
        orderBy: 'COALESCE(name,"") COLLATE NOCASE');
    if (!mounted) return;
    setState(() {
      _suppliers = rows;
      if (_suppliers.isNotEmpty && _supplierId == null) {
        _supplierId = _suppliers.first['id'] as int?;
      }
    });
  }

  void _searchProductsDebounced(String q) {
    _debouncer?.cancel();
    _debouncer = Timer(const Duration(milliseconds: 220), () {
      _searchProducts(q);
    });
  }

  Future<void> _searchProducts(String q) async {
    q = q.trim();
    if (q.isEmpty) {
      if (mounted) setState(() => _productResults = []);
      return;
    }
    final db = await appdb.getDb();
    final rows = await db.rawQuery(
      '''
      SELECT id, sku, name, category, last_purchase_price
      FROM products
      WHERE sku LIKE ? OR name LIKE ?
      ORDER BY name COLLATE NOCASE
      LIMIT 20
      ''',
      ['%$q%', '%$q%'],
    );
    if (mounted) setState(() => _productResults = rows);
  }

  void _pickProduct(Map<String, dynamic> p) {
    setState(() {
      _selectedProduct = p;
      final lastCost = (p['last_purchase_price'] as num?)?.toDouble() ?? 0.0;
      _costCtrl.text = lastCost > 0 ? lastCost.toStringAsFixed(2) : '0';
      _qtyCtrl.text = '1';
    });
  }

  void _addLine() {
    if (_selectedProduct == null) {
      _snack('Selecciona un producto');
      return;
    }
    final qty = int.tryParse(_qtyCtrl.text.trim());
    final cost = double.tryParse(_costCtrl.text.trim().replaceAll(',', '.'));
    if (qty == null || qty <= 0 || cost == null || cost < 0) {
      _snack('Cantidad / costo inválidos');
      return;
    }

    final p = _selectedProduct!;
    final id = p['id'] as int;
    final sku = (p['sku'] ?? '').toString();
    final name = (p['name'] ?? '').toString();
    final category = (p['category'] ?? '').toString();

    final idx = _cart.indexWhere((e) => e.productId == id);
    setState(() {
      if (idx >= 0) {
        final prev = _cart[idx];
        _cart[idx] =
            prev.copyWith(quantity: prev.quantity + qty, unitCost: cost);
      } else {
        _cart.add(_PurchaseItemRow(
          productId: id,
          sku: sku,
          name: name,
          category: category,
          quantity: qty,
          unitCost: cost,
        ));
      }
      _selectedProduct = null;
      _searchCtrl.clear();
      _productResults = [];
      _qtyCtrl.text = '1';
      _costCtrl.text = '0';
    });
  }

  double get _cartTotal =>
      _cart.fold<double>(0.0, (s, r) => s + r.quantity * r.unitCost);
  int get _cartPieces => _cart.fold<int>(0, (s, r) => s + r.quantity);

  Future<void> _saveConfirmed() async {
    try {
      final db = await appdb.getDb();
      await db.transaction((txn) async {
        final pid = await txn.insert('purchases', {
          'folio': _folioCtrl.text.trim().isEmpty ? null : _folioCtrl.text,
          'supplier_id': _supplierId,
          'date': DateFormat('yyyy-MM-dd').format(_date),
        });

        for (final r in _cart) {
          await txn.insert('purchase_items', {
            'purchase_id': pid,
            'product_id': r.productId,
            'quantity': r.quantity,
            'unit_cost': r.unitCost,
          });

          final cur = await txn.query('products',
              columns: ['stock'],
              where: 'id=?',
              whereArgs: [r.productId],
              limit: 1);
          final stock = (cur.first['stock'] as int?) ?? 0;

          await txn.update(
            'products',
            {
              'stock': stock + r.quantity,
              'last_purchase_price': r.unitCost,
              'last_purchase_date': DateTime.now().toIso8601String(),
            },
            where: 'id=?',
            whereArgs: [r.productId],
          );
        }
      });

      if (!mounted) return;
      setState(() {
        _cart.clear();
        _folioCtrl.clear();
        _selectedProduct = null;
        _searchCtrl.clear();
        _productResults = [];
      });
      _snack('Compra registrada');
      _prepareAutoFolio();
    } catch (e) {
      _snack('Error al guardar: $e');
    }
  }

  Future<void> _confirmAndSave() async {
    if (_supplierId == null) {
      _snack('Selecciona un proveedor');
      return;
    }
    if (_cart.isEmpty) {
      _snack('Carrito vacío');
      return;
    }

    // Agrupar por categoría
    final Map<String, _Agg> byCat = {};
    for (final r in _cart) {
      byCat.putIfAbsent(r.category, () => _Agg());
      byCat[r.category]!.pieces += r.quantity;
      byCat[r.category]!.amount += r.quantity * r.unitCost;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar compra'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('Por categoría',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
            const SizedBox(height: 8),
            ...byCat.entries.map((e) => Row(
                  children: [
                    Expanded(
                        child: Text(
                            e.key.isEmpty ? 'Sin categoría' : e.key)),
                    Text(
                        '${e.value.pieces} pzs · ${_money.format(e.value.amount)}'),
                  ],
                )),
            const Divider(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Totales: ${_cartPieces} pzs · ${_money.format(_cartTotal)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar y guardar')),
        ],
      ),
    );

    if (confirmed == true) {
      await _saveConfirmed();
    }
  }

  Future<void> _quickAddSupplierDialog() async {
    final phoneCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final addrCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nuevo proveedor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration:
                  const InputDecoration(labelText: 'Teléfono (ID) *'),
            ),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            TextField(
              controller: addrCtrl,
              decoration: const InputDecoration(labelText: 'Dirección'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Guardar')),
        ],
      ),
    );

    if (ok != true) return;

    final phone = phoneCtrl.text.trim();
    final name = nameCtrl.text.trim();
    final addr = addrCtrl.text.trim();
    if (phone.isEmpty) {
      _snack('El teléfono es obligatorio');
      return;
    }

    final db = await appdb.getDb();
    final id = await db.insert(
      'suppliers',
      {'phone': phone, 'name': name, 'address': addr},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _loadSuppliers();
    if (!mounted) return;
    setState(() => _supplierId = id);
    _snack('Proveedor agregado');
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final total = _cartTotal;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compras'),
        actions: [
          IconButton(
            tooltip: 'Historial',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const PurchasesHistoryPage()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Proveedor + botón nuevo
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _supplierId,
                  items: _suppliers
                      .map((s) => DropdownMenuItem<int>(
                            value: s['id'] as int,
                            child: Text(
                              '${(s['name'] ?? '').toString().isEmpty ? '(Sin nombre)' : s['name']} — ${s['phone']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _supplierId = v),
                  decoration:
                      const InputDecoration(labelText: 'Proveedor'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _quickAddSupplierDialog,
                icon: const Icon(Icons.add_business),
                tooltip: 'Nuevo proveedor',
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Folio + Fecha
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _folioCtrl,
                  decoration: const InputDecoration(labelText: 'Folio'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                  child: InputDecorator(
                    decoration:
                        const InputDecoration(labelText: 'Fecha'),
                    child: Text(DateFormat('yyyy-MM-dd').format(_date)),
                  ),
                ),
              ),
            ],
          ),

          const Divider(height: 32),

          // Búsqueda de productos
          TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              labelText: 'Buscar producto (SKU o nombre)',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: _searchProductsDebounced,
          ),
          if (_productResults.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(
                border:
                    Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _productResults.length,
                itemBuilder: (_, i) {
                  final p = _productResults[i];
                  return ListTile(
                    dense: true,
                    title: Text('${p['name']}'),
                    subtitle: Text(
                        'SKU: ${p['sku']}  ·  Cat: ${p['category'] ?? ''}  ·  Últ. costo: ${_money.format((p['last_purchase_price'] as num?)?.toDouble() ?? 0)}'),
                    onTap: () => _pickProduct(p),
                  );
                },
              ),
            ),
          ],

          if (_selectedProduct != null) ...[
            const SizedBox(height: 12),
            Text(
                'Seleccionado: ${_selectedProduct!['name']} (SKU: ${_selectedProduct!['sku']})'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Cantidad'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _costCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Costo unitario'),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _addLine,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar'),
                ),
              ],
            ),
          ],

          const Divider(height: 32),

          // Carrito
          Row(
            children: [
              const Text('Renglones',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_cart.isNotEmpty)
                TextButton.icon(
                  onPressed: () => setState(() => _cart.clear()),
                  icon: const Icon(Icons.delete_sweep),
                  label: const Text('Vaciar'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_cart.isEmpty)
            const Text('Sin productos en la compra')
          else
            Column(
              children: _cart
                  .asMap()
                  .entries
                  .map((e) => _CartTile(
                        row: e.value,
                        onDelete: () =>
                            setState(() => _cart.removeAt(e.key)),
                        money: _money,
                      ))
                  .toList(),
            ),

          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Text('Total: ${_money.format(total)}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
          ),

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _confirmAndSave,
            icon: const Icon(Icons.save),
            label: const Text('Guardar compra'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _CartTile extends StatelessWidget {
  const _CartTile({
    super.key,
    required this.row,
    required this.onDelete,
    required this.money,
  });

  final _PurchaseItemRow row;
  final VoidCallback onDelete;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final subtotal = row.quantity * row.unitCost;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(row.name),
        subtitle: Text(
            'SKU: ${row.sku} · Cat: ${row.category.isEmpty ? "—" : row.category} · ${row.quantity} × ${money.format(row.unitCost)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(money.format(subtotal)),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.close),
              tooltip: 'Quitar',
            ),
          ],
        ),
      ),
    );
  }
}

class _PurchaseItemRow {
  final int productId;
  final String sku;
  final String name;
  final String category;
  final int quantity;
  final double unitCost;

  _PurchaseItemRow({
    required this.productId,
    required this.sku,
    required this.name,
    required this.category,
    required this.quantity,
    required this.unitCost,
  });

  _PurchaseItemRow copyWith({
    int? productId,
    String? sku,
    String? name,
    String? category,
    int? quantity,
    double? unitCost,
  }) {
    return _PurchaseItemRow(
      productId: productId ?? this.productId,
      sku: sku ?? this.sku,
      name: name ?? this.name,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      unitCost: unitCost ?? this.unitCost,
    );
  }
}

class _Agg {
  int pieces = 0;
  double amount = 0;
}