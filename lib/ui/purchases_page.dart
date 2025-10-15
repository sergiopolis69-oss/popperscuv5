import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:popperscuv5/data/database.dart' as appdb;

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});
  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _folioCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _costCtrl = TextEditingController(text: '0');

  List<Map<String, Object?>> _items = [];
  List<Map<String, Object?>> _skuMatches = [];
  bool _loadingSku = false;

  Future<void> _searchSku(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _skuMatches = []);
      return;
    }
    setState(() => _loadingSku = true);
    final db = await appdb.DatabaseHelper.instance.db;
    final rows = await db.query(
      'products',
      columns: ['id','sku','name','stock'],
      where: 'sku LIKE ? OR name LIKE ?',
      whereArgs: ['%$q%','%$q%'],
      orderBy: 'sku LIMIT 10',
    );
    setState(() {
      _skuMatches = rows;
      _loadingSku = false;
    });
  }

  Future<void> _addItemFromSku(Map<String, Object?> p) async {
    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
    final cost = double.tryParse(_costCtrl.text) ?? 0.0;
    if (qty <= 0) return;
    _items.add({
      'product_id': p['id'],
      'sku': p['sku'],
      'name': p['name'],
      'quantity': qty,
      'unit_cost': cost,
    });
    setState(() {
      _skuCtrl.clear();
      _qtyCtrl.text = '1';
      _costCtrl.text = '0';
      _skuMatches = [];
    });
  }

  Future<void> _save() async {
    try {
      final db = await appdb.DatabaseHelper.instance.db;
      final date = _dateCtrl.text.isEmpty
          ? DateTime.now().toIso8601String().substring(0, 10)
          : _dateCtrl.text;

      final supPhone = _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim();
      int? supplierId;
      if (supPhone != null) {
        final ex = await db.query('suppliers', where: 'phone=?', whereArgs: [supPhone], limit: 1);
        supplierId = ex.isEmpty ? await db.insert('suppliers', {'phone': supPhone}) : ex.first['id'] as int;
      }

      final pid = await db.insert('purchases', {
        'folio': _folioCtrl.text.trim(),
        'supplier_id': supplierId,
        'date': date,
      });

      for (final it in _items) {
        await db.insert('purchase_items', {
          'purchase_id': pid,
          'product_id': it['product_id'],
          'quantity': it['quantity'],
          'unit_cost': it['unit_cost'],
        });
        // actualizar last_purchase_price y stock
        await db.rawUpdate('UPDATE products SET last_purchase_price=?, stock=stock+? WHERE id=?',
            [it['unit_cost'], it['quantity'], it['product_id']]);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Compra guardada')));
        setState(() {
          _items = [];
          _folioCtrl.clear();
          _phoneCtrl.clear();
          _dateCtrl.clear();
          _skuCtrl.clear();
          _qtyCtrl.text = '1';
          _costCtrl.text = '0';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final skuBox = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _skuCtrl,
          decoration: const InputDecoration(labelText: 'SKU o nombre', border: OutlineInputBorder()),
          onChanged: _searchSku,
        ),
        const SizedBox(height: 6),
        if (_loadingSku) const LinearProgressIndicator(minHeight: 2),
        if (_skuMatches.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black26),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _skuMatches.length,
              itemBuilder: (_, i) {
                final r = _skuMatches[i];
                return ListTile(
                  dense: true,
                  title: Text('${r['sku']} • ${r['name']}'),
                  subtitle: Text('Stock: ${r['stock']}'),
                  onTap: () => _addItemFromSku(r),
                );
              },
            ),
          ),
      ],
    );

    final qtyCostRow = Row(
      children: [
        Expanded(
          child: TextField(
            controller: _qtyCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Cantidad', border: OutlineInputBorder()),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _costCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Costo unitario', border: OutlineInputBorder()),
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Compras')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _folioCtrl, decoration: const InputDecoration(labelText: 'Folio', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Teléfono proveedor (opcional)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _dateCtrl, decoration: const InputDecoration(labelText: 'Fecha (YYYY-MM-DD, opcional)', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          skuBox,
          const SizedBox(height: 10),
          qtyCostRow,
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () {
              if (_skuMatches.isNotEmpty) _addItemFromSku(_skuMatches.first);
            },
            icon: const Icon(Icons.add),
            label: const Text('Agregar producto seleccionado'),
          ),
          const SizedBox(height: 16),
          const Text('Detalle', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          ..._items.map((it) => ListTile(
                title: Text('${it['sku']} • ${it['name']}'),
                subtitle: Text('Cant: ${it['quantity']}  •  Costo: ${it['unit_cost']}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _items.remove(it)),
                ),
              )),
          const SizedBox(height: 16),
          ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Guardar compra')),
        ],
      ),
    );
  }
}