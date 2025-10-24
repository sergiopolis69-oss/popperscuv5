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

  // Top 5
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

  Future<void> _loadTopClients() async {
    final db = await _db();
    final rows = await db.rawQuery('''
      SELECT c.phone,
             COALESCE(NULLIF(TRIM(c.name),''), c.phone) AS name,
             COALESCE(SUM(COALESCE(s.shipping_cost,0) + (
                SELECT COALESCE(SUM(pi.quantity * pi.unit_price),0)
                FROM sale_items pi
                WHERE pi.sale_id = s.id
             ) - COALESCE(s.discount,0)), 0) AS total
      FROM customers c
      LEFT JOIN sales s ON s.customer_phone = c.phone
      GROUP BY c.phone
      ORDER BY total DESC
      LIMIT 5
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
        _selectedClient =
            rows.cast<Map<String, dynamic>?>().firstWhere((r) => r?['phone'] == ph, orElse: () => null);
      }
    });
  }

  Future<void> _selectClient(Map<String, dynamic> c) async {
    setState(() => _selectedClient = c);
    final db = await _db();

    // Total histórico de ventas a ese cliente (envíos incluidos y descuentos restados para el total mostrado)
    final totRow = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(COALESCE(s.shipping_cost,0) + (
          SELECT COALESCE(SUM(si.quantity * si.unit_price),0)
          FROM sale_items si WHERE si.sale_id = s.id
        ) - COALESCE(s.discount,0)), 0) AS total
      FROM sales s
      WHERE s.customer_phone = ?
    ''', [c['phone']]);

    final total = (totRow.isEmpty ? 0 : (totRow.first['total'] as num? ?? 0).toDouble());
    setState(() => _selectedClientTotal = total);
  }

  Future<void> _confirmAddClient() async {
    _phoneCtrl.text = '';
    _nameCtrl.text = '';
    _addrCtrl.text = '';

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

  // ========== IMPORTAR DESDE CONTACTOS (flutter_contacts) ==========
  Future<void> _importFromContacts() async {
    try {
      // Pide permiso (read-only es suficiente)
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        _snack('Permiso de contactos denegado');
        return;
      }

      // Carga con propiedades para obtener phones
      final contacts = await FlutterContacts.getContacts(withProperties: true);

      if (contacts.isEmpty) {
        _snack('No se encontraron contactos');
        return;
      }

      final db = await _db();
      int imported = 0;
      int skipped = 0;

      for (final c in contacts) {
        final phone = _firstPhone(c);
        if (phone == null || phone.isEmpty) {
          skipped++;
          continue;
        }
        final normPhone = _normalizePhone(phone);
        if (normPhone.isEmpty) {
          skipped++;
          continue;
        }

        final displayName = (c.displayName ?? '').trim();
        final name = displayName.isNotEmpty ? displayName : normPhone;

        try {
          await db.insert('customers', {
            'phone': normPhone,
            'name': name,
            'address': '', // flutter_contacts requiere otra consulta para direcciones postales
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          imported++;
        } catch (_) {
          skipped++;
        }
      }

      _snack('Importados: $imported • Omitidos: $skipped');
      await _loadClients();
      await _loadTopClients();
    } catch (e) {
      _snack('Error importando contactos: $e');
    }
  }

  String? _firstPhone(Contact c) {
    if (c.phones.isEmpty) return null;
    return c.phones.first.number?.trim() ?? '';
  }

  String _normalizePhone(String raw) {
    // Quita espacios, guiones, paréntesis, + y puntos
    return raw.replaceAll(RegExp(r'[\s\-\(\)\.\+]'), '');
  }
  // ===========================================================

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: [
          IconButton(
            tooltip: 'Importar desde contactos',
            onPressed: _importFromContacts,
            icon: const Icon(Icons.contact_phone),
          ),
          IconButton(
            tooltip: 'Agregar cliente',
            onPressed: _confirmAddClient,
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
          // Top 5
          if (_topClients.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Top 5 por ventas históricas',
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

          // Lista de clientes
          Expanded(
            child: Row(
              children: [
                // Lista
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
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Eliminar',
                                onPressed: () => _confirmDeleteClient(c),
                              ),
                            );
                          },
                        ),
                ),

                // Detalle seleccionado
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