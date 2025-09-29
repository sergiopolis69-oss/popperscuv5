import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../repositories/client_repository.dart';

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});
  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  final _repo = ClientRepository();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();

  int _count = 0;
  List<Map<String, dynamic>> _top = [];

  Future<void> _refresh() async {
    final c = await _repo.count();
    final t = await _repo.topClients(limit: 10);
    setState(() => {_count = c, _top = t});
  }

  Future<void> _add() async {
    if (_phoneCtrl.text.trim().isEmpty || _nameCtrl.text.trim().isEmpty) return;
    await _repo.upsert(
      _phoneCtrl.text.trim(),
      _nameCtrl.text.trim(),
      _addrCtrl.text.trim(),
    );
    _nameCtrl.clear();
    _phoneCtrl.clear();
    _addrCtrl.clear();
    _refresh();
  }

  Future<void> _importFromContacts() async {
    final granted = await FlutterContacts.requestPermission();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permiso de contactos denegado')),
      );
      return;
    }
    // Abre el picker nativo
    final picked = await FlutterContacts.openExternalPick();
    if (picked == null) return;

    // Asegura traer teléfonos
    await picked.fetch(withProperties: true);
    final name = picked.displayName.trim();
    final phone = picked.phones.isNotEmpty
        ? picked.phones.first.number.replaceAll(RegExp(r'\s'), '')
        : '';

    if (name.isEmpty || phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contacto sin nombre o teléfono')),
      );
      return;
    }

    _nameCtrl.text = name;
    _phoneCtrl.text = phone;
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: ListTile(
            title: const Text('Mejores clientes'),
            subtitle: Text('Total clientes: $_count'),
            trailing: IconButton(
              tooltip: 'Importar contacto',
              icon: const Icon(Icons.contacts),
              onPressed: _importFromContacts,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ..._top.map(
          (c) => ListTile(
            title: Text('${c['name']}'),
            subtitle: Text('${c['phone']}'),
            trailing: Text('\$${(c['total'] as num?)?.toDouble().toString()}'),
          ),
        ),
        const Divider(),
        const Text('Agregar cliente'),
        const SizedBox(height: 6),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _phoneCtrl,
          decoration: const InputDecoration(labelText: 'Teléfono (ID)'),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _addrCtrl,
          decoration: const InputDecoration(labelText: 'Dirección'),
        ),
        const SizedBox(height: 6),
        FilledButton(onPressed: _add, child: const Text('Guardar')),
      ],
    );
  }
}