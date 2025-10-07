import 'dart:typed_data';
import 'package:flutter/services.dart';

class AndroidDownloads {
  static const _ch = MethodChannel('pdv/files');

  /// Guarda bytes en Descargas usando MediaStore (Android 10+)
  /// o almacenamiento externo directo (Android 9 o menos).
  static Future<String> saveBytes({
    required String baseName,
    required List<int> bytes,
    String mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  }) async {
    final filename = baseName.endsWith('.xlsx') ? baseName : '$baseName.xlsx';
    final uriOrPath = await _ch.invokeMethod<String>('saveToDownloads', {
      'filename': filename,
      'bytes': Uint8List.fromList(bytes),
      'mime': mime,
    });
    return uriOrPath ?? '';
  }
}