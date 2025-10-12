import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart' as appdb;

/// Página de Compras:
/// - Selector de proveedor (lista + botón "nuevo").
/// - Folio y fecha.
/// - Búsqueda de producto por SKU o nombre (live search).
/// - Captura de cantidad y costo unitario.
/// - Carrito de compra, total.
/// - Guarda la compra: purchase + purchase_items, actualiza stock y last_purchase_price.
/// - Confirmación con desglose.
class PurchasesPage extends StatefulWidget {
  const PurchasesPage({Key? key}) : super(key: key);

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _folioCtrl = TextEditingController();
  DateTime _date = DateTime.now();

  String? _supplierPhone;
  List<Map<String, dynamic>> _suppliers = [];

  // Búsqueda de productos
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _productResults = [];
  Map<String, dynamic>? _selectedProduct;

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
  }

  @override
  void dispose() {
    _folioCtrl.dispose();
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    final db = await appdb.getDb();
    final rows = await db.query('suppliers', orderBy: 'name COLLATE NOCASE');
    setState(() {
      _suppliers = rows;
      if (_suppliers.isNotEmpty && _supplierPhone == null) {
        _supplierPhone = _suppliers.first['phone'] as String?;
      }
    });
  }

  Future<void> _searchProducts(String q) async {
    q = q.trim();
    if (q.isEmpty) {
      setState(() {
        _productResults = [];
      });
      return;
    }
    final db = await appdb.getDb();
    final rows = await db.rawQuery(
      '''
      SELECT id, sku, name, category, default_sale_price, last_purchase_price, stock
      FROM products
      WHERE sku LIKE ? OR name LIKE ?
      ORDER BY name COLLATE NOCASE
      LIMIT 20
      ''',
      ['%$q%', '%$q%'],
    );
    setState(() {
      _productResults = rows;
    });
  }

  void _pickProduct(Map<String, dynamic> p) {
    setState(() {
      _selectedProduct = p;
      // Por defecto sugerimos el último costo de compra como costo unitario
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
    final sku = (p['sku'] ?? '').toString();
    final id = p['id'] as int;
    final name = (p['name'] ?? '').toString();

    // Si ya existe en carrito, solo acumula
    final idx = _cart.indexWhere((e) => e.productId == id);
    setState(() {
      if (idx >= 0) {
        final prev = _cart[idx];
        _cart[idx] = prev.copyWith(quantity: prev.quantity + qty, unitCost: cost);
      } else {
        _cart.add(_PurchaseItemRow(
          productId: id,
          sku: sku,
          name: name,
          quantity: qty,
          unitCost: cost,
        ));
      }
      // limpiar selección
      _selectedProduct = null;
      _searchCtrl.clear();
      _productResults = [];
      _qtyCtrl.text = '1';
      _costCtrl.text = '0';
    });
  }

  double get _cartTotal {
    return _cart.fold<double>(0.0, (sum, r) => sum + (r.quantity * r.unitCost));
  }

  Future<void> _save() async {
    if (_supplierPhone == null || _supplierPhone!.trim().isEmpty) {
      _snack('Selecciona un proveedor');
      return;
    }
    if (_cart.isEmpty) {
      _snack('Carrito vacío');
      return;
    }

    try {
      final db = await appdb.getDb();
      final folio = _folioCtrl.text.trim();
      final dateTxt = DateFormat('yyyy-MM-dd').format(_date);

      int purchaseId = 0;

      await db.transaction((txn) async {
        purchaseId = await txn.insert('purchases', {
          'folio': folio,
          'supplier_phone': _supplierPhone,
          'date': dateTxt,
        });

        for (final r in _cart) {
          await txn.insert('purchase_items', {
            'purchase_id': purchaseId,
            'product_id': r.productId,
            'quantity': r.quantity,
            'unit_cost': r.unitCost,
          });

          // Actualizar stock y último costo
          await txn.rawUpdate(
            'UPDATE products SET stock = COALESCE(stock,0) + ?, last_purchase_price = ? WHERE id = ?',
            [r.quantity, r.unitCost, r.productId],
          );
        }
      });

      await _showConfirmation(purchaseId, folio, dateTxt);

      setState(() {
        _cart.clear();
        _folioCtrl.clear();
        _selectedProduct = null;
        _searchCtrl.clear();
        _productResults = [];
      });
      _snack('Compra registrada');
    } catch (e) {
      _snack('Error al guardar: $e');
    }
  }

  Future<void> _showConfirmation(int purchaseId, String folio, String dateTxt) async {
    final total = _cartTotal;
    final lines = _cart
        .map((r) => '${r.sku} · ${r.name}\n  ${r.quantity} × ${_money.format(r.unitCost)} = ${_money.format(r.quantity * r.unitCost)}')
        .join('\n');

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Compra guardada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('Folio', folio.isEmpty ? '(sin folio)' : folio),
            _kv('Fecha', dateTxt),
            const SizedBox(height: 12),
            const Text('Productos:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(lines),
            const SizedBox(height: 12),
            _kv('Total', _money.format(total), bold: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar')),
        ],
      ),
    );
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
              decoration: const InputDecoration(labelText: 'Teléfono (ID) *'),
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
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Guardar')),
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
    await db.insert('suppliers', {
      'phone': phone,
      'name': name,
      'address': addr,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await _loadSuppliers();
    setState(() {
      _supplierPhone = phone;
    });
    _snack('Proveedor agregado');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _kv(String k, String v, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(k, style: style)),
          Text(v, style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _cartTotal;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compras'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Proveedor + botón nuevo
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _supplierPhone,
                  items: _suppliers
                      .map((s) => DropdownMenuItem<String>(
                            value: (s['phone'] ?? '').toString(),
                            child: Text(
                              '${(s['name'] ?? '').toString().isEmpty ? '(Sin nombre)' : s['name']} — ${s['phone']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _supplierPhone = v),
                  decoration: const InputDecoration(labelText: 'Proveedor'),
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
                    decoration: const InputDecoration(labelText: 'Fecha'),
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
            onChanged: _searchProducts,
          ),
          if (_productResults.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
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
                    subtitle: Text('SKU: ${p['sku']}  ·  Cat: ${p['category']}  ·  Últ. costo: ${_money.format((p['last_purchase_price'] as num?)?.toDouble() ?? 0)}'),
                    onTap: () => _pickProduct(p),
                  );
                },
              ),
            ),
          ],

          if (_selectedProduct != null) ...[
            const SizedBox(height: 12),
            Text('Producto seleccionado: ${_selectedProduct!['name']} (SKU: ${_selectedProduct!['sku']})'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Cantidad'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _costCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Costo unitario'),
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
              const Text('Renglones', style: TextStyle(fontWeight: FontWeight.bold)),
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
                        onDelete: () => setState(() => _cart.removeAt(e.key)),
                        money: _money,
                      ))
                  .toList(),
            ),

          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Text('Total: ${_money.format(total)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
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
    Key? key,
    required this.row,
    required this.onDelete,
    required this.money,
  }) : super(key: key);

  final _PurchaseItemRow row;
  final VoidCallback onDelete;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final subtotal = row.quantity * row.unitCost;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text('${row.name}'),
        subtitle: Text('SKU: ${row.sku} · Cant: ${row.quantity} × ${money.format(row.unitCost)}'),
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
  final int quantity;
  final double unitCost;

  _PurchaseItemRow({
    required this.productId,
    required this.sku,
    required this.name,
    required this.quantity,
    required this.unitCost,
  });

  _PurchaseItemRow copyWith({
    int? productId,
    String? sku,
    String? name,
    int? quantity,
    double? unitCost,
  }) {
    return _PurchaseItemRow(
      productId: productId ?? this.productId,
      sku: sku ?? this.sku,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unitCost: unitCost ?? this.unitCost,
    );
    }
}