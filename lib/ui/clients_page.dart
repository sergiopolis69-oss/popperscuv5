// lib/ui/clients_page.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database.dart' as appdb;

class ClientsPage extends StatefulWidget {
  const ClientsPage({Key? key}) : super(key: key);

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

  // Buscador
  final _qCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];

  // Analytics / ranking
  bool _loadingAnalytics = true;

  // “Volumen” puede ser ventas netas o piezas
  _VolumeMetric _volumeMetric = _VolumeMetric.netSales;

  // peso de utilidad en ranking combinado (0..1). volumen = 1 - profitWeight
  double _profitWeight = 0.60;

  // Listas calculadas (all-time)
  List<_ClientAgg> _topByProfit = [];
  List<_ClientAgg> _topByNetSales = [];
  List<_ClientAgg> _topByQty = [];
  List<_ClientAgg> _combined = [];

  @override
  void initState() {
    super.initState();
    _searchClients(''); // carga inicial lista clientes
    _loadAnalytics(); // carga ranking/reporte
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  Future<Database> _db() async {
    try {
      // ignore: unnecessary_await_in_return
      return await appdb.getDb();
    } catch (_) {
      return await appdb.DatabaseHelper.instance.db;
    }
  }

  // ----------------- DATA (clientes) -----------------

  Future<void> _searchClients(String q) async {
    final db = await _db();
    final like = '%${q.trim()}%';
    final rows = await db.rawQuery('''
      SELECT phone,
             TRIM(COALESCE(name,'')) AS name,
             COALESCE(address,'') AS address
      FROM customers
      WHERE (? = '' OR phone LIKE ? OR name LIKE ? OR address LIKE ?)
      ORDER BY name COLLATE NOCASE
      LIMIT 400
    ''', [q.trim(), like, like, like]);
    setState(() => _results = rows);
  }

  Future<num> _clientTotals(String phone) async {
    final db = await _db();
    final row = await db.rawQuery('''
      SELECT COALESCE(SUM(
        (SELECT COALESCE(SUM(si.quantity*si.unit_price),0) FROM sale_items si WHERE si.sale_id = s.id)
        + COALESCE(s.shipping_cost,0)
        - COALESCE(s.discount,0)
      ),0) AS total
      FROM sales s
      WHERE s.customer_phone = ?
    ''', [phone]);
    return (row.isEmpty ? 0 : (row.first['total'] ?? 0)) as num;
  }

  Future<int> _clientSalesCount(String phone) async {
    final db = await _db();
    final row = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM sales WHERE customer_phone = ?',
      [phone],
    );
    return ((row.isEmpty ? 0 : (row.first['cnt'] ?? 0)) as num).toInt();
  }

  // ----------------- ANALYTICS (Top30 + ranking) -----------------

  Future<void> _loadAnalytics() async {
    if (!_loadingAnalytics) setState(() => _loadingAnalytics = true);

    try {
      final db = await _db();

      // Traemos todas las líneas de ventas con datos necesarios para utilidad.
      // OJO: NO incluimos envío en utilidad. Sí lo acumulamos como informativo.
      final rows = await db.rawQuery('''
        SELECT
          s.id AS sale_id,
          s.customer_phone AS phone,
          COALESCE(c.name,'') AS customer_name,
          COALESCE(s.discount,0) AS sale_discount,
          COALESCE(s.shipping_cost,0) AS shipping_cost,

          si.product_id,
          COALESCE(si.quantity,0) AS quantity,
          COALESCE(si.unit_price,0) AS unit_price,

          COALESCE(p.last_purchase_price,0) AS last_cost
        FROM sales s
        LEFT JOIN customers c ON c.phone = s.customer_phone
        JOIN sale_items si ON si.sale_id = s.id
        LEFT JOIN products p ON p.id = si.product_id
        WHERE s.customer_phone IS NOT NULL AND TRIM(s.customer_phone) <> ''
        ORDER BY s.id DESC
      ''');

      // 1) sumar subtotal por venta para prorratear descuento
      final saleGross = <int, double>{};
      final saleDiscount = <int, double>{};

      for (final r in rows) {
        final sid = (r['sale_id'] as num).toInt();
        final qty = (r['quantity'] as num?)?.toInt() ?? 0;
        final unit = (r['unit_price'] as num?)?.toDouble() ?? 0.0;
        final gross = qty * unit;

        saleGross[sid] = (saleGross[sid] ?? 0.0) + gross;
        saleDiscount[sid] = (r['sale_discount'] as num?)?.toDouble() ?? 0.0;
      }

      // 2) agregar por cliente: piezas, revenue bruto, descuento asignado, netSales, costo, utilidad
      final byClient = <String, _ClientAgg>{};

      for (final r in rows) {
        final sid = (r['sale_id'] as num).toInt();
        final phone = (r['phone'] ?? '').toString();
        if (phone.trim().isEmpty) continue;

        final name = (r['customer_name'] ?? '').toString();
        final qty = (r['quantity'] as num?)?.toInt() ?? 0;
        final unit = (r['unit_price'] as num?)?.toDouble() ?? 0.0;
        final costUnit = (r['last_cost'] as num?)?.toDouble() ?? 0.0;

        final grossLine = qty * unit;
        final grossSale = saleGross[sid] ?? 0.0;
        final discSale = saleDiscount[sid] ?? 0.0;

        // descuento prorrateado por renglón
        final discLine = grossSale > 0 ? discSale * (grossLine / grossSale) : 0.0;

        // costo estimado y utilidad por renglón (sin envío)
        final costLine = qty * costUnit;
        final profitLine = (grossLine - discLine) - costLine;

        final shipping = (r['shipping_cost'] as num?)?.toDouble() ?? 0.0;

        final agg = byClient.putIfAbsent(
          phone,
          () => _ClientAgg(
            phone: phone,
            name: name.trim().isEmpty ? phone : name.trim(),
          ),
        );

        agg.qty += qty;
        agg.grossSales += grossLine;
        agg.discounts += discLine;
        agg.netSales += (grossLine - discLine);
        agg.cost += costLine;
        agg.profit += profitLine;

        // informativo (no afecta utilidad)
        agg.shipping += shipping;
      }

      final all = byClient.values.toList();

      // Listas “puras”
      final topProfit = [...all]..sort((a, b) => b.profit.compareTo(a.profit));
      final topNet = [...all]..sort((a, b) => b.netSales.compareTo(a.netSales));
      final topQty = [...all]..sort((a, b) => b.qty.compareTo(a.qty));

      // Ranking combinado (ponderado con normalización 0..1)
      final maxProfit = topProfit.isNotEmpty ? topProfit.first.profit.abs() : 0.0;
      final maxNet = topNet.isNotEmpty ? topNet.first.netSales : 0.0;
      final maxQty = topQty.isNotEmpty ? topQty.first.qty.toDouble() : 0.0;

      double volumeOf(_ClientAgg a) {
        if (_volumeMetric == _VolumeMetric.netSales) return a.netSales;
        return a.qty.toDouble();
      }

      final maxVolume = _volumeMetric == _VolumeMetric.netSales ? maxNet : maxQty;

      for (final a in all) {
        final pNorm = (maxProfit <= 0) ? 0.0 : (a.profit / maxProfit).clamp(-1.0, 1.0);
        final vNorm = (maxVolume <= 0) ? 0.0 : (volumeOf(a) / maxVolume).clamp(0.0, 1.0);

        // OJO: utilidad puede ser negativa; para ranking combinado, si es negativa, castiga.
        // pNorm ya queda en [-1..1]. Se pondera directo.
        a.score = (_profitWeight * pNorm) + ((1.0 - _profitWeight) * vNorm);
      }

      final combined = [...all]..sort((a, b) => b.score.compareTo(a.score));

      if (!mounted) return;
      setState(() {
        _topByProfit = topProfit;
        _topByNetSales = topNet;
        _topByQty = topQty;
        _combined = combined;
        _loadingAnalytics = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingAnalytics = false);
      }
    }
  }

  // ----------------- EXPORT EXCEL -----------------

  Future<void> _exportTop30Excel() async {
    try {
      final excel = Excel.createExcel();
      excel.delete('Sheet1');

      final now = DateTime.now();
      final ts = DateFormat('yyyyMMdd_HHmm').format(now);

      final topProfit = _topByProfit.take(30).toList();
      final topVol = (_volumeMetric == _VolumeMetric.netSales ? _topByNetSales : _topByQty).take(30).toList();
      final topCombined = _combined.take(30).toList();

      void writeSheet(String name, List<_ClientAgg> rows) {
        final sheet = excel[name];

        // Header
        sheet.appendRow([
          TextCellValue('Rank'),
          TextCellValue('Cliente'),
          TextCellValue('Teléfono'),
          TextCellValue('Piezas'),
          TextCellValue('Ventas brutas'),
          TextCellValue('Descuentos'),
          TextCellValue('Ventas netas'),
          TextCellValue('Costo estimado'),
          TextCellValue('Utilidad'),
          TextCellValue('Margen %'),
          TextCellValue('Envío (info)'),
          TextCellValue('Score (si aplica)'),
        ]);

        for (int i = 0; i < rows.length; i++) {
          final a = rows[i];
          final margin = a.netSales > 0 ? (a.profit / a.netSales) : 0.0;

          sheet.appendRow([
            IntCellValue(i + 1),
            TextCellValue(a.name),
            TextCellValue(a.phone),
            IntCellValue(a.qty),
            DoubleCellValue(a.grossSales),
            DoubleCellValue(a.discounts),
            DoubleCellValue(a.netSales),
            DoubleCellValue(a.cost),
            DoubleCellValue(a.profit),
            DoubleCellValue(margin * 100),
            DoubleCellValue(a.shipping),
            DoubleCellValue(a.score),
          ]);
        }
      }

      writeSheet('Top 30 Utilidad', topProfit);
      writeSheet(_volumeMetric == _VolumeMetric.netSales ? 'Top 30 VentasNetas' : 'Top 30 Piezas', topVol);
      writeSheet('Ranking Combinado', topCombined);

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/reporte_clientes_$ts.xlsx');
      final bytes = excel.encode();
      if (bytes == null) {
        _snack('No se pudo generar el archivo Excel');
        return;
      }
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Reporte clientes (Top 30)',
        text:
            'Reporte generado: Top 30 por utilidad, Top 30 por volumen y Ranking combinado.\n'
            'Volumen: ${_volumeMetric == _VolumeMetric.netSales ? 'Ventas netas' : 'Piezas'}\n'
            'Peso utilidad: ${(100 * _profitWeight).toStringAsFixed(0)}%',
      );
    } catch (e) {
      _snack('Error exportando Excel: $e');
    }
  }

  // ----------------- IMPORTAR 1 CONTACTO -----------------

  Future<void> _importOneFromContacts() async {
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        _snack('Permiso de contactos denegado');
        return;
      }

      final picked = await FlutterContacts.openExternalPick();
      if (picked == null) {
        _snack('No seleccionaste contacto');
        return;
      }

      final full = await FlutterContacts.getContact(
        picked.id,
        withProperties: true,
        withAccounts: false,
      );
      if (full == null) {
        _snack('No fue posible leer el contacto');
        return;
      }

      final phoneRaw = _firstPhone(full);
      if (phoneRaw == null || phoneRaw.isEmpty) {
        _snack('El contacto no tiene teléfono');
        return;
      }

      final phone = _normalizePhone(phoneRaw);
      final name = (full.displayName ?? '').trim();
      final addr = '';

      await _confirmAddClient(prePhone: phone, preName: name, preAddr: addr);
    } catch (e) {
      _snack('Error importando contacto: $e');
    }
  }

  String? _firstPhone(Contact c) {
    if (c.phones.isEmpty) return null;
    return c.phones.first.number?.trim() ?? '';
  }

  String _normalizePhone(String raw) {
    return raw.replaceAll(RegExp(r'[\s\-\(\)\.\+]'), '');
  }

  // ----------------- CRUD CLIENTE -----------------

  Future<void> _confirmAddClient({
    String prePhone = '',
    String preName = '',
    String preAddr = '',
  }) async {
    final phoneCtrl = TextEditingController(text: prePhone);
    final nameCtrl = TextEditingController(text: preName);
    final addrCtrl = TextEditingController(text: preAddr);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Agregar cliente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono (ID) *'),
            ),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
            TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: 'Dirección')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;

    final phone = _normalizePhone(phoneCtrl.text.trim());
    if (phone.isEmpty) {
      _snack('El teléfono (ID) es obligatorio');
      return;
    }

    final name = nameCtrl.text.trim();
    final addr = addrCtrl.text.trim();

    try {
      final db = await _db();
      await db.insert(
        'customers',
        {'phone': phone, 'name': name, 'address': addr},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      _snack('Cliente guardado');
      await _searchClients(_qCtrl.text);
      await _loadAnalytics(); // refrescar ranking
    } catch (e) {
      _snack('Error al guardar: $e');
    }
  }

  Future<void> _editClient(Map<String, dynamic> c) async {
    final phone = (c['phone'] ?? '').toString();
    final nameCtrl = TextEditingController(text: (c['name'] ?? '').toString());
    final addrCtrl = TextEditingController(text: (c['address'] ?? '').toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Editar cliente $phone'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(enabled: false, decoration: InputDecoration(labelText: 'Teléfono (ID)', hintText: phone)),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
            TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: 'Dirección')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar cambios')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final db = await _db();
      await db.update(
        'customers',
        {'name': nameCtrl.text.trim(), 'address': addrCtrl.text.trim()},
        where: 'phone = ?',
        whereArgs: [phone],
      );

      _snack('Cliente actualizado');
      await _searchClients(_qCtrl.text);
      await _loadAnalytics(); // refrescar ranking
    } catch (e) {
      _snack('Error al actualizar: $e');
    }
  }

  Future<void> _deleteClient(Map<String, dynamic> c) async {
    final phone = (c['phone'] ?? '').toString();
    final tot = await _clientTotals(phone);
    final cnt = await _clientSalesCount(phone);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: Text(
          'Se eliminará el cliente ${c['name'] ?? phone}.\n'
          'Ventas registradas: $cnt por ${_money.format((tot).toDouble())}.\n\n'
          'Nota: las ventas históricas no se modifican.',
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
      await db.delete('customers', where: 'phone = ?', whereArgs: [phone]);
      _snack('Cliente eliminado');
      await _searchClients(_qCtrl.text);
      await _loadAnalytics(); // refrescar ranking
    } catch (e) {
      _snack('Error al eliminar: $e');
    }
  }

  // ----------------- HISTORIAL -----------------

  Future<void> _showClientHistory(String phone, String name) async {
    final db = await _db();
    final heads = await db.rawQuery('''
      SELECT id, date, payment_method, place,
             COALESCE(shipping_cost,0) AS shipping_cost,
             COALESCE(discount,0) AS discount
      FROM sales
      WHERE customer_phone = ?
      ORDER BY date DESC, id DESC
    ''', [phone]);

    final items = await db.rawQuery('''
      SELECT si.sale_id, p.sku, p.name, si.quantity, si.unit_price
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN products p ON p.id = si.product_id
      WHERE s.customer_phone = ?
      ORDER BY si.sale_id DESC, p.name COLLATE NOCASE
    ''', [phone]);

    final bySale = <int, List<Map<String, dynamic>>>{};
    for (final it in items) {
      bySale.putIfAbsent(it['sale_id'] as int, () => []).add(it);
    }

    // ignore: use_build_context_synchronously
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Historial de ventas de $name', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Expanded(
                child: heads.isEmpty
                    ? const Center(child: Text('Sin ventas registradas'))
                    : ListView.separated(
                        itemCount: heads.length,
                        separatorBuilder: (_, __) => const Divider(height: 16),
                        itemBuilder: (_, i) {
                          final h = heads[i];
                          final saleId = h['id'] as int;
                          final its = bySale[saleId] ?? const [];
                          final itemsTotal = its.fold<double>(
                            0.0,
                            (a, b) => a + (b['quantity'] as int) * (b['unit_price'] as num).toDouble(),
                          );
                          final qtyTotal = its.fold<int>(0, (a, b) => a + (b['quantity'] as int));
                          final shipping = (h['shipping_cost'] as num).toDouble();
                          final discount = (h['discount'] as num).toDouble();
                          final grand = itemsTotal + shipping - discount;

                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Venta #$saleId • ${h['date']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text('Pago: ${h['payment_method'] ?? '(s/d)'} • Lugar: ${h['place'] ?? '(s/d)'}'),
                                  const SizedBox(height: 8),
                                  ...its.map(
                                    (it) => ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      title: Text('${it['sku']}  ${it['name']}'),
                                      trailing: Text('${it['quantity']} × ${_money.format((it['unit_price'] as num).toDouble())}'),
                                    ),
                                  ),
                                  const Divider(),
                                  Row(
                                    children: [
                                      Expanded(child: Text('Pzas: $qtyTotal')),
                                      Expanded(child: Text('Artículos: ${_money.format(itemsTotal)}')),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Expanded(child: Text('Envío: ${_money.format(shipping)}')),
                                      Expanded(child: Text('Descuento: -${_money.format(discount)}')),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Text('Total: ${_money.format(grand)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------- UI -----------------

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final volumeLabel = _volumeMetric == _VolumeMetric.netSales ? 'Ventas netas' : 'Piezas';
    final weightPct = (100 * _profitWeight).round();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: [
          IconButton(
            tooltip: 'Exportar Excel (Top 30)',
            onPressed: _loadingAnalytics ? null : _exportTop30Excel,
            icon: const Icon(Icons.table_view),
          ),
          IconButton(
            tooltip: 'Importar 1 contacto',
            onPressed: _importOneFromContacts,
            icon: const Icon(Icons.contact_phone),
          ),
          IconButton(
            tooltip: 'Agregar cliente',
            onPressed: () => _confirmAddClient(),
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Reporte / Ranking (sustituye Top 10)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _loadingAnalytics
                      ? const SizedBox(
                          height: 90,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Ranking de clientes (Top 30) • $volumeLabel',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Actualizar ranking',
                                  onPressed: _loadAnalytics,
                                  icon: const Icon(Icons.refresh),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),

                            // Controles de ponderación
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<_VolumeMetric>(
                                    value: _volumeMetric,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      labelText: 'Volumen',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: _VolumeMetric.netSales,
                                        child: Text('Ventas netas'),
                                      ),
                                      DropdownMenuItem(
                                        value: _VolumeMetric.qty,
                                        child: Text('Piezas'),
                                      ),
                                    ],
                                    onChanged: (v) async {
                                      if (v == null) return;
                                      setState(() => _volumeMetric = v);
                                      await _loadAnalytics();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Peso utilidad: $weightPct%'),
                                      Slider(
                                        value: _profitWeight,
                                        min: 0.0,
                                        max: 1.0,
                                        divisions: 20,
                                        label: '$weightPct%',
                                        onChanged: (v) => setState(() => _profitWeight = v),
                                        onChangeEnd: (_) => _loadAnalytics(),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            // Preview top combinado
                            const Text(
                              'Top combinado (preview)',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),

                            if (_combined.isEmpty)
                              const Text('Sin datos suficientes (necesitas ventas).')
                            else
                              Column(
                                children: _combined.take(8).map((a) {
                                  final margin = a.netSales > 0 ? (a.profit / a.netSales) : 0.0;
                                  final vol = _volumeMetric == _VolumeMetric.netSales ? a.netSales : a.qty.toDouble();

                                  return ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      child: Text('${_combined.indexOf(a) + 1}'),
                                    ),
                                    title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: Text(
                                      '${a.phone} • '
                                      'Util: ${_money.format(a.profit)} • '
                                      'Margen ${(margin * 100).toStringAsFixed(1)}% • '
                                      '${volumeLabel}: ${_volumeMetric == _VolumeMetric.netSales ? _money.format(vol) : vol.toInt()}',
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _showClientHistory(a.phone, a.name),
                                  );
                                }).toList(),
                              ),

                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: _exportTop30Excel,
                                icon: const Icon(Icons.download),
                                label: const Text('Exportar Excel (Top 30)'),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),

          // Buscador
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: TextField(
                controller: _qCtrl,
                decoration: InputDecoration(
                  hintText: 'Buscar cliente (teléfono, nombre o dirección)…',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                  suffixIcon: _qCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _qCtrl.clear();
                            _searchClients('');
                          },
                          icon: const Icon(Icons.clear),
                        ),
                ),
                onChanged: _searchClients,
                onSubmitted: _searchClients,
              ),
            ),
          ),

          // Resultados
          if (_results.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 24, 12, 24),
                child: Text('No hay clientes'),
              ),
            )
          else
            SliverList.separated(
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 0),
              itemBuilder: (_, i) {
                final c = _results[i];
                final name = (c['name'] ?? '') as String;
                final phone = (c['phone'] ?? '') as String;
                final addr = (c['address'] ?? '') as String;

                return ListTile(
                  title: Text(name.isEmpty ? '(sin nombre)' : name),
                  subtitle: Text([phone, if (addr.isNotEmpty) addr].join(' • ')),
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  onTap: () async {
                    final total = await _clientTotals(phone);
                    final cnt = await _clientSalesCount(phone);
                    if (!mounted) return;

                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name.isEmpty ? phone : name, style: Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 6),
                              Text([phone, if (addr.isNotEmpty) addr].join(' • ')),
                              const Divider(height: 20),
                              Row(
                                children: [
                                  Expanded(child: _kv('Ventas registradas', '$cnt')),
                                  Expanded(child: _kv('Total histórico', _money.format((total).toDouble()))),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    icon: const Icon(Icons.history),
                                    label: const Text('Ver historial'),
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      _showClientHistory(phone, name.isEmpty ? phone : name);
                                    },
                                  ),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.edit),
                                    label: const Text('Editar'),
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      _editClient(c);
                                    },
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Eliminar'),
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      _deleteClient(c);
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _confirmAddClient(),
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo'),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(k, style: const TextStyle(fontWeight: FontWeight.w500))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

enum _VolumeMetric { netSales, qty }

class _ClientAgg {
  _ClientAgg({
    required this.phone,
    required this.name,
  });

  final String phone;
  final String name;

  int qty = 0;

  double grossSales = 0.0; // sum(qty*unit_price)
  double discounts = 0.0; // descuento prorrateado por renglón
  double netSales = 0.0; // gross - discounts
  double cost = 0.0; // qty*last_purchase_price
  double profit = 0.0; // (gross - discounts) - cost

  double shipping = 0.0; // informativo

  double score = 0.0; // ranking combinado
}