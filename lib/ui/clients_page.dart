import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});
  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  List<Map<String, dynamic>> _clients = [];
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _addr = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await DatabaseHelper.instance.db;
    final rows = await db.query('customers', orderBy: 'name COLLATE NOCASE ASC');
    setState(()=>_clients = rows);
  }

  Future<void> _addManual() async {
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
    // 1) Estado actual
    final status = await FlutterContacts.permissionStatus();
    if (status.isDenied) {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permiso de contactos denegado')));
        return;
      }
    } else if (status.isPermanentlyDenied) {
      // Abre ajustes para que el usuario habilite el permiso
      await FlutterContacts.openExternalAppSettings();
      return;
    }

    // 2) Abrir selector nativo
    final picked = await FlutterContacts.openExternalPick();
    if (picked == null) return;
    final contact = await FlutterContacts.getContact(picked.id, withProperties: true);
    if (contact == null) return;

    final display = (contact.displayName ?? '').trim();
    final phone = (contact.phones.isNotEmpty ? contact.phones.first.number : '').replaceAll(' ', '');
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El contacto no tiene teléfono')));
      return;
    }

    final db = await DatabaseHelper.instance.db;
    await db.insert('customers', {
      'phone': phone,
      'name': display,
      'address': '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final best = _clients.take(5).toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(child: ListTile(
          title: const Text('Mejores clientes'),
          subtitle: Text('Top ${best.length} • Total clientes: ${_clients.length}'),
        )),
        ...best.map((c)=>ListTile(
          title: Text(c['name']?.toString().isEmpty == true ? c['phone'] : c['name']),
          subtitle: Text(c['phone']),
        )),
        const Divider(height: 24),
        Row(
          children: [
            const Text('Agregar cliente', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            OutlinedButton.icon(onPressed: _pickFromContacts, icon: const Icon(Icons.perm_contact_calendar), label: const Text('Desde contactos')),
          ],
        ),
        const SizedBox(height: 8),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono (ID) *')),
        const SizedBox(height: 8),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre')),
        const SizedBox(height: 8),
        TextField(controller: _addr, decoration: const InputDecoration(labelText: 'Dirección')),
        const SizedBox(height: 8),
        FilledButton(onPressed: _addManual, child: const Text('Guardar')),
      ],
    );
  }
}