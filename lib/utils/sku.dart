import 'dart:math';

final _rand = Random.secure();
String generateSku8() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return List.generate(8, (_) => chars[_rand.nextInt(chars.length)]).join();
}