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
  final GlobalKey _skuKey = GlobalKey();

  // historial del producto actual
  List<_PurchaseHistoryRow> _history = [];

  final List<_PurchaseLine> _lines = [];

  @override
  void initState() {
    super.initState();
    _focusSku.addListener(_onFocusChange);
    _prepareAutoFolio();
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

  Future<void> _prepareAutoFolio() async {
    try {
      final db = await appdb.getDb();
      final r = await db.rawQuery('SELECT IFNULL(MAX(id),0)+1 AS next FROM purchases');
      final next = (r.first['next'] as int?) ?? 1;
      final now = DateTime.now();
      final folio = 'C-${now.year.toString().padLeft(4, "0")}'
          '${now.month.toString().padLeft(2, "0")}'
          '${now.day.toString().padLeft(2, "0")}-'
          '${next.toString().padLeft(4, "0")}';
      if (mounted) _folioCtrl.text = folio;
    } catch (_) {
      // si algo pasa, deja folio vacío editable
    }
  }

  // ===== Live search =====
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
        columns: ['id', 'sku', 'name', 'category', 'last_purchase_price'],
        where: 'sku LIKE ? OR name LIKE ?',
        whereArgs: ['%$q%', '%$q%'],
        orderBy: 'name ASC',
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
              constraints: const BoxConstraints(maxHeight: 260),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$name  ($sku)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
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

  Future<void> _loadHistoryForProduct(int productId) async {
    final db = await appdb.getDb();
    final r = await db.rawQuery('''
      SELECT p.date as date, pi.unit_cost as cost
      FROM purchase_items pi
      JOIN purchases p ON p.id = pi.purchase_id
      WHERE pi.product_id = ?
      ORDER BY p.date DESC
      LIMIT 10
    ''', [productId]);
    _history = r
        .map((e) => _PurchaseHistoryRow(
              dateIso: (e['date'] ?? '').toString(),
              unitCost: (e['cost'] as num?)?.toDouble() ?? 0,
            ))
        .toList();
    if (mounted) setState(() {});
  }

  void _selectSuggestion(Map<String, Object?> it) async {
    _skuCtrl.text = (it['sku'] ?? '').toString();
    final price = (it['last_purchase_price'] as num?)?.toDouble() ?? 0;
    _costCtrl.text = price.toStringAsFixed(2);
    _qtyCtrl.selection =
        TextSelection(baseOffset: 0, extentOffset: _qtyCtrl.text.length);
    _hideOverlay();

    final pid = it['id'] as int;
    await _loadHistoryForProduct(pid);
  }

  // ===== Lógica de líneas =====
  Future<void> _addLine() async {
    final sku = _skuCtrl.text.trim();
    if (sku.isEmpty) return;
    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
    final cost = double.tryParse(_costCtrl.text) ?? 0;

    final db = await appdb.getDb();
    final prod = await db.query('products',
        columns: ['id', 'sku', 'name', 'category'],
        where: 'sku = ?',
        whereArgs: [sku],
        limit: 1);
    if (prod.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SKU no encontrado')),
      );
      return;
    }
    final row = prod.first;
    final pid = row['id'] as int;
    final name = (row['name'] ?? '').toString();
    final category = (row['category'] ?? '').toString();

    setState(() {
      _lines.add(_PurchaseLine(
        productId: pid,
        sku: sku,
        name: name,
        category: category,
        qty: qty,
        unitCost: cost,
      ));
      _skuCtrl.clear();
      _qtyCtrl.text = '1';
      _costCtrl.text = '0';
      _history = [];
    });
  }

  double get _total => _lines.fold(0, (s, l) => s + l.qty * l.unitCost);
  int get _totalPieces => _lines.fold(0, (s, l) => s + l.qty);

  // ===== Guardado con confirmación =====
  Future<void> _saveWithConfirm() async {
    if (_lines.isEmpty) return;

    // agrupar por categoría
    final Map<String, _CatAgg> byCat = {};
    for (final l in _lines) {
      byCat.putIfAbsent(l.category, () => _CatAgg());
      byCat[l.category]!.pieces += l.qty;
      byCat[l.category]!.amount += l.qty * l.unitCost;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Confirmar compra'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Por categoría',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              const SizedBox(height: 8),
              ...byCat.entries.map((e) => Row(
                    children: [
                      Expanded(child: Text(e.key.isEmpty ? 'Sin categoría' : e.key)),
                      Text('${e.value.pieces} pzs  ·  \$${e.value.amount.toStringAsFixed(2)}'),
                    ],
                  )),
              const Divider(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Totales de esta compra: ${_totalPieces} pzs  ·  \$${_total.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar y guardar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await _save(); // guarda definitivamente
  }

  Future<void> _save() async {
    final db = await appdb.getDb();
    await db.transaction((txn) async {
      final id = await txn.insert('purchases', {
        'folio': _folioCtrl.text.trim().isEmpty ? null : _folioCtrl.text.trim(),
        'supplier_id':
            await _ensureSupplier(txn, _supplierPhoneCtrl.text.trim()),
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
        final cur = await txn.query('products',
            columns: ['stock'], where: 'id=?', whereArgs: [l.productId], limit: 1);
        final curStock = (cur.first['stock'] as int?) ?? 0;
        await txn.update('products', {
          'last_purchase_price': l.unitCost,
          'last_purchase_date': DateTime.now().toIso8601String(),
          'stock': curStock + l.qty,
        }, where: 'id=?', whereArgs: [l.productId]);
      }
    });

    setState(() {
      _lines.clear();
      _folioCtrl.clear();
      _supplierPhoneCtrl.clear();
      _dateCtrl.clear();
      _history = [];
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compra guardada')),
      );
    }
    // prepara siguiente folio
    _prepareAutoFolio();
  }

  Future<int?> _ensureSupplier(Transaction txn, String phone) async {
    if (phone.isEmpty) return null;
    final r = await txn.query('suppliers',
        where: 'phone=?', whereArgs: [phone], limit: 1);
    if (r.isNotEmpty) return r.first['id'] as int;
    return txn.insert('suppliers', {'phone': phone});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compras')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _folioCtrl,
            decoration: const InputDecoration(labelText: 'Folio (auto)'),
          ),
          TextField(
            controller: _supplierPhoneCtrl,
            decoration:
                const InputDecoration(labelText: 'Teléfono proveedor (opcional)'),
          ),
          TextField(
            controller: _dateCtrl,
            decoration:
                const InputDecoration(labelText: 'Fecha ISO (opcional)'),
          ),
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
                  decoration:
                      const InputDecoration(labelText: 'Costo unitario'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _addLine, child: const Text('Agregar')),
            ],
          ),

          // Historial del producto seleccionado
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Historial (últimas 10 compras)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            ..._history.map((h) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      'Fecha: ${h.dateIso}   ·   Precio: \$${h.unitCost.toStringAsFixed(2)}'),
                )),
          ],

          const SizedBox(height: 12),
          const Divider(),
          const Text('Detalle',
              style: TextStyle(fontWeight: FontWeight.bold)),
          ..._lines.map((l) => ListTile(
                title: Text('${l.name}  (${l.sku})'),
                subtitle: Text(
                    'Cat: ${l.category.isEmpty ? "—" : l.category}  ·  Cant: ${l.qty}  ·  Costo: ${l.unitCost.toStringAsFixed(2)}'),
                trailing: Text(
                    '\$${(l.qty * l.unitCost).toStringAsFixed(2)}'),
              )),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Total: \$${_total.toStringAsFixed(2)}  (${_totalPieces} pzs)',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: _saveWithConfirm,
              child: const Text('Guardar compra')),
        ],
      ),
    );
  }
}

class _PurchaseLine {
  final int productId;
  final String sku;
  final String name;
  final String category;
  final int qty;
  final double unitCost;
  _PurchaseLine({
    required this.productId,
    required this.sku,
    required this.name,
    required this.category,
    required this.qty,
    required this.unitCost,
  });
}

class _PurchaseHistoryRow {
  final String dateIso;
  final double unitCost;
  _PurchaseHistoryRow({required this.dateIso, required this.unitCost});
}

class _CatAgg {
  int pieces = 0;
  double amount = 0;
}