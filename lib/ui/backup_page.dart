// lib/ui/backup_page.dart
import 'package:flutter/material.dart';
import '../utils/db_file_io.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;
  String? _lastPath;

  Future<void> _doExport() async {
    setState(() => _busy = true);
    try {
      final path = await exportToExcel();
      setState(() => _lastPath = path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Respaldo guardado en:\n$path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al respaldar: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doImport() async {
    setState(() => _busy = true);
    try {
      final path = await importFromExcel();
      setState(() => _lastPath = path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('BD restaurada. Ruta:\n$path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al restaurar: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _lastPath ?? '(aún sin respaldo/restauración en esta sesión)';
    return Scaffold(
      appBar: AppBar(title: const Text('Respaldo (BD)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              title: const Text('Última ruta'),
              subtitle: SelectableText(path),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _doExport,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Respaldar BD'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _doImport,
                  icon: const Icon(Icons.settings_backup_restore),
                  label: const Text('Restaurar último respaldo'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text(
              'Los respaldos se guardan en la carpeta "backups" junto a la base de datos de la app. '
              'Puedes copiar ese archivo .db para migrar/restaurar entre instalaciones.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}