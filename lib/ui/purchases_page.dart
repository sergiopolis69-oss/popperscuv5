import 'dart:async';
import 'package:flutter/material.dart';
import 'package:popperscuv5/data/database.dart' as appdb;
import 'package:sqflite/sqflite.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});
  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _folioCtrl = TextEditingController();
  final _supplierPhoneCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();

  // línea actual
  final _skuCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _costCtrl = TextEditingController(text: '0');

  // live search
  final _focusSku = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlay;
  Timer? _debounce;
  List<Map<String, Object?>> _suggestions = [];
  int _highlightIndex = -1;

  final List<_PurchaseLine> _lines = [];

  @override
  void initState() {
    super.initState();
    _focusSku.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusSku.removeListener(_onFocusChange);
    _debounce?.cancel();
    _overlay?.remove();
    _folioCtrl.dispose();
    _supplierPhoneCtrl.dispose();
    _dateCtrl.dispose();
    _skuCtrl.dispose();
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    _focusSku.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusSku.hasFocus) {
      _hideOverlay();
    } else {
      _triggerSearch(_skuCtrl.text);
    }
  }

  void _hideOverlay() {
    _overlay?.remove();
    _overlay = null;
    _highlightIndex = -1;
  }

  void _triggerSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      if (!_focusSku.hasFocus) return;
      final db = await appdb.getDb();
      final res = await db.query(
        'products',
        columns: ['id', 'sku', 'name', 'last_purchase_price'],
        where: 'sku LIKE ? OR name LIKE ?',
        whereArgs: ['%$q%', '%$q%'],
        limit: 20,
      );
      _suggestions = res;
      _showOverlay();
    });
  }

  void _showOverlay() {
    _overlay?.remove();
    final overlay = Overlay.of(context);
    final render = _skuKey.currentContext?.findRenderObject() as RenderBox?;
    final size = render?.size ?? const Size(300, 44);

    _overlay = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _suggestions.length,
                itemBuilder: (ctx, i) {
                  final it = _suggestions[i];
                  final sku = (it['sku'] ?? '').toString();
                  final name = (it['name'] ?? '').toString();
                  final selected = i == _highlightIndex;
                  return InkWell(
                    onTap: () => _selectSuggestion(it),
                    child: Container(
                      color: selected ? Theme.of(context).hoverColor : null,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                              child: Text('$sku – $name',
                                  overflow: TextOverflow.ellipsis)),
                          Text('\$${(it['last_purchase_price'] ?? 0)}'),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_overlay!);
  }

  void _selectSuggestion(Map<String, Object?> it) {
    _skuCtrl.text = (it['sku'] ?? '').toString();
    final price = (it['last_purchase_price'] as num?)?.toDouble() ?? 0;
    _costCtrl.text = price.toStringAsFixed(2);
    _qtyCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _qtyCtrl.text.length);
    _hideOverlay();
  }

  final GlobalKey _skuKey = GlobalKey();

  Future<void> _addLine() async {
    final sku = _skuCtrl.text.trim();
    if (sku.isEmpty) return;
    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
    final cost = double.tryParse(_costCtrl.text) ?? 0;

    final db = await appdb.getDb();
    final prod = await db.query('products',
        where: 'sku = ?', whereArgs: [sku], limit: 1);
    if (prod.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SKU no encontrado')),
      );
      return;
    }
    final pid = prod.first['id'] as int;

    setState(() {
      _lines.add(_PurchaseLine(productId: pid, sku: sku, qty: qty, unitCost: cost));
      _skuCtrl.clear();
      _qtyCtrl.text = '1';
      _costCtrl.text = '0';
    });
  }

  double get _total => _lines.fold(0, (s, l) => s + l.qty * l.unitCost);

  Future<void> _save() async {
    final db = await appdb.getDb();
    await db.transaction((txn) async {
      final id = await txn.insert('purchases', {
        'folio': _folioCtrl.text.trim().isEmpty ? null : _folioCtrl.text.trim(),
        'supplier_id': await _ensureSupplier(txn, _supplierPhoneCtrl.text.trim()),
        'date': _dateCtrl.text.trim().isEmpty
            ? DateTime.now().toIso8601String()
            : _dateCtrl.text.trim(),
      });
      for (final l in _lines) {
        await txn.insert('purchase_items', {
          'purchase_id': id,
          'product_id': l.productId,
          'quantity': l.qty,
          'unit_cost': l.unitCost,
        });
        // actualiza last_purchase_price y stock
        await txn.update('products', {
          'last_purchase_price': l.unitCost,
          'last_purchase_date': DateTime.now().toIso8601String(),
          'stock': (await _getStock(txn, l.productId)) + l.qty,
        }, where: 'id=?', whereArgs: [l.productId]);
      }
    });

    setState(() {
      _lines.clear();
      _folioCtrl.clear();
      _supplierPhoneCtrl.clear();
      _dateCtrl.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Compra guardada')),
    );
  }

  Future<int?> _ensureSupplier(Transaction txn, String phone) async {
    if (phone.isEmpty) return null;
    final r = await txn.query('suppliers', where: 'phone=?', whereArgs: [phone], limit: 1);
    if (r.isNotEmpty) return r.first['id'] as int;
    return txn.insert('suppliers', {'phone': phone});
  }

  Future<int> _getStock(Transaction txn, int productId) async {
    final r = await txn.query('products', columns: ['stock'], where: 'id=?', whereArgs: [productId], limit: 1);
    return (r.first['stock'] as int?) ?? 0;
    }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compras')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _folioCtrl, decoration: const InputDecoration(labelText: 'Folio')),
          TextField(controller: _supplierPhoneCtrl, decoration: const InputDecoration(labelText: 'Teléfono proveedor')),
          TextField(controller: _dateCtrl, decoration: const InputDecoration(labelText: 'Fecha (ISO opcional)')),

          const SizedBox(height: 16),
          // === Autocomplete de productos ===
          CompositedTransformTarget(
            link: _layerLink,
            child: TextField(
              key: _skuKey,
              controller: _skuCtrl,
              focusNode: _focusSku,
              decoration: const InputDecoration(
                labelText: 'SKU o nombre (buscar)',
                hintText: 'Escribe para buscar…',
              ),
              onChanged: _triggerSearch,
              onEditingComplete: _addLine,
              onSubmitted: (_) => _addLine(),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Cantidad'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _costCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Costo unitario'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _addLine, child: const Text('Agregar')),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(),
          const Text('Detalle', style: TextStyle(fontWeight: FontWeight.bold)),
          ..._lines.map((l) => ListTile(
                title: Text(l.sku),
                subtitle: Text('Cant: ${l.qty}  ·  Costo: ${l.unitCost.toStringAsFixed(2)}'),
                trailing: Text('\$${(l.qty * l.unitCost).toStringAsFixed(2)}'),
              )),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text('Total: \$${_total.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _save, child: const Text('Guardar compra')),
        ],
      ),
    );
  }
}

class _PurchaseLine {
  final int productId;
  final String sku;
  final int qty;
  final double unitCost;
  _PurchaseLine({
    required this.productId,
    required this.sku,
    required this.qty,
    required this.unitCost,
  });
}