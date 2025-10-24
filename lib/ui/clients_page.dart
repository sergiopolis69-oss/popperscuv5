// lib/ui/clients_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

// Intenta usar getDb(); si no existe, usa DatabaseHelper.instance.db
import '../data/database.dart' as appdb;

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

  final _qCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _selected;

  // Top 5
  List<Map<String, dynamic>> _top5 = [];

  @override
  void initState() {
    super.initState();
    _loadTop5();
    _searchClients('');
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  Future<Database> _db() async {
    try {
      // Si tu proyecto expone getDb(), úsalo
      // ignore: unnecessary_await_in_return
      return await appdb.getDb();
    } catch (_) {
      return await appdb.DatabaseHelper.instance.db;
    }
  }

  Future<void> _loadTop5() async {
    final db = await _db();
    final rows = await db.rawQuery('''
      SELECT 
        c.phone,
        COALESCE(c.name,'') AS name,
        COALESCE(c.address,'') AS address,
        COALESCE(SUM(si.quantity * si.unit_price), 0) AS total
      FROM customers c
      LEFT JOIN sales s ON s.customer_phone = c.phone
      LEFT JOIN sale_items si ON si.sale_id = s.id
      GROUP BY c.phone
      ORDER BY total DESC
      LIMIT 5
    ''');
    setState(() => _top5 = rows);
  }

  Future<void> _searchClients(String q) async {
    final db = await _db();
    final like = '%${q.trim()}%';
    final rows = await db.rawQuery('''
      SELECT phone, COALESCE(name,'') AS name, COALESCE(address,'') AS address
      FROM customers
      WHERE (? = '' OR phone LIKE ? OR name LIKE ?)
      ORDER BY name COLLATE NOCASE
      LIMIT 100
    ''', [q.trim(), like, like]);
    setState(() {
      _results = rows;
      // Si hay un seleccionado que ya no está en resultados, lo mantenemos igual
    });
  }

  Future<double> _totalSalesOf(String phone) async {
    final db = await _db();
    final row = await db.rawQuery('''
      SELECT COALESCE(SUM(si.quantity * si.unit_price), 0) AS total
      FROM sales s
      LEFT JOIN sale_items si ON si.sale_id = s.id
      WHERE s.customer_phone = ?
    ''', [phone]);
    final n = (row.isNotEmpty ? row.first['total'] : 0) as num;
    return n.toDouble();
  }

  Future<int> _countSalesOf(String phone) async {
    final db = await _db();
    final row = await db.rawQuery('''
      SELECT COUNT(*) AS cnt
      FROM sales
      WHERE customer_phone = ?
    ''', [phone]);
    final n = (row.isNotEmpty ? row.first['cnt'] : 0) as num;
    return n.toInt();
  }

  Future<void> _selectCustomer(Map<String, dynamic> c) async {
    final phone = (c['phone'] ?? '').toString();
    final total = await _totalSalesOf(phone);
    final cnt = await _countSalesOf(phone);
    setState(() {
      _selected = {
        ...c,
        'total_sales': total,
        'sales_count': cnt,
      };
    });
  }

  Future<void> _addClientDialog() async {
    final phoneCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final addrCtrl = TextEditingController();

    final askConfirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nuevo cliente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono (ID)*'),
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuar')),
        ],
      ),
    );

    if (askConfirm != true) return;

    final phone = phoneCtrl.text.trim();
    final name = nameCtrl.text.trim();
    final addr = addrCtrl.text.trim();

    if (phone.isEmpty) {
      _snack('El teléfono (ID) es obligatorio');
      return;
    }

    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar'),
        content: Text('¿Guardar cliente con ID: $phone?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );

    if (sure != true) return;

    try {
      final db = await _db();
      await db.insert('customers', {
        'phone': phone,
        'name': name,
        'address': addr,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      _snack('Cliente guardado');
      await _loadTop5();
      await _searchClients(_qCtrl.text);
    } catch (e) {
      _snack('Error al guardar: $e');
    }
  }

  Future<void> _editClientDialog(Map<String, dynamic> c) async {
    final phone = (c['phone'] ?? '').toString();
    final nameCtrl = TextEditingController(text: (c['name'] ?? '').toString());
    final addrCtrl = TextEditingController(text: (c['address'] ?? '').toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Editar cliente $phone'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(enabled: false, decoration: InputDecoration(labelText: 'Teléfono (ID)', hintText: phone)),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
            TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: 'Dirección')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar cambios')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final db = await _db();
      await db.update(
        'customers',
        {'name': nameCtrl.text.trim(), 'address': addrCtrl.text.trim()},
        where: 'phone = ?',
        whereArgs: [phone],
      );

      _snack('Cliente actualizado');
      await _loadTop5();
      await _searchClients(_qCtrl.text);
      if (_selected != null && _selected!['phone'] == phone) {
        _selectCustomer({
          'phone': phone,
          'name': nameCtrl.text.trim(),
          'address': addrCtrl.text.trim(),
        });
      }
    } catch (e) {
      _snack('Error al actualizar: $e');
    }
  }

  Future<void> _deleteClient(String phone) async {
    final tot = await _totalSalesOf(phone);
    final cnt = await _countSalesOf(phone);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: Text(
          'Se eliminará el cliente $phone.\n'
          'Histórico de ventas registradas: $cnt por ${_money.format(tot)}.\n\n'
          'Nota: Las ventas históricas permanecerán con el ID de cliente guardado en cada venta.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final db = await _db();
      await db.delete('customers', where: 'phone = ?', whereArgs: [phone]);

      if (mounted) _snack('Cliente eliminado');
      setState(() {
        if (_selected != null && _selected!['phone'] == phone) {
          _selected = null;
        }
      });
      await _loadTop5();
      await _searchClients(_qCtrl.text);
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
        title: const Text('Clientes'),
        actions: [
          IconButton(
            tooltip: 'Añadir cliente',
            onPressed: _addClientDialog,
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // TOP 5
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Top 5 clientes por ventas históricas', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_top5.isEmpty)
                    const Text('Sin datos')
                  else
                    Column(
                      children: _top5.map((c) {
                        final name = (c['name'] ?? '').toString();
                        final phone = (c['phone'] ?? '').toString();
                        final total = (c['total'] as num?)?.toDouble() ?? 0.0;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.star),
                          title: Text(name.isEmpty ? '(sin nombre)' : name),
                          subtitle: Text(phone),
                          trailing: Text(_money.format(total)),
                          onTap: () => _selectCustomer(c),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),

          // BUSCADOR
          TextField(
            controller: _qCtrl,
            decoration: InputDecoration(
              labelText: 'Buscar cliente (teléfono o nombre)',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Limpiar',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _qCtrl.clear();
                  _searchClients('');
                },
              ),
            ),
            onChanged: _searchClients,
          ),
          const SizedBox(height: 8),

          // RESULTADOS
          if (_results.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Text('No hay clientes'),
            )
          else
            ..._results.map((c) {
              final name = (c['name'] ?? '').toString();
              final phone = (c['phone'] ?? '').toString();
              final addr = (c['address'] ?? '').toString();
              final selected = _selected != null && _selected!['phone'] == phone;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  title: Text(name.isEmpty ? '(sin nombre)' : name),
                  subtitle: Text([phone, if (addr.isNotEmpty) addr].join(' • ')),
                  trailing: Icon(selected ? Icons.check_circle : Icons.chevron_right),
                  onTap: () => _selectCustomer(c),
                ),
              );
            }),

          const SizedBox(height: 12),

          // DETALLE DEL SELECCIONADO
          if (_selected != null)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _ClientDetail(
                  data: _selected!,
                  money: _money,
                  onEdit: () => _editClientDialog(_selected!),
                  onDelete: () => _deleteClient((_selected!['phone'] ?? '').toString()),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addClientDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo'),
      ),
    );
  }
}

class _ClientDetail extends StatelessWidget {
  const _ClientDetail({
    required this.data,
    required this.money,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> data;
  final NumberFormat money;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final phone = (data['phone'] ?? '').toString();
    final name = (data['name'] ?? '').toString();
    final address = (data['address'] ?? '').toString();
    final total = (data['total_sales'] as num?)?.toDouble() ?? 0.0;
    final cnt = (data['sales_count'] as num?)?.toInt() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name.isEmpty ? '(sin nombre)' : name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 6),
        Text([phone, if (address.isNotEmpty) address].join(' • ')),
        const Divider(height: 20),
        Row(
          children: [
            Expanded(child: _kv('Ventas registradas', '$cnt')),
            Expanded(child: _kv('Total histórico', money.format(total))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit), label: const Text('Editar')),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_forever),
              label: const Text('Eliminar'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(k, style: const TextStyle(fontWeight: FontWeight.w500))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}