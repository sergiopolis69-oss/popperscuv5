import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:popperscuv5/data/database.dart' as appdb;

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});
  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _folioCtrl = TextEditingController();
  final _dateCtrl = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
  final _skuCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _costCtrl = TextEditingController(text: '0');

  String? _supplierPhone; // dropdown value (phone)
  List<Map<String, Object?>> _suppliers = [];
  final List<_Line> _lines = [];

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    final db = await appdb.DatabaseHelper.instance.db;
    final rows = await db.query('suppliers', orderBy: 'name COLLATE NOCASE');
    setState(() => _suppliers = rows);
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final sel = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (sel != null) {
      _dateCtrl.text = DateFormat('yyyy-MM-dd').format(sel);
    }
  }

  void _addLine() {
    final sku = _skuCtrl.text.trim();
    final q = int.tryParse(_qtyCtrl.text) ?? 0;
    final c = double.tryParse(_costCtrl.text.replaceAll(',', '.')) ?? 0;
    if (sku.isEmpty || q <= 0 || c < 0) {
      _snack('SKU / Cantidad / Costo inválidos');
      return;
    }
    setState(() {
      _lines.add(_Line(sku: sku, qty: q, cost: c));
      _skuCtrl.clear();
      _qtyCtrl.text = '1';
      _costCtrl.text = '0';
    });
  }

  Future<void> _quickAddSupplierDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addrCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nuevo proveedor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono')),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
            TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: 'Dirección')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;

    final phone = phoneCtrl.text.trim();
    if (phone.isEmpty) {
      _snack('El teléfono es obligatorio');
      return;
    }
    final db = await appdb.DatabaseHelper.instance.db;
    await db.insert(
      'suppliers',
      {
        'phone': phone,
        'name': nameCtrl.text.trim(),
        'address': addrCtrl.text.trim(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await _loadSuppliers();
    setState(() => _supplierPhone = phone);
  }

  Future<int?> _ensureSupplierByPhone(DatabaseExecutor txn, String phone) async {
    final existing = await txn.query('suppliers', where: 'phone=?', whereArgs: [phone], limit: 1);
    if (existing.isNotEmpty) return existing.first['id'] as int;
    final id = await txn.insert('suppliers', {'phone': phone});
    return id;
  }

  Future<int> _ensureProductBySku(DatabaseExecutor txn, String sku) async {
    final p = await txn.query('products', where: 'sku=?', whereArgs: [sku], limit: 1);
    if (p.isNotEmpty) return p.first['id'] as int;
    // producto mínimo si no existe
    final id = await txn.insert('products', {
      'sku': sku,
      'name': sku,
      'category': '',
      'default_sale_price': 0.0,
      'last_purchase_price': 0.0,
      'stock': 0,
    });
    return id;
  }

  Future<void> _savePurchase() async {
    if (_supplierPhone == null || _supplierPhone!.isEmpty) {
      _snack('Selecciona un proveedor'); return;
    }
    if (_lines.isEmpty) {
      _snack('Agrega al menos un producto'); return;
    }

    try {
      final db = await appdb.DatabaseHelper.instance.db;
      await db.transaction((txn) async {
        final supId = await _ensureSupplierByPhone(txn, _supplierPhone!);
        final pid = await txn.insert('purchases', {
          'folio': _folioCtrl.text.trim(),
          'supplier_id': supId,
          'date': _dateCtrl.text.trim(),
        });

        for (final ln in _lines) {
          final prodId = await _ensureProductBySku(txn, ln.sku);
          await txn.insert('purchase_items', {
            'purchase_id': pid,
            'product_id': prodId,
            'quantity': ln.qty,
            'unit_cost': ln.cost,
          });
          // actualiza costo y stock
          await txn.update('products', {
            'last_purchase_price': ln.cost,
            'last_purchase_date': _dateCtrl.text.trim(),
            'stock': (Sqflite.firstIntValue(await txn.rawQuery('SELECT stock FROM products WHERE id=?', [prodId])) ?? 0) + ln.qty,
          }, where: 'id=?', whereArgs: [prodId]);
        }
      });

      setState(() {
        _lines.clear();
        _folioCtrl.clear();
      });
      _snack('Compra guardada');
    } catch (e) {
      _snack('Error al guardar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _lines.fold<double>(0.0, (a, b) => a + b.cost * b.qty);
    return Scaffold(
      appBar: AppBar(title: const Text('Compras')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _supplierPhone,
                  items: [
                    for (final s in _suppliers)
                      DropdownMenuItem(
                        value: (s['phone'] ?? '').toString(),
                        child: Text('${s['name'] ?? ''} (${s['phone'] ?? ''})'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _supplierPhone = v),
                  decoration: const InputDecoration(labelText: 'Proveedor'),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(onPressed: _quickAddSupplierDialog, child: const Text('Nuevo')),
            ],
          ),
          const SizedBox(height: 12),
          TextField(controller: _folioCtrl, decoration: const InputDecoration(labelText: 'Folio')),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: TextField(controller: _dateCtrl, readOnly: true, decoration: const InputDecoration(labelText: 'Fecha'))),
              const SizedBox(width: 12),
              IconButton(onPressed: _pickDate, icon: const Icon(Icons.calendar_today)),
            ],
          ),
          const Divider(height: 32),
          Row(children: [
            Expanded(child: TextField(controller: _skuCtrl, decoration: const InputDecoration(labelText: 'SKU'))),
            const SizedBox(width: 8),
            SizedBox(width: 80, child: TextField(controller: _qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cant.'))),
            const SizedBox(width: 8),
            SizedBox(width: 120, child: TextField(controller: _costCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Costo'))),
            const SizedBox(width: 8),
            FilledButton(onPressed: _addLine, child: const Text('Agregar')),
          ]),
          const SizedBox(height: 12),
          ..._lines.map((l) => ListTile(
                title: Text('${l.sku}  x${l.qty}'),
                subtitle: Text('Costo: ${l.cost.toStringAsFixed(2)}  |  Importe: ${(l.cost * l.qty).toStringAsFixed(2)}'),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _lines.remove(l))),
              )),
          const Divider(height: 24),
          Align(alignment: Alignment.centerRight, child: Text('Total: ${total.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleMedium)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _savePurchase, child: const Text('Guardar compra')),
        ],
      ),
    );
  }
}

class _Line {
  final String sku;
  final int qty;
  final double cost;
  _Line({required this.sku, required this.qty, required this.cost});
}