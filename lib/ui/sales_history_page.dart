
import 'package:flutter/material.dart';
import '../repositories/sale_repository.dart';
import 'components/search_field.dart';

class SalesHistoryPage extends StatefulWidget {
  const SalesHistoryPage({super.key});

  @override
  State<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends State<SalesHistoryPage> {
  final _repo = SaleRepository();
  String _customer = '';
  String _payment = '';
  String _productLike = '';
  String _from = '2025-01-01';
  String _to = '2030-01-01';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: ListView(
        children: [
          Row(
            children: [
              Expanded(child: TextFormField(decoration: const InputDecoration(labelText: 'Desde (YYYY-MM-DD)'), initialValue: _from, onChanged: (v)=>_from=v)),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(decoration: const InputDecoration(labelText: 'Hasta (YYYY-MM-DD)'), initialValue: _to, onChanged: (v)=>_to=v)),
            ],
          ),
          const SizedBox(height: 8),
          SearchField(hint: 'Filtrar por cliente (teléfono)', onChanged: (v)=> setState(()=>_customer=v)),
          const SizedBox(height: 8),
          SearchField(hint: 'Filtrar por producto (nombre contiene)', onChanged: (v)=> setState(()=>_productLike=v)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _payment.isEmpty ? null : _payment,
            items: const [
              DropdownMenuItem(value: 'Efectivo', child: Text('Efectivo')),
              DropdownMenuItem(value: 'Tarjeta', child: Text('Tarjeta')),
              DropdownMenuItem(value: 'Transferencia', child: Text('Transferencia')),
            ],
            onChanged: (v)=> setState(()=>_payment=v ?? ''),
            decoration: const InputDecoration(labelText: 'Forma de pago'),
          ),
          const Divider(),
          FutureBuilder(
            future: _repo.history(
              customerPhone: _customer.isEmpty ? null : _customer,
              paymentMethod: _payment.isEmpty ? null : _payment,
              productNameLike: _productLike.isEmpty ? null : _productLike,
              fromDateInclusive: _from,
              toDateInclusive: _to,
            ),
            builder: (context, snapshot){
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final data = snapshot.data!;
              return Column(
                children: data.map((r){
                  final total = (r['subtotal'] as num).toDouble() + (r['shippingCost'] as num).toDouble() - (r['discount'] as num).toDouble();
                  return ListTile(
                    title: Text('Venta #${r['id']} - ${r['datetime']}'),
                    subtitle: Text('Cliente: ${r['customerPhone']} | Pago: ${r['paymentMethod']} | Lugar: ${r['place']}'),
                    trailing: Text(total.toStringAsFixed(2)),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
