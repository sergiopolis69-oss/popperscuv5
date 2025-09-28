import 'package:flutter/material.dart';
import '../repositories/sales_repository.dart';
import 'package:intl/intl.dart';

class SalesHistoryPage extends StatefulWidget {
  const SalesHistoryPage({super.key});
  @override
  State<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends State<SalesHistoryPage> {
  final _repo = SalesRepository();
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to   = DateTime.now();
  List<Map<String,dynamic>> _sales = [];

  Future<void> _load() async {
    final r = await _repo.salesBetween(_from, _to);
    setState(()=> _sales = r);
  }

  Future<void> _pickFrom() async {
    final d = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDate: _from);
    if (d!=null) { setState(()=>_from = d); _load(); }
  }
  Future<void> _pickTo() async {
    final d = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDate: _to);
    if (d!=null) { setState(()=>_to = d); _load(); }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd HH:mm');
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _pickFrom, icon: const Icon(Icons.calendar_today), label: Text('Desde: ${DateFormat('yyyy-MM-dd').format(_from)}'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: _pickTo, icon: const Icon(Icons.calendar_today_outlined), label: Text('Hasta: ${DateFormat('yyyy-MM-dd').format(_to)}'))),
          ]),
          const SizedBox(height: 12),
          Expanded(child: ListView.separated(
            itemBuilder: (_,i){
              final s = _sales[i];
              return ListTile(
                title: Text('Venta #${s['id']} ${df.format(DateTime.parse(s['date'] as String))}'),
                subtitle: Text('Pago: ${s['payment_method'] ?? ''}  Envío: ${s['shipping_cost']}  Desc: ${s['discount']}'),
              );
            },
            separatorBuilder: (_,__)=>const Divider(height: 1),
            itemCount: _sales.length,
          ))
        ],
      ),
    );
  }
}
