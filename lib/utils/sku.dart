import 'dart:math';

String generateSku8() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rnd = Random.secure();
  return List.generate(8, (_) => chars[rnd.nextInt(chars.length)]).join();
}