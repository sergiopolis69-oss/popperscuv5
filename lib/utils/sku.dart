import 'dart:math';

/// Genera un SKU aleatorio de 8 caracteres alfanuméricos (sin 0/1/O/I).
String generateSku8() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
}
