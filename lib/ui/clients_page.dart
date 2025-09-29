import 'package:flutter/material.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
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
    setState(()=> {_count=c, _top=t});
  }

  Future<void> _add() async {
    if (_phoneCtrl.text.trim().isEmpty || _nameCtrl.text.trim().isEmpty) return;
    await _repo.upsert(_phoneCtrl.text.trim(), _nameCtrl.text.trim(), _addrCtrl.text.trim());
    _nameCtrl.clear(); _phoneCtrl.clear(); _addrCtrl.clear();
    _refresh();
  }

  Future<void> _importFromContacts() async {
    final status = await Permission.contacts.request();
    if (!status.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permiso de contactos denegado')));
      return;
    }
    final contact = await ContactsService.openDeviceContactPicker();
    if (contact == null) return;
    final name = (contact.displayName ?? '').trim();
    final phone = (contact.phones?.isNotEmpty == true) ? (contact.phones!.first.value ?? '').replaceAll(RegExp(r'\\s'), '') : '';
    if (phone.isEmpty || name.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contacto sin nombre o teléfono')));
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
        ..._top.map((c)=>ListTile(
          title: Text('${c['name']}'),
          subtitle: Text('${c['phone']}'),
          trailing: Text('\\$${(c['total'] as num?)?.toDouble().toString()}'),
        )),
        const Divider(),
        const Text('Agregar cliente'),
        const SizedBox(height: 6),
        TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
        const SizedBox(height: 6),
        TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Teléfono (ID)')),
        const SizedBox(height: 6),
        TextField(controller: _addrCtrl, decoration: const InputDecoration(labelText: 'Dirección')),
        const SizedBox(height: 6),
        FilledButton(onPressed: _add, child: const Text('Guardar')),
      ],
    );
  }
}