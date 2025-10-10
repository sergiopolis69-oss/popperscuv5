Future<String> _saveExcelToDownloads(Excel excel, String filename) async {
  // 1) Pide permisos (por si el OEM los exige)
  await [Permission.storage].request();

  final bytes = excel.save();
  if (bytes == null) {
    throw Exception('No fue posible generar el archivo XLSX');
  }

  // 2) Usa el MIME correcto para Excel y captura el valor de retorno
  //    Nota: algunos dispositivos devuelven una ruta, otros un "content://".
  final saved = await FileSaver.instance.saveFile(
    name: filename,
    bytes: Uint8List.fromList(bytes),
    ext: 'xlsx',
    mimeType: MimeType.xlsx, // <- importante
  );

  // `saved` puede ser String (ruta/uri). Lo convertimos a string siempre.
  final savedStr = saved?.toString() ?? '';
  if (savedStr.isEmpty) {
    // Forzamos un error visible si el plugin no entregó nada
    throw Exception('El sistema no devolvió localización del archivo');
  }
  return savedStr;
}