import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:popperscuv5/data/database.dart' as appdb;

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _searchCtrl = TextEditingController();
  List<Map<String, Object?>> _rows = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_load);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = await appdb.DatabaseHelper.instance.db;
    final q = _searchCtrl.text.trim();
    List<Map<String, Object?>> rows;
    if (q.isEmpty) {
      rows = await db.query('products', orderBy: 'name COLLATE NOCASE');
    } else {
      rows = await db.query(
        'products',
        where: 'sku LIKE ? OR name LIKE ?',
        whereArgs: ['%$q%', '%$q%'],
        orderBy: 'name COLLATE NOCASE',
      );
    }
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar por SKU o nombre…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: _rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = _rows[i];
                return ListTile(
                  title: Text('${r['name']}'),
                  subtitle: Text('SKU: ${r['sku']} • Cat: ${r['category'] ?? ''}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Exist: ${r['stock'] ?? 0}'),
                      Text('PV: ${(r['default_sale_price'] ?? 0).toString()}'),
                    ],
                  ),
                );
              },
            ),
    );
  }
}