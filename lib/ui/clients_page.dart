import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../data/database.dart';

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});
  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _addr = TextEditingController();

  List<Map<String, dynamic>> _clients = [];
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await DatabaseHelper.instance.db;
    final rows = await db.query('customers', orderBy: 'name COLLATE NOCASE ASC', limit: 200);
    final c = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM customers')) ?? 0;
    setState(() {
      _clients = rows;
      _total = c;
    });
  }

  Future<void> _add() async {
    final phone = _phone.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El teléfono (ID) es obligatorio')));
      return;
    }
    final db = await DatabaseHelper.instance.db;
    await db.insert('customers', {
      'phone': phone,
      'name': _name.text.trim(),
      'address': _addr.text.trim(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _name.clear(); _phone.clear(); _addr.clear();
    _load();
  }

  Future<void> _pickFromContacts() async {
    final granted = await FlutterContacts.requestPermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permiso de contactos denegado')));
      }
      return;
    }
    final picked = await FlutterContacts.openExternalPick();
    if (picked == null) return;
    final contact = await FlutterContacts.getContact(picked.id, withProperties: true);
    if (contact == null) return;
    final display = contact.displayName;
    final phone = contact.phones.isNotEmpty ? contact.phones.first.number.replaceAll(' ', '') : '';
    setState(() {
      _name.text = display;
      _phone.text = phone; // obligatorio
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: ListTile(
            title: const Text('Clientes'),
            subtitle: Text('Total: $_total'),
            trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ),
        ),
        const SizedBox(height: 8),
        ..._clients.map((c)=> ListTile(
          title: Text(c['name'] ?? ''),
          subtitle: Text('${c['phone'] ?? ''} • ${c['address'] ?? ''}'),
        )),
        const Divider(),
        const Text('Agregar cliente'),
        const SizedBox(height: 6),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre')),
        const SizedBox(height: 6),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(
          labelText: 'Teléfono (ID) *',
          suffixIcon: IconButton(icon: const Icon(Icons.contacts), onPressed: _pickFromContacts),
        )),
        const SizedBox(height: 6),
        TextField(controller: _addr, decoration: const InputDecoration(labelText: 'Dirección')),
        const SizedBox(height: 6),
        FilledButton(onPressed: _add, child: const Text('Guardar')),
      ],
    );
  }
}
