// lib/utils/db_file_io.dart
import 'dart:io';
import 'package:path/path.dart' as p;
import '../data/database.dart';

/// RESPALDO: crea una copia del archivo SQLite actual
/// dentro de la carpeta 'backups' junto a la BD.
/// Devuelve la ruta completa del archivo creado.
Future<String> exportToExcel() async {
  final helper = DatabaseHelper.instance;
  final dbPath = await helper.dbFilePath();
  final folder = await helper.dbFolderPath();
  final backupsDir = Directory(p.join(folder, 'backups'));
  if (!await backupsDir.exists()) {
    await backupsDir.create(recursive: true);
  }

  // Cerrar antes de copiar
  await helper.reset();

  final ts = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '')
      .replaceAll('.', '')
      .replaceAll('-', '');
  final destPath = p.join(backupsDir.path, 'pdv_backup_$ts.db');
  await File(dbPath).copy(destPath);

  // Reabrir para seguir operando
  await helper.db;

  return destPath;
}

/// RESTAURAR: toma el archivo .db más reciente de 'backups'
/// y lo copia sobre la BD oficial de la app.
/// Devuelve la ruta final de la BD.
Future<String> importFromExcel() async {
  final helper = DatabaseHelper.instance;
  final folder = await helper.dbFolderPath();
  final backupsDir = Directory(p.join(folder, 'backups'));
  if (!await backupsDir.exists()) {
    throw Exception('No hay carpeta de respaldos');
  }

  final backups = backupsDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.db'))
      .toList()
    ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

  if (backups.isEmpty) {
    throw Exception('No se encontraron archivos de respaldo');
  }

  final latest = backups.first;
  final dbPath = await helper.dbFilePath();

  await helper.reset();
  await File(latest.path).copy(dbPath);
  await helper.db;

  return dbPath;
}