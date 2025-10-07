import 'package:flutter/material.dart';
import '../repositories/supplier_repository.dart';

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});
  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  final _repo = SupplierRepository();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  List<Supplier> _rows = [];

  Future<void> _load() async {
    final r = await _repo.all(limit: 200);
    setState(()=>_rows = r);
  }

  Future<void> _add() async {
    if (_phone.text.trim().isEmpty || _name.text.trim().isEmpty) return;
    await _repo.upsertByPhone(phone: _phone.text.trim(), name: _name.text.trim(), address: _address.text.trim());
    _name.clear(); _phone.clear(); _address.clear();
    _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: ListTile(
            title: const Text('Proveedores'),
            subtitle: Text('Total: ${_rows.length}'),
          ),
        ),
        const SizedBox(height: 8),
        ..._rows.map((s)=> ListTile(
          title: Text(s.name),
          subtitle: Text('${s.phone}  •  ${s.address}'),
        )),
        const Divider(),
        const Text('Agregar proveedor'),
        const SizedBox(height: 6),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre')),
        const SizedBox(height: 6),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono (ID)')),
        const SizedBox(height: 6),
        TextField(controller: _address, decoration: const InputDecoration(labelText: 'Dirección')),
        const SizedBox(height: 6),
        FilledButton(onPressed: _add, child: const Text('Guardar')),
      ],
    );
  }
}
