
import 'package:flutter/material.dart';
import '../repositories/customer_repository.dart';
import '../models/customer.dart';

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  final _repo = CustomerRepository();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _addr = TextEditingController();
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: ListView(
        children: [
          FutureBuilder(
            future: Future.wait([_repo.count(), _repo.topCustomers()]),
            builder: (context, snapshot){
              if (!snapshot.hasData) return const SizedBox();
              final count = snapshot.data![0] as int;
              final top = snapshot.data![1] as List<Map<String, Object?>>;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Clientes: $count', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('Mejores clientes (por # de ventas):'),
                      ...top.map((r)=> ListTile(
                        dense: true,
                        title: Text('${r['name']} (${r['phone']})'),
                        trailing: Text('Ventas: ${r['salesCount']}'),
                      )),
                    ],
                  ),
                ),
              );
            },
          ),
          const Divider(),
          TextField(decoration: const InputDecoration(labelText: 'Buscar'), onChanged: (v)=> setState(()=>_q=v)),
          FutureBuilder(
            future: _repo.search(_q),
            builder: (context, snapshot){
              if (!snapshot.hasData) return const SizedBox();
              final data = snapshot.data!;
              return Column(children: data.map((c)=> ListTile(
                title: Text(c.name),
                subtitle: Text('${c.phone}  ·  ${c.address}'),
              )).toList());
            },
          ),
          const Divider(),
          const Text('Agregar cliente'),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre')),
          TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Teléfono (ID)')),
          TextField(controller: _addr, decoration: const InputDecoration(labelText: 'Dirección')),
          const SizedBox(height: 8),
          FilledButton(onPressed: () async {
            if (_phone.text.isEmpty) return;
            await _repo.upsert(Customer(phone: _phone.text, name: _name.text, address: _addr.text));
            if (context.mounted){
              _name.clear(); _phone.clear(); _addr.clear();
              setState((){});
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cliente guardado')));
            }
          }, child: const Text('Guardar')),
        ],
      ),
    );
  }
}
