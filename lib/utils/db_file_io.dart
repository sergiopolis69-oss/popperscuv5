// lib/utils/db_file_io.dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../db/database.dart';

/// Copia el archivo SQLite (pdv.db) a Documentos de la app y devuelve la ruta del respaldo.
Future<String> backupDbToDocuments() async {
  final dbPathBase = await getDatabasesPath();
  final src = File(p.join(dbPathBase, 'pdv.db'));

  if (!await src.exists()) {
    throw Exception('No se encontró pdv.db en $dbPathBase');
  }

  // Cierra la conexión si está abierta para asegurar flush de disco.
  try {
    final db = await DatabaseHelper.instance.db;
    await db.close();
  } catch (_) {}
  DatabaseHelper.instance.reset();

  final docsDir = await getApplicationDocumentsDirectory();
  final ts = DateTime.now();
  final fileName =
      'pdv-backup-${ts.year.toString().padLeft(4, '0')}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}-${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}${ts.second.toString().padLeft(2, '0')}.db';
  final dstPath = p.join(docsDir.path, fileName);

  await src.copy(dstPath);
  return dstPath;
}

/// Restaura el archivo SQLite desde [sourceFilePath] y reemplaza pdv.db.
Future<void> restoreDbFromFile(String sourceFilePath) async {
  final src = File(sourceFilePath);
  if (!await src.exists()) {
    throw Exception('El archivo no existe: $sourceFilePath');
  }

  final dbPathBase = await getDatabasesPath();
  final dstPath = p.join(dbPathBase, 'pdv.db');

  try {
    final db = await DatabaseHelper.instance.db;
    await db.close();
  } catch (_) {}
  DatabaseHelper.instance.reset();

  await Directory(dbPathBase).create(recursive: true);
  final dst = File(dstPath);
  if (await dst.exists()) {
    await dst.delete();
  }
  await src.copy(dstPath);
}

/// Devuelve la ruta actual de pdv.db
Future<String> currentDbPath() async {
  final dbPathBase = await getDatabasesPath();
  return p.join(dbPathBase, 'pdv.db');
}