// lib/ui/sales_history_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

// Usa tu helper actual. Si tu proyecto expone getDb() en data/db.dart, cámbialo por ese import.
// En tu repo actual lo habitual es data/database.dart con DatabaseHelper y/o getDb().
import '../data/database.dart' as appdb;

class SalesHistoryPage extends StatefulWidget {
  const SalesHistoryPage({super.key});

  @override
  State<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends State<SalesHistoryPage> {
  final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');
  final _qCtrl = TextEditingController();

  // Encabezados de ventas + acarreos (totales) ya calculados
  List<Map<String, dynamic>> _sales = [];
  // Cache de renglones por venta
  final Map<int, List<Map<String, dynamic>>> _itemsBySale = {};

  @override
  void initState() {
    super.initState();
    _load(); // carga inicial sin filtro
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  Future<Database> _db() async {
    // Soporta ambos estilos de helper que has usado en el proyecto
    try {
      // si existe getDb()
      // ignore: unnecessary_await_in_return
      return await appdb.getDb();
    } catch (_) {
      return await appdb.DatabaseHelper.instance.db;
    }
  }

  Future<void> _load({String? q}) async {
    final db = await _db();
    final hasQ = q != null && q.trim().isNotEmpty;
    final like = hasQ ? '%${q!.trim()}%' : null;

    // Filtra por: id (folio), fecha, cliente (phone o name), y producto (sku o name)
    // Nota: CAST(id AS TEXT) para permitir LIKE en el id.
    final heads = await db.rawQuery('''
      SELECT 
        s.id,
        s.customer_phone,
        COALESCE(c.name, '') AS customer_name,
        s.payment_method,
        s.place,
        s.shipping_cost,
        s.discount,
        s.date,
        SUM(si.quantity) AS total_qty,
        SUM(si.quantity * si.unit_price) AS total_amount
      FROM sales s
      LEFT JOIN customers c ON c.phone = s.customer_phone
      LEFT JOIN sale_items si ON si.sale_id = s.id
      LEFT JOIN products p ON p.id = si.product_id
      ${hasQ ? '''
      WHERE 
        CAST(s.id AS TEXT) LIKE ? OR
        s.date LIKE ? OR
        s.customer_phone LIKE ? OR
        COALESCE(c.name,'') LIKE ? OR
        COALESCE(p.sku,'') LIKE ? OR
        COALESCE(p.name,'') LIKE ?
      ''' : ''}
      GROUP BY s.id
      ORDER BY s.date DESC, s.id DESC
    ''', hasQ ? [like, like, like, like, like, like] : []);

    // Cargar renglones para las ventas visibles (para expanders)
    _itemsBySale.clear();
    if (heads.isNotEmpty) {
      final ids = heads.map((e) => e['id'] as int).toList();
      // Para performance, trae todos los renglones de golpe (de las ventas en pantalla)
      final placeholders = List.filled(ids.length, '?').join(',');
      final rows = await db.rawQuery('''
        SELECT si.sale_id, si.quantity, si.unit_price,
               p.sku, p.name
        FROM sale_items si
        JOIN products p ON p.id = si.product_id
        WHERE si.sale_id IN ($placeholders)
        ORDER BY si.sale_id DESC, p.name COLLATE NOCASE
      ''', ids);

      for (final r in rows) {
        final sid = r['sale_id'] as int;
        (_itemsBySale[sid] ??= []).add(r);
      }
    }

    setState(() {
      _sales = heads;
    });
  }

  Future<void> _confirmAndDeleteSale(int saleId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar venta'),
        content: const Text(
          'Esto revertirá el stock de los productos y eliminará la venta.\n\n¿Deseas continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final db = await _db();
      await db.transaction((txn) async {
        // Trae renglones de la venta para revertir existencias
        final items = await txn.rawQuery(
          'SELECT product_id, quantity FROM sale_items WHERE sale_id = ?',
          [saleId],
        );

        // Revertir stock
        for (final it in items) {
          final pid = it['product_id'] as int;
          final qty = (it['quantity'] as num).toInt();
          await txn.rawUpdate(
              'UPDATE products SET stock = COALESCE(stock,0) + ? WHERE id = ?',
              [qty, pid]);
        }

        // Borra renglones y encabezado
        await txn.delete('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
        await txn.delete('sales', where: 'id = ?', whereArgs: [saleId]);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Venta eliminada')),
        );
      }

      // Recargar la lista manteniendo el filtro actual
      _load(q: _qCtrl.text.trim());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error eliminando venta: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Búsqueda
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _qCtrl,
            decoration: InputDecoration(
              labelText: 'Buscar (folio, fecha, cliente o producto)',
              hintText: 'Ej. 120, 2024-10, 5512345678, Ana, SKU123, palomitas',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Buscar',
                icon: const Icon(Icons.manage_search),
                onPressed: () => _load(q: _qCtrl.text.trim()),
              ),
            ),
            onSubmitted: (v) => _load(q: v.trim()),
          ),
        ),
        const SizedBox(height: 4),

        // Lista
        Expanded(
          child: _sales.isEmpty
              ? const Center(child: Text('Sin ventas'))
              : ListView.builder(
                  itemCount: _sales.length,
                  itemBuilder: (_, i) {
                    final s = _sales[i];
                    final sid = s['id'] as int;
                    final phone = (s['customer_phone'] ?? '').toString();
                    final cust = (s['customer_name'] ?? '').toString();
                    final pay = (s['payment_method'] ?? '').toString();
                    final place = (s['place'] ?? '').toString();
                    final date = (s['date'] ?? '').toString();
                    final totalQty = (s['total_qty'] as num?)?.toInt() ?? 0;
                    final totalAmt = (s['total_amount'] as num?)?.toDouble() ?? 0.0;

                    final items = _itemsBySale[sid] ?? const <Map<String, dynamic>>[];

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        title: Text('Folio $sid • $date'),
                        subtitle: Text(
                          [
                            cust.isEmpty ? '(sin nombre)' : cust,
                            phone.isEmpty ? '(s/ teléfono)' : phone,
                            pay.isEmpty ? '(s/ pago)' : 'Pago: $pay',
                            place.isEmpty ? null : 'Lugar: $place',
                            '$totalQty pzas',
                            _money.format(totalAmt),
                          ].where((e) => e != null && e.isNotEmpty).join(' • '),
                        ),
                        trailing: IconButton(
                          tooltip: 'Eliminar venta',
                          icon: const Icon(Icons.delete_forever),
                          onPressed: () => _confirmAndDeleteSale(sid),
                        ),
                        children: [
                          const Divider(height: 1),
                          ...items.map((it) {
                            final sku = (it['sku'] ?? '').toString();
                            final name = (it['name'] ?? '').toString();
                            final q = (it['quantity'] as num?)?.toInt() ?? 0;
                            final unit = (it['unit_price'] as num?)?.toDouble() ?? 0.0;
                            final sub = q * unit;
                            return ListTile(
                              dense: true,
                              title: Text('$sku  $name'),
                              trailing: Text('$q × ${_money.format(unit)}  =  ${_money.format(sub)}'),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}