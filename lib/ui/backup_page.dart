// lib/ui/backup_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/xlsx_io.dart';
import '../utils/db_file_io.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;
  String? _lastBackupPath;
  final _restoreCtrl = TextEditingController();

  @override
  void dispose() {
    _restoreCtrl.dispose();
    super.dispose();
  }

  Future<void> _exportarXlsx() async {
    setState(() => _busy = true);
    try {
      final path = await exportToExcel();
      setState(() => _lastBackupPath = path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Archivo XLSX exportado:\n$path')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error exportando: $e')));
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _importarXlsx() async {
    setState(() => _busy = true);
    try {
      await importFromExcel();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Importación completada')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error importando: $e')));
    } finally {
      setState(() => _busy = false);
    }
  }

  /// 🔹 Respaldo y restauración del archivo .db
  Future<void> _backupDb() async {
    setState(() => _busy = true);
    try {
      final path = await backupDbToDocuments();
      setState(() => _lastBackupPath = path);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Respaldo creado:\n$path')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al respaldar: $e')));
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ruta copiada al portapapeles')),
    );
  }

  Future<void> _restoreDb() async {
    final path = _restoreCtrl.text.trim();
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indica la ruta completa del .db')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await restoreDbFromFile(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Restauración completada. Cierra y vuelve a abrir la app para aplicar cambios.'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al restaurar: $e')));
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _verRutaActual() async {
    try {
      final path = await currentDbPath();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Ruta actual de la base de datos'),
          content: SelectableText(path),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _copyPath(path);
              },
              child: const Text('Copiar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _lastBackupPath;
    return Scaffold(
      appBar: AppBar(title: const Text('Respaldo / Importación')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 🔸 Sección XLSX
            Text('Exportar / Importar XLSX',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _exportarXlsx,
              icon: const Icon(Icons.file_download),
              label: const Text('Exportar XLSX'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _importarXlsx,
              icon: const Icon(Icons.file_upload),
              label: const Text('Importar XLSX'),
            ),
            const Divider(height: 32),

            // 🔸 Sección Backup físico .db
            Text('Respaldo físico (.db)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _backupDb,
              icon: const Icon(Icons.save_alt),
              label: const Text('Respaldar base de datos'),
            ),
            if (last != null) ...[
              const SizedBox(height: 8),
              Text('Último respaldo:', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              SelectableText(last),
              const SizedBox(height: 6),
              FilledButton.tonalIcon(
                onPressed: () => _copyPath(last),
                icon: const Icon(Icons.copy),
                label: const Text('Copiar ruta'),
              ),
            ],
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Ver ruta actual de pdv.db'),
              subtitle: const Text('Muestra dónde está el archivo de base de datos'),
              trailing: const Icon(Icons.folder_open),
              onTap: _verRutaActual,
            ),
            const Divider(height: 32),

            // 🔸 Restaurar desde ruta
            Text('Restaurar desde archivo .db',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _restoreCtrl,
              decoration: const InputDecoration(
                labelText: 'Ruta completa del archivo .db',
                border: OutlineInputBorder(),
                hintText: '/ruta/a/mi-respaldo.db',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _restoreDb,
              icon: const Icon(Icons.restore),
              label: const Text('Restaurar'),
            ),
            if (_busy) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}