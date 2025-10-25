// lib/ui/clients_page.dart
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../data/database.dart' as appdb;

class ClientsPage extends StatefulWidget {
  const ClientsPage({Key? key}) : super(key: key);

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  final _qCtrl = TextEditingController();

  // Top clientes
  List<Map<String, dynamic>> _topClients = [];

  // Resultados de búsqueda
  List<Map<String, dynamic>> _clients = [];
  Map<String, dynamic>? _selectedClient;
  double _selectedClientTotal = 0.0;

  // Alta / edición rápida
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTopClients();
    _loadClients();
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  Future<Database> _db() async {
    try {
      return await appdb.getDb();
    } catch (_) {
      return await appdb.DatabaseHelper.instance.db;
    }
  }

  // ----------- Data loaders -----------

  Future<void> _loadTopClients() async {
    final db = await _db();
    final rows = await db.rawQuery('''
      SELECT c.phone,
             COALESCE(NULLIF(TRIM(c.name),''), c.phone) AS name,
             COALESCE(SUM(
               (SELECT COALESCE(SUM(si.quantity * si.unit_price),0) 
                  FROM sale_items si WHERE si.sale_id = s.id)
               + COALESCE(s.shipping_cost,0)
               - COALESCE(s.discount,0)
             ), 0) AS total
      FROM customers c
      LEFT JOIN sales s ON s.customer_phone = c.phone
      GROUP BY c.phone
      ORDER BY total DESC
      LIMIT 10
    ''');
    setState(() => _topClients = rows);
  }

  Future<void> _loadClients({String? q}) async {
    final db = await _db();
    final _q = (q ?? _qCtrl.text).trim();

    final rows = await db.rawQuery('''
      SELECT phone,
             COALESCE(NULLIF(TRIM(name),''), phone) AS name,
             address
      FROM customers
      ${_q.isEmpty ? '' : 'WHERE phone LIKE ? OR name LIKE ? OR address LIKE ?'}
      ORDER BY name COLLATE NOCASE
      LIMIT 200
    ''', _q.isEmpty ? [] : ['%$_q%', '%$_q%', '%$_q%']);

    setState(() {
      _clients = rows;
      if (_selectedClient != null) {
        final ph = _selectedClient!['phone'] as String;
        _selectedClient = rows.cast<Map<String, dynamic>?>().firstWhere(
              (r) => r?['phone'] == ph,
              orElse: () => null,
            );
      }
    });
  }

  Future<void> _selectClient(Map<String, dynamic> c) async {
    setState(() => _selectedClient = c);
    final db = await _db();

    // Total histórico de ventas a ese cliente (envíos incluidos y descuentos restados)
    final totRow = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(COALESCE(s.shipping_cost,0) + (
          SELECT COALESCE(SUM(si.quantity * si.unit_price),0)
          FROM sale_items si WHERE si.sale_id = s.id
        ) - COALESCE(s.discount,0)), 0) AS total
      FROM sales s
      WHERE s.customer_phone = ?
    ''', [c['phone']]);

    final totalNum = (totRow.isEmpty ? 0 : (totRow.first['total'] ?? 0)) as num;
    setState(() => _selectedClientTotal = totalNum.toDouble());
  }

  // ----------- Agregar / Eliminar -----------

  Future<void> _confirmAddClient({String prePhone = '', String preName = '', String preAddr = ''}) async {
    _phoneCtrl.text = prePhone;
    _nameCtrl.text = preName;
    _addrCtrl.text = preAddr;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Agregar cliente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono (ID) *'),
            ),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            TextField(
              controller: _addrCtrl,
              decoration: const InputDecoration(labelText: 'Dirección'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );

    if (ok == true) {
      final phone = _normalizePhone(_phoneCtrl.text.trim());
      if (phone.isEmpty) {
        _snack('El teléfono es obligatorio');
        return;
      }
      final name = _nameCtrl.text.trim();
      final addr = _addrCtrl.text.trim();

      final db = await _db();
      await db.insert('customers', {
        'phone': phone,
        'name': name,
        'address': addr,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      _snack('Cliente guardado');
      await _loadClients();
      await _loadTopClients();
    }
  }

  Future<void> _confirmDeleteClient(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: Text('¿Eliminar al cliente "${c['name'] ?? c['phone']}"? '
            'Las ventas históricas no se modificarán.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );

    if (ok == true) {
      final db = await _db();
      await db.delete('customers', where: 'phone = ?', whereArgs: [c['phone']]);
      setState(() {
        if (_selectedClient?['phone'] == c['phone']) {
          _selectedClient = null;
          _selectedClientTotal = 0.0;
        }
      });
      _snack('Cliente eliminado');
      await _loadClients();
      await _loadTopClients();
    }
  }

  // ----------- Importar UNO desde contactos -----------

  Future<void> _importOneFromContacts() async {
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        _snack('Permiso de contactos denegado');
        return;
      }

      // Abre el picker nativo para escoger UN contacto
      final picked = await FlutterContacts.openExternalPick();
      if (picked == null) {
        _snack('No seleccionaste contacto');
        return;
      }

      // Trae propiedades (teléfonos, etc.)
      final full = await FlutterContacts.getContact(picked.id, withProperties: true);
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
      final address = ''; // opcional: podrías mapear postalAddresses si quieres

      // Confirmación (y permite editar antes de guardar)
      await _confirmAddClient(
        prePhone: phone,
        preName: name.isNotEmpty ? name : phone,
        preAddr: address,
      );
    } catch (e) {
      _snack('Error importando contacto: $e');
    }
  }

  String? _firstPhone(Contact c) {
    if (c.phones.isEmpty) return null;
    return c.phones.first.number?.trim() ?? '';
  }

  String _normalizePhone(String raw) {
    return raw.replaceAll(RegExp(r'[\s\-\(\)\.\+]'), '');
  }

  // ----------- Historial de ventas de un cliente -----------

  Future<void> _showClientHistory(String phone, String name) async {
    final db = await _db();

    // Encabezados de ventas de ese cliente
    final heads = await db.rawQuery('''
      SELECT id, date, payment_method, place, 
             COALESCE(shipping_cost,0) AS shipping_cost,
             COALESCE(discount,0) AS discount
      FROM sales
      WHERE customer_phone = ?
      ORDER BY date DESC, id DESC
    ''', [phone]);

    if (heads.isEmpty) {
      // Hoja con mensaje vacío
      // ignore: use_build_context_synchronously
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(children: [
              Text('Historial de ventas de $name', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              const Text('No hay ventas registradas para este cliente.'),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      );
      return;
    }

    // Items de ventas de ese cliente
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
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Historial de ventas de $name',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: heads.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (_, i) {
                      final h = heads[i];
                      final saleId = h['id'] as int;
                      final its = bySale[saleId] ?? const [];
                      final itemsTotal = its.fold<double>(
                        0.0,
                        (a, b) => a + (b['quantity'] as int) * (b['unit_price'] as num).toDouble(),
                      );
                      final qtyTotal = its.fold<int>(
                        0,
                        (a, b) => a + (b['quantity'] as int),
                      );
                      final shipping = (h['shipping_cost'] as num).toDouble();
                      final discount = (h['discount'] as num).toDouble();
                      final grandTotal = itemsTotal + shipping - discount;

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Venta #$saleId • ${h['date']}',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text('Pago: ${h['payment_method'] ?? '(s/d)'} • Lugar: ${h['place'] ?? '(s/d)'}'),
                              const SizedBox(height: 8),
                              ...its.map((it) => ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text('${it['sku']}  ${it['name']}'),
                                    trailing: Text('${it['quantity']} × \$${(it['unit_price'] as num).toStringAsFixed(2)}'),
                                  )),
                              const Divider(),
                              Row(
                                children: [
                                  Expanded(child: Text('Pzas: $qtyTotal')),
                                  Expanded(child: Text('Artículos: \$${itemsTotal.toStringAsFixed(2)}')),
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(child: Text('Envío: \$${shipping.toStringAsFixed(2)}')),
                                  Expanded(child: Text('Descuento: -\$${discount.toStringAsFixed(2)}')),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text('Total: \$${grandTotal.toStringAsFixed(2)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
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
        );
      },
    );
  }

  // ----------- UI Helpers -----------

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ----------- Build -----------

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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _qCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar cliente (teléfono, nombre, dirección)…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                suffixIcon: _qCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _qCtrl.clear();
                          _loadClients();
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
              onChanged: (_) => _loadClients(),
              onSubmitted: (_) => _loadClients(),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_topClients.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Top 10 por ventas históricas',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _topClients.map((c) {
                      final total = (c['total'] as num?)?.toDouble() ?? 0.0;
                      return Chip(
                        label: Text('${c['name']} • \$${total.toStringAsFixed(2)}'),
                        avatar: const Icon(Icons.star, size: 18),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          const Divider(height: 0),
          Expanded(
            child: Row(
              children: [
                // Lista de clientes
                Expanded(
                  flex: 2,
                  child: _clients.isEmpty
                      ? const Center(child: Text('No hay clientes'))
                      : ListView.separated(
                          itemCount: _clients.length,
                          separatorBuilder: (_, __) => const Divider(height: 0),
                          itemBuilder: (_, i) {
                            final c = _clients[i];
                            return ListTile(
                              title: Text(c['name'] ?? c['phone']),
                              subtitle: Text(
                                '${c['phone']}${(c['address'] ?? '').toString().isNotEmpty ? ' • ${c['address']}' : ''}',
                              ),
                              onTap: () => _selectClient(c),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Historial',
                                    icon: const Icon(Icons.history),
                                    onPressed: () => _showClientHistory(
                                      (c['phone'] ?? '').toString(),
                                      (c['name'] ?? c['phone']).toString(),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: 'Eliminar',
                                    onPressed: () => _confirmDeleteClient(c),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                // Panel de detalle
                Expanded(
                  child: _selectedClient == null
                      ? const SizedBox()
                      : Container(
                          decoration: BoxDecoration(
                            border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Cliente', style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 8),
                                Text(_selectedClient!['name'] ?? _selectedClient!['phone'],
                                    style: Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: 4),
                                Text(_selectedClient!['phone'] ?? ''),
                                if ((_selectedClient!['address'] ?? '').toString().isNotEmpty)
                                  Text(_selectedClient!['address']),
                                const SizedBox(height: 16),
                                const Divider(),
                                const SizedBox(height: 8),
                                Text('Total histórico de ventas',
                                    style: Theme.of(context).textTheme.titleSmall),
                                const SizedBox(height: 4),
                                Text('\$${_selectedClientTotal.toStringAsFixed(2)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: FilledButton.icon(
                                    onPressed: () => _showClientHistory(
                                      (_selectedClient!['phone'] ?? '').toString(),
                                      (_selectedClient!['name'] ?? _selectedClient!['phone']).toString(),
                                    ),
                                    icon: const Icon(Icons.history),
                                    label: const Text('Ver historial'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}