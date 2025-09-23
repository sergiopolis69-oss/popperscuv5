
import '../data/database.dart';
import '../models/product.dart';

class ProductRepository {
  Future<int> insert(Product p) async {
    final db = await AppDatabase().db();
    return db.insert('products', p.toMap());
  }

  Future<int> update(Product p) async {
    final db = await AppDatabase().db();
    return db.update('products', p.toMap(), where: 'id=?', whereArgs: [p.id]);
  }

  Future<int> delete(int id) async {
    final db = await AppDatabase().db();
    return db.delete('products', where: 'id=?', whereArgs: [id]);
  }

  Future<List<Product>> search(String q) async {
    final db = await AppDatabase().db();
    final res = await db.query('products',
      where: 'name LIKE ? OR category LIKE ?',
      whereArgs: ['%$q%', '%$q%'],
      orderBy: 'name ASC');
    return res.map(Product.fromMap).toList();
  }

  Future<List<Product>> all() async {
    final db = await AppDatabase().db();
    final res = await db.query('products', orderBy: 'name ASC');
    return res.map(Product.fromMap).toList();
  }
}
