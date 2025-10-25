// lib/ui/clients_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../data/database.dart' as appdb;

class ClientsPage extends StatefulWidget {
  const ClientsPage({Key? key}) : super(key: key);

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

  // Top 10
  List<Map<String, dynamic>> _top10 = [];

  // Buscador
  final _qCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];

  @override
  void initState() {
    super.initState();
    _loadTop10();
    _searchClients(''); // carga inicial
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  Future<Database> _db() async {
    try {
      // si tu proyecto expone getDb()
      // ignore: unnecessary_await_in_return
      return await appdb.getDb();
    } catch (_) {
      return await appdb.DatabaseHelper.instance.db;
    }
  }

  // ----------------- DATA -----------------

  Future<void> _loadTop10() async {
    final db = await _db();
    final rows = await db.rawQuery('''
      SELECT 
        c.phone,
        TRIM(COALESCE(c.name,'')) AS name,
        COALESCE(c.address,'') AS address,
        COALESCE(SUM(
          (SELECT COALESCE(SUM(si.quantity*si.unit_price),0) FROM sale_items si WHERE si.sale_id = s.id)
          + COALESCE(s.shipping_cost,0)
          - COALESCE(s.discount,0)
        ),0) AS total
      FROM customers c
      LEFT JOIN sales s ON s.customer_phone = c.phone
      GROUP BY c.phone
      ORDER BY total DESC
      LIMIT 10
    ''');
    setState(() => _top10 = rows);
  }

  Future<void> _searchClients(String q) async {
    final db = await _db();
    final like = '%${q.trim()}%';
    final rows = await db.rawQuery('''
      SELECT phone,
             TRIM(COALESCE(name,'')) AS name,
             COALESCE(address,'') AS address
      FROM customers
      WHERE (? = '' OR phone LIKE ? OR name LIKE ? OR address LIKE ?)
      ORDER BY name COLLATE NOCASE
      LIMIT 400
    ''', [q.trim(), like, like, like]);
    setState(() => _results = rows);
  }

  Future<num> _clientTotals(String phone) async {
    final db = await _db();
    final row = await db.rawQuery('''
      SELECT COALESCE(SUM(
        (SELECT COALESCE(SUM(si.quantity*si.unit_price),0) FROM sale_items si WHERE si.sale_id = s.id)
        + COALESCE(s.shipping_cost,0)
        - COALESCE(s.discount,0)
      ),0) AS total
      FROM sales s
      WHERE s.customer_phone = ?
    ''', [phone]);
    return (row.isEmpty ? 0 : (row.first['total'] ?? 0)) as num;
  }

  Future<int> _clientSalesCount(String phone) async {
    final db = await _db();
    final row = await db.rawQuery('SELECT COUNT(*) AS cnt FROM sales WHERE customer_phone = ?', [phone]);
    return ((row.isEmpty ? 0 : (row.first['cnt'] ?? 0)) as num).toInt();
  }

  // ----------------- IMPORTAR 1 CONTACTO -----------------

  Future<void> _importOneFromContacts() async {
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        _snack('Permiso de contactos denegado');
        return;
      }

      // Abre el picker nativo (1 contacto)
      final picked = await FlutterContacts.openExternalPick();
      if (picked == null) {
        _snack('No seleccionaste contacto');
        return;
      }

      final full = await FlutterContacts.getContact(picked.id, withProperties: true, withAccounts: false);
      if (full == null) {
        _snack('No fue posible leer el contacto');
        return;
      }

      final phoneRaw = _firstPhone(full);
      if (phoneRaw == null || phoneRaw.isEmpty) {
        _snack('El contacto no tiene teléfono');
        return;
      }

      final phone = _normalizePhone(phoneRaw);
      final name = (full.displayName ?? '').trim();
      final addr = ''; // Si quieres, puedes mapear postalAddresses aquí

      await _confirmAddClient(prePhone: phone, preName: name, preAddr: addr);
    } catch (e) {
      _snack('Error importando contacto: $e');
    }
  }

  String? _firstPhone(Contact c) {
    if (c.phones.isEmpty) return null;
    return c.phones.first.number?.trim() ?? '';
  }

  String _normalizePhone(String raw) {
    // Quita espacios, -, (), ., +
    return raw.replaceAll(RegExp(r'[\s\-\(\)\.\+]'), '');
  }

  // ----------------- CRUD CLIENTE -----------------

  Future<void> _confirmAddClient({String prePhone = '', String preName = '', String preAddr = ''}) async {
    final phoneCtrl = TextEditingController(text: prePhone);
    final nameCtrl = TextEditingController(text: preName);
    final addrCtrl = TextEditingController(text: preAddr);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Agregar cliente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono (ID) *'),
            ),
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

    final phone = _normalizePhone(phoneCtrl.text.trim());
    if (phone.isEmpty) {
      _snack('El teléfono (ID) es obligatorio');
      return;
    }
    final name = nameCtrl.text.trim();
    final addr = addrCtrl.text.trim();

    try {
      final db = await _db();
      await db.insert('customers', {
        'phone': phone,
        'name': name,
        'address': addr,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      _snack('Cliente guardado');
      await _loadTop10();
      await _searchClients(_qCtrl.text);
    } catch (e) {
      _snack('Error al guardar: $e');
    }
  }

  Future<void> _editClient(Map<String, dynamic> c) async {
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
      await db.update('customers', {
        'name': nameCtrl.text.trim(),
        'address': addrCtrl.text.trim(),
      }, where: 'phone = ?', whereArgs: [phone]);

      _snack('Cliente actualizado');
      await _loadTop10();
      await _searchClients(_qCtrl.text);
    } catch (e) {
      _snack('Error al actualizar: $e');
    }
  }

  Future<void> _deleteClient(Map<String, dynamic> c) async {
    final phone = (c['phone'] ?? '').toString();
    final tot = await _clientTotals(phone);
    final cnt = await _clientSalesCount(phone);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: Text(
          'Se eliminará el cliente ${c['name'] ?? phone}.\n'
          'Ventas registradas: $cnt por ${_money.format((tot).toDouble())}.\n\n'
          'Nota: las ventas históricas no se modifican.',
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
      _snack('Cliente eliminado');
      await _loadTop10();
      await _searchClients(_qCtrl.text);
    } catch (e) {
      _snack('Error al eliminar: $e');
    }
  }

  // ----------------- HISTORIAL -----------------

  Future<void> _showClientHistory(String phone, String name) async {
    final db = await _db();
    final heads = await db.rawQuery('''
      SELECT id, date, payment_method, place,
             COALESCE(shipping_cost,0) AS shipping_cost,
             COALESCE(discount,0) AS discount
      FROM sales
      WHERE customer_phone = ?
      ORDER BY date DESC, id DESC
    ''', [phone]);

    final items = await db.rawQuery('''
      SELECT si.sale_id, p.sku, p.name, si.quantity, si.unit_price
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN products p ON p.id = si.product_id
      WHERE s.customer_phone = ?
      ORDER BY si.sale_id DESC, p.name COLLATE NOCASE
    ''', [phone]);

    final bySale = <int, List<Map<String, dynamic>>>{};
    for (final it in items) {
      bySale.putIfAbsent(it['sale_id'] as int, () => []).add(it);
    }

    // ignore: use_build_context_synchronously
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Historial de ventas de $name', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Expanded(
                child: heads.isEmpty
                    ? const Center(child: Text('Sin ventas registradas'))
                    : ListView.separated(
                        itemCount: heads.length,
                        separatorBuilder: (_, __) => const Divider(height: 16),
                        itemBuilder: (_, i) {
                          final h = heads[i];
                          final saleId = h['id'] as int;
                          final its = bySale[saleId] ?? const [];
                          final itemsTotal = its.fold<double>(0.0, (a, b) => a + (b['quantity'] as int) * (b['unit_price'] as num).toDouble());
                          final qtyTotal = its.fold<int>(0, (a, b) => a + (b['quantity'] as int));
                          final shipping = (h['shipping_cost'] as num).toDouble();
                          final discount = (h['discount'] as num).toDouble();
                          final grand = itemsTotal + shipping - discount;

                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Venta #$saleId • ${h['date']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text('Pago: ${h['payment_method'] ?? '(s/d)'} • Lugar: ${h['place'] ?? '(s/d)'}'),
                                  const SizedBox(height: 8),
                                  ...its.map((it) => ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        title: Text('${it['sku']}  ${it['name']}'),
                                        trailing: Text('${it['quantity']} × ${_money.format((it['unit_price'] as num).toDouble())}'),
                                      )),
                                  const Divider(),
                                  Row(
                                    children: [
                                      Expanded(child: Text('Pzas: $qtyTotal')),
                                      Expanded(child: Text('Artículos: ${_money.format(itemsTotal)}')),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Expanded(child: Text('Envío: ${_money.format(shipping)}')),
                                      Expanded(child: Text('Descuento: -${_money.format(discount)}')),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Text('Total: ${_money.format(grand)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------- UI -----------------

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
            tooltip: 'Importar 1 contacto',
            onPressed: _importOneFromContacts,
            icon: const Icon(Icons.contact_phone),
          ),
          IconButton(
            tooltip: 'Agregar cliente',
            onPressed: () => _confirmAddClient(),
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Top 10
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Top 10 por ventas históricas', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_top10.isEmpty)
                    const Text('Sin datos')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _top10.map((c) {
                        final total = (c['total'] as num?)?.toDouble() ?? 0.0;
                        final label = (c['name'] as String?)?.isNotEmpty == true ? c['name'] as String : (c['phone'] ?? '') as String;
                        return ActionChip(
                          avatar: const Icon(Icons.star, size: 18),
                          label: Text('$label • ${_money.format(total)}'),
                          onPressed: () => _showClientHistory((c['phone'] ?? '').toString(), label),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),

          // Buscador
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: TextField(
                controller: _qCtrl,
                decoration: InputDecoration(
                  hintText: 'Buscar cliente (teléfono, nombre o dirección)…',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                  suffixIcon: _qCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _qCtrl.clear();
                            _searchClients('');
                          },
                          icon: const Icon(Icons.clear),
                        ),
                ),
                onChanged: _searchClients,
                onSubmitted: _searchClients,
              ),
            ),
          ),

          // Resultados
          if (_results.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 24, 12, 24),
                child: Text('No hay clientes'),
              ),
            )
          else
            SliverList.separated(
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 0),
              itemBuilder: (_, i) {
                final c = _results[i];
                final name = (c['name'] ?? '') as String;
                final phone = (c['phone'] ?? '') as String;
                final addr = (c['address'] ?? '') as String;

                return ListTile(
                  title: Text(name.isEmpty ? '(sin nombre)' : name),
                  subtitle: Text([phone, if (addr.isNotEmpty) addr].join(' • ')),
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  onTap: () async {
                    final total = await _clientTotals(phone);
                    final cnt = await _clientSalesCount(phone);
                    if (!mounted) return;

                    // BottomSheet de acciones + resumen
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name.isEmpty ? phone : name, style: Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 6),
                              Text([phone, if (addr.isNotEmpty) addr].join(' • ')),
                              const Divider(height: 20),
                              Row(
                                children: [
                                  Expanded(child: _kv('Ventas registradas', '$cnt')),
                                  Expanded(child: _kv('Total histórico', _money.format((total).toDouble()))),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    icon: const Icon(Icons.history),
                                    label: const Text('Ver historial'),
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      _showClientHistory(phone, name.isEmpty ? phone : name);
                                    },
                                  ),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.edit),
                                    label: const Text('Editar'),
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      _editClient(c);
                                    },
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Eliminar'),
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      _deleteClient(c);
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _confirmAddClient(),
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo'),
      ),
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