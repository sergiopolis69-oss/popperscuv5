// lib/ui/clients_page.dart
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

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

  // Analítica (top 30 + ranking combinado)
  bool _loadingAnalytics = false;
  List<Map<String, dynamic>> _topProfit = []; // phone, name, profit, net_sales, qty, sales_count
  List<Map<String, dynamic>> _topVolume = []; // phone, name, volume_value, net_sales, qty, profit, sales_count
  List<Map<String, dynamic>> _combined = []; // phone, name, score, profit, net_sales, qty, sales_count

  // Controles
  double _profitWeight = 0.60; // 60% utilidad, 40% volumen
  _VolumeMetric _volumeMetric = _VolumeMetric.netSales;

  // Periodo para analytics
  _PeriodPreset _preset = _PeriodPreset.d30;
  DateTime? _from; // inclusivo
  DateTime? _to; // inclusivo

  @override
  void initState() {
    super.initState();
    _applyPreset(_PeriodPreset.d30); // default: últimos 30 días
    _searchClients(''); // carga inicial
    _loadAnalytics();
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

  // ----------------- Helpers periodo -----------------

  String _fmtDay(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  void _applyPreset(_PeriodPreset p) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    DateTime? f;
    DateTime? t;

    switch (p) {
      case _PeriodPreset.d7:
        f = today.subtract(const Duration(days: 6));
        t = today;
        break;
      case _PeriodPreset.d30:
        f = today.subtract(const Duration(days: 29));
        t = today;
        break;
      case _PeriodPreset.d60:
        f = today.subtract(const Duration(days: 59));
        t = today;
        break;
      case _PeriodPreset.d90:
        f = today.subtract(const Duration(days: 89));
        t = today;
        break;
      case _PeriodPreset.y1:
        f = DateTime(today.year - 1, today.month, today.day);
        t = today;
        break;
      case _PeriodPreset.all:
        f = null;
        t = null;
        break;
      case _PeriodPreset.custom:
        // se setea en _pickRange()
        break;
    }

    setState(() {
      _preset = p;
      _from = f;
      _to = t;
    });
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final initStart = _from ?? today.subtract(const Duration(days: 29));
    final initEnd = _to ?? today;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: DateTimeRange(start: initStart, end: initEnd),
    );

    if (picked == null) return;

    setState(() {
      _preset = _PeriodPreset.custom;
      _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });

    await _loadAnalytics();
  }

  String _periodLabel() {
    if (_preset == _PeriodPreset.all) return 'Todo';
    if (_preset == _PeriodPreset.custom && _from != null && _to != null) {
      return '${DateFormat('dd/MM/yyyy').format(_from!)} — ${DateFormat('dd/MM/yyyy').format(_to!)}';
    }
    if (_from != null && _to != null) {
      return '${DateFormat('dd/MM').format(_from!)} — ${DateFormat('dd/MM').format(_to!)}';
    }
    return 'Todo';
  }

  // ----------------- DATA: búsqueda clientes -----------------

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
    final row = await db.rawQuery('SELECT COUNT(*) AS cnt FROM sales WHERE customer_phone = ?', [phone]);
    return ((row.isEmpty ? 0 : (row.first['cnt'] ?? 0)) as num).toInt();
  }

  // ----------------- DATA: analytics ranking -----------------

  Future<void> _loadAnalytics() async {
    if (!mounted) return;
    setState(() => _loadingAnalytics = true);

    try {
      final db = await _db();

      final hasRange = (_preset != _PeriodPreset.all) && _from != null && _to != null;
      final whereDate = hasRange ? 'AND DATE(s.date) BETWEEN ? AND ?' : '';
      final args = <Object?>[];
      if (hasRange) {
        args.add(_fmtDay(_from!));
        args.add(_fmtDay(_to!));
      }

      // Traemos por renglón para repartir descuento proporcional por venta
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
        $whereDate
        ORDER BY s.id DESC
      ''', args);

      // 1) Agrupar por sale_id para poder distribuir el descuento de esa venta proporcional al subtotal de items
      final saleGroups = <int, List<Map<String, dynamic>>>{};
      final saleMeta = <int, Map<String, dynamic>>{};

      for (final r in rows) {
        final sid = (r['sale_id'] as num).toInt();
        saleGroups.putIfAbsent(sid, () => []).add(r);

        saleMeta.putIfAbsent(sid, () {
          return {
            'phone': (r['phone'] ?? '').toString(),
            'name': (r['customer_name'] ?? '').toString(),
            'discount': (r['sale_discount'] as num?)?.toDouble() ?? 0.0,
            'shipping': (r['shipping_cost'] as num?)?.toDouble() ?? 0.0,
          };
        });
      }

      // 2) Consolidar por cliente:
      // - net_sales (items - descuentos)
      // - qty
      // - profit (net_sales - cost)
      // - sales_count
      final byClient = <String, Map<String, dynamic>>{};
      final salesSeenByClient = <String, Set<int>>{};

      for (final entry in saleGroups.entries) {
        final sid = entry.key;
        final items = entry.value;
        final meta = saleMeta[sid] ?? const <String, dynamic>{};

        final phone = (meta['phone'] ?? '').toString();
        if (phone.trim().isEmpty) continue;

        final name = (meta['name'] ?? '').toString();
        final saleDiscount = (meta['discount'] as num?)?.toDouble() ?? 0.0;

        final itemsSubtotal = items.fold<double>(
          0.0,
          (sum, it) =>
              sum + ((it['quantity'] as num?)?.toInt() ?? 0) * ((it['unit_price'] as num?)?.toDouble() ?? 0.0),
        );

        // Por cada línea: repartir descuento proporcional al gross de la línea
        double saleNet = 0.0;
        double saleCost = 0.0;
        int saleQty = 0;

        for (final it in items) {
          final qty = (it['quantity'] as num?)?.toInt() ?? 0;
          final unit = (it['unit_price'] as num?)?.toDouble() ?? 0.0;
          final costUnit = (it['last_cost'] as num?)?.toDouble() ?? 0.0;

          final lineGross = qty * unit;
          final lineDiscount = itemsSubtotal > 0 ? saleDiscount * (lineGross / itemsSubtotal) : 0.0;

          final lineNet = (lineGross - lineDiscount).clamp(0.0, double.infinity);
          final lineCost = qty * costUnit;

          saleNet += lineNet;
          saleCost += lineCost;
          saleQty += qty;
        }

        final saleProfit = saleNet - saleCost;

        final agg = byClient.putIfAbsent(phone, () {
          return {
            'phone': phone,
            'name': name.isEmpty ? phone : name,
            'net_sales': 0.0,
            'qty': 0,
            'profit': 0.0,
            'sales_count': 0,
          };
        });

        agg['net_sales'] = (agg['net_sales'] as double) + saleNet;
        agg['profit'] = (agg['profit'] as double) + saleProfit;
        agg['qty'] = (agg['qty'] as int) + saleQty;

        final seen = salesSeenByClient.putIfAbsent(phone, () => <int>{});
        if (!seen.contains(sid)) {
          seen.add(sid);
          agg['sales_count'] = (agg['sales_count'] as int) + 1;
        }
      }

      final allClients = byClient.values.toList();

      // Top 30 por utilidad
      final topProfit = [...allClients]
        ..sort((a, b) => ((b['profit'] as double).compareTo(a['profit'] as double)));
      final topProfit30 = topProfit.take(30).toList();

      // Top 30 por volumen (ventas netas o piezas)
      final topVolume = [...allClients]
        ..sort((a, b) {
          final av = _volumeMetric == _VolumeMetric.netSales ? (a['net_sales'] as double) : (a['qty'] as int).toDouble();
          final bv = _volumeMetric == _VolumeMetric.netSales ? (b['net_sales'] as double) : (b['qty'] as int).toDouble();
          return bv.compareTo(av);
        });
      final topVolume30 = topVolume.take(30).map((m) {
        final volumeVal = _volumeMetric == _VolumeMetric.netSales ? (m['net_sales'] as double) : (m['qty'] as int).toDouble();
        return {
          ...m,
          'volume_value': volumeVal,
        };
      }).toList();

      // Ranking combinado: normalizar (0..1) utilidad y volumen, score = w*profit + (1-w)*volume
      double maxProfit = 0.0;
      double maxVol = 0.0;
      for (final c in allClients) {
        final p = (c['profit'] as double);
        final v = _volumeMetric == _VolumeMetric.netSales ? (c['net_sales'] as double) : (c['qty'] as int).toDouble();
        if (p > maxProfit) maxProfit = p;
        if (v > maxVol) maxVol = v;
      }

      final combined = allClients.map((c) {
        final p = (c['profit'] as double);
        final v = _volumeMetric == _VolumeMetric.netSales ? (c['net_sales'] as double) : (c['qty'] as int).toDouble();

        final pNorm = maxProfit <= 0 ? 0.0 : (p / maxProfit).clamp(0.0, 1.0);
        final vNorm = maxVol <= 0 ? 0.0 : (v / maxVol).clamp(0.0, 1.0);

        final score = _profitWeight * pNorm + (1.0 - _profitWeight) * vNorm;

        return {
          ...c,
          'score': score,
          'volume_value': v,
        };
      }).toList()
        ..sort((a, b) => ((b['score'] as double).compareTo(a['score'] as double)));

      final combined30 = combined.take(30).toList();

      if (!mounted) return;
      setState(() {
        _topProfit = topProfit30;
        _topVolume = topVolume30;
        _combined = combined30;
      });
    } catch (e) {
      if (!mounted) return;
      _snack('Error cargando ranking: $e');
    } finally {
      if (mounted) setState(() => _loadingAnalytics = false);
    }
  }

  // ----------------- EXPORTAR EXCEL -----------------

  Future<void> _exportTop30Excel() async {
    try {
      final excel = Excel.createExcel();
      excel.delete('Sheet1');

      // Hoja 1: Ranking combinado
      final s1 = excel['Ranking_Combinado'];
      s1.appendRow([
        TextCellValue('Rank'),
        TextCellValue('Cliente'),
        TextCellValue('Teléfono'),
        TextCellValue('Score'),
        TextCellValue('Utilidad'),
        TextCellValue('Ventas netas'),
        TextCellValue('Piezas'),
        TextCellValue('Ventas (conteo)'),
        TextCellValue('Periodo'),
        TextCellValue('Volumen usado'),
        TextCellValue('Peso utilidad'),
      ]);

      for (int i = 0; i < _combined.length; i++) {
        final r = _combined[i];
        s1.appendRow([
          IntCellValue(i + 1),
          TextCellValue((r['name'] ?? '').toString()),
          TextCellValue((r['phone'] ?? '').toString()),
          DoubleCellValue(((r['score'] as num?)?.toDouble() ?? 0.0)),
          DoubleCellValue(((r['profit'] as num?)?.toDouble() ?? 0.0)),
          DoubleCellValue(((r['net_sales'] as num?)?.toDouble() ?? 0.0)),
          IntCellValue(((r['qty'] as num?)?.toInt() ?? 0)),
          IntCellValue(((r['sales_count'] as num?)?.toInt() ?? 0)),
          TextCellValue(_periodLabel()),
          TextCellValue(_volumeMetric == _VolumeMetric.netSales ? 'Ventas netas' : 'Piezas'),
          TextCellValue('${(100 * _profitWeight).toStringAsFixed(0)}%'),
        ]);
      }

      // Hoja 2: Top utilidad
      final s2 = excel['Top30_Utilidad'];
      s2.appendRow([
        TextCellValue('Rank'),
        TextCellValue('Cliente'),
        TextCellValue('Teléfono'),
        TextCellValue('Utilidad'),
        TextCellValue('Ventas netas'),
        TextCellValue('Piezas'),
        TextCellValue('Ventas (conteo)'),
        TextCellValue('Periodo'),
      ]);

      for (int i = 0; i < _topProfit.length; i++) {
        final r = _topProfit[i];
        s2.appendRow([
          IntCellValue(i + 1),
          TextCellValue((r['name'] ?? '').toString()),
          TextCellValue((r['phone'] ?? '').toString()),
          DoubleCellValue(((r['profit'] as num?)?.toDouble() ?? 0.0)),
          DoubleCellValue(((r['net_sales'] as num?)?.toDouble() ?? 0.0)),
          IntCellValue(((r['qty'] as num?)?.toInt() ?? 0)),
          IntCellValue(((r['sales_count'] as num?)?.toInt() ?? 0)),
          TextCellValue(_periodLabel()),
        ]);
      }

      // Hoja 3: Top volumen
      final s3 = excel['Top30_Volumen'];
      s3.appendRow([
        TextCellValue('Rank'),
        TextCellValue('Cliente'),
        TextCellValue('Teléfono'),
        TextCellValue(_volumeMetric == _VolumeMetric.netSales ? 'Ventas netas' : 'Piezas'),
        TextCellValue('Utilidad'),
        TextCellValue('Ventas netas'),
        TextCellValue('Piezas'),
        TextCellValue('Ventas (conteo)'),
        TextCellValue('Periodo'),
      ]);

      for (int i = 0; i < _topVolume.length; i++) {
        final r = _topVolume[i];
        s3.appendRow([
          IntCellValue(i + 1),
          TextCellValue((r['name'] ?? '').toString()),
          TextCellValue((r['phone'] ?? '').toString()),
          DoubleCellValue(((r['volume_value'] as num?)?.toDouble() ?? 0.0)),
          DoubleCellValue(((r['profit'] as num?)?.toDouble() ?? 0.0)),
          DoubleCellValue(((r['net_sales'] as num?)?.toDouble() ?? 0.0)),
          IntCellValue(((r['qty'] as num?)?.toInt() ?? 0)),
          IntCellValue(((r['sales_count'] as num?)?.toInt() ?? 0)),
          TextCellValue(_periodLabel()),
        ]);
      }

      // Guardar en temp y compartir
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/reporte_clientes_top30.xlsx');
      final bytes = excel.encode();
      if (bytes == null) throw Exception('No se pudo generar el archivo Excel');
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Reporte Top 30 Clientes',
        text:
            'Reporte generado: Top 30 por utilidad, Top 30 por volumen y Ranking combinado.\n'
            'Periodo: ${_periodLabel()}\n'
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

      // Abre el picker nativo (1 contacto)
      final picked = await FlutterContacts.openExternalPick();
      if (picked == null) {
        _snack('No seleccionaste contacto');
        return;
      }

      final full = await FlutterContacts.getContact(picked.id, withProperties: true, withAccounts: false);
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
      final addr = ''; // Si quieres, puedes mapear postalAddresses aquí

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
    // Quita espacios, -, (), ., +
    return raw.replaceAll(RegExp(r'[\s\-\(\)\.\+]'), '');
  }

  // ----------------- CRUD CLIENTE -----------------

  Future<void> _confirmAddClient({String prePhone = '', String preName = '', String preAddr = ''}) async {
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
      await db.insert('customers', {
        'phone': phone,
        'name': name,
        'address': addr,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      _snack('Cliente guardado');
      await _searchClients(_qCtrl.text);
      await _loadAnalytics();
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
      await db.update('customers', {
        'name': nameCtrl.text.trim(),
        'address': addrCtrl.text.trim(),
      }, where: 'phone = ?', whereArgs: [phone]);

      _snack('Cliente actualizado');
      await _searchClients(_qCtrl.text);
      await _loadAnalytics();
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
      await _loadAnalytics();
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
                          final saleId = (h['id'] as num).toInt();
                          final its = bySale[saleId] ?? const [];
                          final itemsTotal = its.fold<double>(
                            0.0,
                            (a, b) => a + ((b['quantity'] as num?)?.toInt() ?? 0) * ((b['unit_price'] as num?)?.toDouble() ?? 0.0),
                          );
                          final qtyTotal = its.fold<int>(0, (a, b) => a + ((b['quantity'] as num?)?.toInt() ?? 0));
                          final shipping = (h['shipping_cost'] as num?)?.toDouble() ?? 0.0;
                          final discount = (h['discount'] as num?)?.toDouble() ?? 0.0;
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
                                      trailing: Text(
                                        '${it['quantity']} × ${_money.format(((it['unit_price'] as num?)?.toDouble() ?? 0.0))}',
                                      ),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: [
          IconButton(
            tooltip: 'Exportar Top 30 (Excel)',
            onPressed: (_combined.isEmpty && _topProfit.isEmpty && _topVolume.isEmpty) ? null : _exportTop30Excel,
            icon: const Icon(Icons.download),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Ranking periodo: ${_periodLabel()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          // Ranking / Top 30
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Ranking de clientes (Top 30)',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Actualizar ranking',
                            onPressed: _loadAnalytics,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Periodo: ${_periodLabel()}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Elegir rango',
                            onPressed: _pickRange,
                            icon: const Icon(Icons.calendar_month),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('7D'),
                            selected: _preset == _PeriodPreset.d7,
                            onSelected: (_) async {
                              _applyPreset(_PeriodPreset.d7);
                              await _loadAnalytics();
                            },
                          ),
                          ChoiceChip(
                            label: const Text('30D'),
                            selected: _preset == _PeriodPreset.d30,
                            onSelected: (_) async {
                              _applyPreset(_PeriodPreset.d30);
                              await _loadAnalytics();
                            },
                          ),
                          ChoiceChip(
                            label: const Text('60D'),
                            selected: _preset == _PeriodPreset.d60,
                            onSelected: (_) async {
                              _applyPreset(_PeriodPreset.d60);
                              await _loadAnalytics();
                            },
                          ),
                          ChoiceChip(
                            label: const Text('90D'),
                            selected: _preset == _PeriodPreset.d90,
                            onSelected: (_) async {
                              _applyPreset(_PeriodPreset.d90);
                              await _loadAnalytics();
                            },
                          ),
                          ChoiceChip(
                            label: const Text('1A'),
                            selected: _preset == _PeriodPreset.y1,
                            onSelected: (_) async {
                              _applyPreset(_PeriodPreset.y1);
                              await _loadAnalytics();
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Todo'),
                            selected: _preset == _PeriodPreset.all,
                            onSelected: (_) async {
                              _applyPreset(_PeriodPreset.all);
                              await _loadAnalytics();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<_VolumeMetric>(
                              value: _volumeMetric,
                              decoration: const InputDecoration(
                                isDense: true,
                                labelText: 'Volumen para ranking',
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
                                Text(
                                  'Peso utilidad: ${(100 * _profitWeight).toStringAsFixed(0)}%',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                Slider(
                                  value: _profitWeight,
                                  min: 0,
                                  max: 1,
                                  divisions: 10,
                                  label: '${(100 * _profitWeight).toStringAsFixed(0)}%',
                                  onChanged: (v) => setState(() => _profitWeight = v),
                                  onChangeEnd: (_) => _loadAnalytics(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_loadingAnalytics)
                        const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
                      else if (_combined.isEmpty)
                        const Text('No hay ventas en el periodo seleccionado.')
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Ranking combinado (Top 10)', style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _combined.take(10).map((c) {
                                final profit = (c['profit'] as num?)?.toDouble() ?? 0.0;
                                final net = (c['net_sales'] as num?)?.toDouble() ?? 0.0;
                                final qty = (c['qty'] as num?)?.toInt() ?? 0;
                                final label = (c['name'] ?? c['phone']).toString();
                                final phone = (c['phone'] ?? '').toString();

                                final subtitle = _volumeMetric == _VolumeMetric.netSales
                                    ? 'Util ${_money.format(profit)} • Net ${_money.format(net)}'
                                    : 'Util ${_money.format(profit)} • $qty pzas';

                                return ActionChip(
                                  avatar: const Icon(Icons.leaderboard, size: 18),
                                  label: Text('$label • $subtitle'),
                                  onPressed: () => _showClientHistory(phone, label),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.download),
                                    label: const Text('Exportar Excel Top 30'),
                                    onPressed: _exportTop30Excel,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Incluye: Ranking combinado, Top 30 por utilidad y Top 30 por volumen.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
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

                    // BottomSheet de acciones + resumen
                    // ignore: use_build_context_synchronously
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

enum _PeriodPreset { d7, d30, d60, d90, y1, all, custom }
```0