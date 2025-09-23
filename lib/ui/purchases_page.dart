
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../repositories/purchase_repository.dart';
import '../repositories/product_repository.dart';
import '../models/purchase.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _repo = PurchaseRepository();
  final _prodRepo = ProductRepository();
  String _supplier = '';
  final _items = <PurchaseItem>[];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: ListView(
        children: [
          TextField(decoration: const InputDecoration(labelText: 'Proveedor'), onChanged: (v)=>_supplier=v),
          const SizedBox(height: 8),
          FutureBuilder(
            future: _prodRepo.all(),
            builder: (context, snapshot){
              if (!snapshot.hasData) return const SizedBox();
              final data = snapshot.data!;
              return Column(children: data.take(12).map((p)=> ListTile(
                title: Text(p.name),
                subtitle: Text('Cat: ${p.category}'),
                trailing: IconButton(icon: const Icon(Icons.add), onPressed: (){
                  _items.add(PurchaseItem(purchaseId: 0, productId: p.id!, quantity: 1, unitCost: p.lastPurchasePrice));
                  setState((){});
                }),
              )).toList());
            },
          ),
          const Divider(),
          const Text('Detalle compra'),
          ..._items.asMap().entries.map((e){
            final i = e.key; final it = e.value;
            return Row(
              children: [
                Expanded(child: Text('Prod: ${it.productId}')),
                Expanded(child: TextFormField(initialValue: it.quantity.toString(), keyboardType: TextInputType.number, onChanged: (v)=> _items[i] = PurchaseItem(purchaseId: 0, productId: it.productId, quantity: int.tryParse(v)??1, unitCost: it.unitCost))),
                Expanded(child: TextFormField(initialValue: it.unitCost.toStringAsFixed(2), keyboardType: TextInputType.number, onChanged: (v)=> _items[i] = PurchaseItem(purchaseId: 0, productId: it.productId, quantity: it.quantity, unitCost: double.tryParse(v)??it.unitCost))),
                IconButton(icon: const Icon(Icons.delete), onPressed: (){ setState(()=>_items.removeAt(i)); }),
              ],
            );
          }),
          const SizedBox(height: 8),
          FilledButton(onPressed: () async {
            final now = DateFormat('yyyy-MM-dd').format(DateTime.now());
            final pid = await _repo.createPurchase(Purchase(date: now, supplier: _supplier), _items);
            if (context.mounted){
              _items.clear();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compra registrada (ID $pid)')));
              setState((){});
            }
          }, child: const Text('Registrar compra')),
          const Divider(),
          const Text('Compras recientes'),
          FutureBuilder(
            future: _repo.recentPurchases(),
            builder: (context, snapshot){
              if (!snapshot.hasData) return const SizedBox();
              return Column(children: snapshot.data!.map((r)=> ListTile(
                title: Text('Compra #${r['id']} - ${r['date']}'),
                subtitle: Text('Proveedor: ${r['supplier']}'),
                trailing: Text((r['total'] as num).toStringAsFixed(2)),
              )).toList());
            },
          ),
        ],
      ),
    );
  }
}
