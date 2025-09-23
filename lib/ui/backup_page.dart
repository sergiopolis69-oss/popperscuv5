
import 'package:flutter/material.dart';
import '../utils/xml_backup.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  String _status = '';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.icon(onPressed: () async {
            final saved = await XmlBackup.exportAll();
            setState(()=>_status = saved != null ? 'Exportado a: $saved' : 'Cancelado');
          }, icon: const Icon(Icons.upload), label: const Text('Exportar XML')),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: () async {
            await XmlBackup.importAllWithPicker();
            setState(()=>_status='Importación finalizada');
          }, icon: const Icon(Icons.download), label: const Text('Importar XML')),
          const SizedBox(height: 16),
          Text(_status),
        ],
      ),
    );
  }
}
