
import 'package:flutter/material.dart';
import '../repositories/product_repository.dart';
import '../models/product.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _repo = ProductRepository();
  String _q = '';
  final _name = TextEditingController();
  final _cat = TextEditingController();
  final _sale = TextEditingController();
  final _cost = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: ListView(
        children: [
          TextField(decoration: const InputDecoration(labelText: 'Buscar'), onChanged: (v)=> setState(()=>_q=v)),
          FutureBuilder(
            future: _repo.search(_q),
            builder: (context, snapshot){
              if (!snapshot.hasData) return const SizedBox();
              final data = snapshot.data!;
              return Column(children: data.map((p)=> ListTile(
                title: Text(p.name),
                subtitle: Text('Cat: ${p.category}  Stock: ${p.stock}  PV: ${p.salePrice.toStringAsFixed(2)}  Costo: ${p.lastPurchasePrice.toStringAsFixed(2)}  Últ. compra: ${p.lastPurchaseDate ?? '-'}'),
              )).toList());
            },
          ),
          const Divider(),
          const Text('Agregar/editar producto'),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre')),
          TextField(controller: _cat, decoration: const InputDecoration(labelText: 'Categoría')),
          TextField(controller: _sale, decoration: const InputDecoration(labelText: 'Precio venta'), keyboardType: TextInputType.number),
          TextField(controller: _cost, decoration: const InputDecoration(labelText: 'Último costo'), keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          FilledButton(onPressed: () async {
            final p = Product(
              name: _name.text, category: _cat.text,
              salePrice: double.tryParse(_sale.text) ?? 0,
              lastPurchasePrice: double.tryParse(_cost.text) ?? 0,
            );
            await _repo.insert(p);
            if (context.mounted){
              _name.clear(); _cat.clear(); _sale.clear(); _cost.clear();
              setState((){});
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto guardado')));
            }
          }, child: const Text('Guardar')),
        ],
      ),
    );
  }
}
