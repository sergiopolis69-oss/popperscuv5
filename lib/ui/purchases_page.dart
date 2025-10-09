import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';
import '../repositories/product_repository.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});
  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _folioCtrl = TextEditingController();
  final _supplierSearchCtrl = TextEditingController();
  final _productSearchCtrl = TextEditingController();

  List<Map<String, dynamic>> _supplierResults = [];
  List<Map<String, dynamic>> _productResults = [];
  int? _selectedSupplierId;

  final _repo = ProductRepository();
  final List<Map<String, dynamic>> _items = [];

  Timer? _debSup;
  Timer? _debProd;

  @override
  void dispose() {
    _folioCtrl.dispose();
    _supplierSearchCtrl.dispose();
    _productSearchCtrl.dispose();
    _debSup?.cancel(); _debProd?.cancel();
    super.dispose();
  }

  void _onSupplierChanged(String q) {
    _debSup?.cancel();
    _debSup = Timer(const Duration(milliseconds: 250), () async {
      final db = await DatabaseHelper.instance.db;
      final like = '%${q.trim()}%';
      final rows = await db.query(
        'suppliers',
        where: 'name LIKE ? OR phone LIKE ?',
        whereArgs: [like, like],
        orderBy: 'name COLLATE NOCASE ASC',
        limit: 20,
      );
      setState(()=> _supplierResults = rows);
    });
  }

  void _onProductChanged(String q) {
    _debProd?.cancel();
    _debProd = Timer(const Duration(milliseconds: 250), () async {
      if (q.trim().isEmpty) { setState(()=>_productResults=[]); return; }
      final r = await _repo.searchLite(q, limit: 25);
      setState(()=> _productResults = r);
    });
  }

  Future<void> _addQuickSupplier() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final addr = TextEditingController();
    await showDialog(context: context, builder: (ctx){
      return AlertDialog(
        title: const Text('Nuevo proveedor'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre')),
          TextField(controller: phone, decoration: const InputDecoration(labelText: 'Teléfono (ID)*'), keyboardType: TextInputType.phone),
          TextField(controller: addr, decoration: const InputDecoration(labelText: 'Dirección')),
        ]),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () async {
            final tel = phone.text.trim();
            if (tel.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El teléfono (ID) es obligatorio')));
              return;
            }
            final db = await DatabaseHelper.instance.db;
            final id = await db.insert('suppliers', {
              'name': name.text.trim(),
              'phone': tel,
              'address': addr.text.trim(),
            }, conflictAlgorithm: ConflictAlgorithm.replace);
            setState(() {
              _selectedSupplierId = id;
              _supplierSearchCtrl.text = name.text.trim().isEmpty ? tel : name.text.trim();
              _supplierResults.clear();
            });
            if (context.mounted) Navigator.pop(ctx);
          }, child: const Text('Guardar')),
        ],
      );
    });
  }

  Future<void> _promptAddProduct(Map<String, dynamic> p) async {
    final qty = TextEditingController(text: '1');
    final cost = TextEditingController(text: '0');
    await showDialog(context: context, builder: (ctx){
      return AlertDialog(
        title: Text(p['name'] ?? ''),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad')),
          const SizedBox(height: 8),
          TextField(controller: cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Costo unitario')),
        ]),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: (){
            final q = int.tryParse(qty.text) ?? 0;
            final c = double.tryParse(cost.text.replaceAll(',', '.')) ?? 0;
            if (q>0 && c>0) {
              setState(()=> _items.add({
                'product_id': p['id'],
                'name': p['name'],
                'quantity': q,
                'unit_cost': c,
              }));
            }
            Navigator.pop(ctx);
          }, child: const Text('Agregar')),
        ],
      );
    });
  }

  double get _totalPzas => _items.fold(0.0, (a,it)=> a + (it['quantity'] as int));
  double get _totalMonto => _items.fold(0.0, (a,it)=> a + (it['quantity'] as int) * (it['unit_cost'] as double));

  Future<void> _savePurchase() async {
    final folio = _folioCtrl.text.trim();
    if (folio.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Folio obligatorio')));
      return;
    }
    if (_selectedSupplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona o agrega proveedor')));
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Agrega al menos un producto')));
      return;
    }

    final db = await DatabaseHelper.instance.db;
    final batch = db.batch();

    final purchaseId = await db.insert('purchases', {
      'folio': folio,
      'supplier_id': _selectedSupplierId,
      'date': DateTime.now().toIso8601String(),
    });

    for (final it in _items) {
      batch.insert('purchase_items', {
        'purchase_id': purchaseId,
        'product_id': it['product_id'],
        'quantity': it['quantity'],
        'unit_cost': it['unit_cost'],
      });
      batch.rawUpdate('UPDATE products SET stock = stock + ?, last_purchase_price = ?, last_purchase_date = ? WHERE id = ?',
        [it['quantity'], it['unit_cost'], DateTime.now().toIso8601String(), it['product_id']]);
    }

    await batch.commit(noResult: true);
    setState(() {
      _items.clear();
      _productSearchCtrl.clear();
      _productResults.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Compra registrada')));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Folio de compra'),
        const SizedBox(height: 4),
        TextField(controller: _folioCtrl, decoration: const InputDecoration(hintText: 'Escribe el folio…')),

        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Proveedor (buscar por nombre o teléfono)'),
              const SizedBox(height: 4),
              TextField(
                controller: _supplierSearchCtrl,
                decoration: InputDecoration(
                  hintText: 'Ej. Logística MX / 5512345678',
                  suffixIcon: IconButton(icon: const Icon(Icons.person_add), onPressed: _addQuickSupplier),
                ),
                onChanged: (q) { _selectedSupplierId = null; _onSupplierChanged(q); },
              ),
              if (_supplierResults.isNotEmpty)
                Card(
                  margin: const EdgeInsets.only(top:6),
                  child: Column(
                    children: _supplierResults.map((s)=> ListTile(
                      dense: true,
                      title: Text(s['name'] ?? s['phone'] ?? ''),
                      subtitle: Text('Tel: ${s['phone'] ?? ''}'),
                      onTap: (){
                        setState(() {
                          _selectedSupplierId = s['id'] as int?;
                          _supplierSearchCtrl.text = (s['name'] as String?)?.isEmpty == true ? (s['phone'] ?? '') : (s['name'] ?? '');
                          _supplierResults.clear();
                        });
                      },
                    )).toList(),
                  ),
                ),
            ])),
          ],
        ),

        const SizedBox(height: 16),
        const Text('Producto (buscar por nombre / SKU)'),
        const SizedBox(height: 4),
        TextField(
          controller: _productSearchCtrl,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Escribe para buscar…'),
          onChanged: _onProductChanged,
        ),
        if (_productResults.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top:6),
            child: Column(
              children: _productResults.map((p)=> ListTile(
                dense: true,
                title: Text(p['name'] ?? ''),
                subtitle: Text('SKU: ${p['sku'] ?? '—'}'),
                trailing: const Icon(Icons.add),
                onTap: ()=> _promptAddProduct(p),
              )).toList(),
            ),
          ),

        const SizedBox(height: 12),

        Card(
          child: Column(
            children: [
              const ListTile(title: Text('Productos de la compra')),
              ..._items.map((it)=> ListTile(
                title: Text(it['name'] ?? ''),
                subtitle: Text('x${it['quantity']}  •  \$${it['unit_cost']}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: ()=> setState(()=> _items.remove(it)),
                ),
              )),
              if (_items.isEmpty) const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Sin productos'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(title: const Text('Total piezas'), trailing: Text('${_totalPzas.toStringAsFixed(0)}')),
              ListTile(title: const Text('Total monetario'), trailing: Text('\$${_totalMonto.toStringAsFixed(2)}')),
            ],
          ),
        ),

        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _savePurchase, icon: const Icon(Icons.check), label: const Text('Registrar compra')),
      ],
    );
  }
}
