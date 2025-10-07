import 'package:sqflite/sqflite.dart';
import '../data/database.dart';

class ProductRepository {
  Future<Database> get _db async => DatabaseHelper.instance.db;

  /// Busca por nombre, categoría o SKU (para live search ligero).
  /// Devuelve solo columnas útiles para UI rápida.
  Future<List<Map<String, dynamic>>> searchLite(String query, {int limit = 25}) async {
    final db = await _db;
    final q = '%${query.trim()}%';
    return db.query(
      'products',
      columns: [
        'id',
        'sku',
        'name',
        'category',
        'stock',
        'last_purchase_price',
        'default_sale_price',
      ],
      where: 'name LIKE ? OR category LIKE ? OR IFNULL(sku, "") LIKE ?',
      whereArgs: [q, q, q],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
    );
  }

  /// Obtiene un producto por SKU exacto.
  Future<Map<String, dynamic>?> findBySku(String sku) async {
    final db = await _db;
    final rows = await db.query(
      'products',
      where: 'sku = ?',
      whereArgs: [sku.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// Obtiene un producto por ID.
  Future<Map<String, dynamic>?> getById(int id) async {
    final db = await _db;
    final rows = await db.query('products', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// Crea o actualiza un producto.
  /// - Si [id] es null, inserta.
  /// - Si [id] no es null, actualiza ese registro.
  Future<int> upsert({
    int? id,
    String? sku,
    required String name,
    String? category,
    int stock = 0,
    double defaultSalePrice = 0.0,
    double initialCost = 0.0,
    double? lastPurchasePrice,
    DateTime? lastPurchaseDate,
  }) async {
    final db = await _db;
    final data = <String, Object?>{
      'sku': sku?.trim(),
      'name': name.trim(),
      'category': (category ?? '').trim(),
      'stock': stock,
      'default_sale_price': defaultSalePrice,
      'initial_cost': initialCost,
      if (lastPurchasePrice != null) 'last_purchase_price': lastPurchasePrice,
      if (lastPurchaseDate != null) 'last_purchase_date': lastPurchaseDate.toIso8601String(),
    };

    if (id == null) {
      return await db.insert('products', data);
    } else {
      await db.update('products', data, where: 'id = ?', whereArgs: [id]);
      return id;
    }
  }

  /// Ajusta inventario por compra y actualiza último costo/fecha de compra.
  Future<void> applyPurchase({
    required int productId,
    required int quantity,
    required double unitCost,
    DateTime? date,
  }) async {
    final db = await _db;
    final now = (date ?? DateTime.now()).toIso8601String();
    await db.update(
      'products',
      {
        'stock': DatabaseExpression('stock + $quantity'),
        'last_purchase_price': unitCost,
        'last_purchase_date': now,
      },
      where: 'id = ?',
      whereArgs: [productId],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Disminuye inventario por venta (cantidad positiva).
  Future<void> applySale({
    required int productId,
    required int quantity,
  }) async {
    final db = await _db;
    await db.update(
      'products',
      {
        'stock': DatabaseExpression('stock - $quantity'),
      },
      where: 'id = ?',
      whereArgs: [productId],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Lista simple (para catálogos o combos).
  Future<List<Map<String, dynamic>>> list({int limit = 200, int offset = 0}) async {
    final db = await _db;
    return db.query(
      'products',
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
      offset: offset,
    );
  }

  /// Elimina un producto por ID.
  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }
}

/// Pequeño helper para expresiones SQL en updates (p.ej. stock = stock + 1)
class DatabaseExpression {
  final String expression;
  const DatabaseExpression(this.expression);
}

/// Extiende sqflite.update para soportar DatabaseExpression como valor.
extension _ExprUpdate on Database {
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    // Detecta DatabaseExpression y genera setClause manual.
    final exprEntries = <String, String>{};
    final normal = <String, Object?>{};
    values.forEach((k, v) {
      if (v is DatabaseExpression) {
        exprEntries[k] = v.expression;
      } else {
        normal[k] = v;
      }
    });

    if (exprEntries.isEmpty) {
      // Caso normal
      return sqfliteUpdate(
        table,
        normal,
        where: where,
        whereArgs: whereArgs,
        conflictAlgorithm: conflictAlgorithm,
      );
    }

    // Armar UPDATE manual con expresiones + parámetros normales.
    final sets = <String>[];
    final args = <Object?>[];
    normal.forEach((k, v) {
      sets.add('$k = ?');
      args.add(v);
    });
    exprEntries.forEach((k, expr) {
      sets.add('$k = $expr');
    });

    final sql = StringBuffer()
      ..write('UPDATE $table SET ')
      ..write(sets.join(', '));
    if (where != null && where.isNotEmpty) {
      sql.write(' WHERE $where');
    }
    final dbClient = this;
    return dbClient.rawUpdate(sql.toString(), [...args, if (whereArgs != null) ...whereArgs]);
  }

  // Renombra al update original de sqflite para seguir usándolo arriba
  Future<int> sqfliteUpdate(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) =>
      (this as dynamic).update(table, values,
          where: where, whereArgs: whereArgs, conflictAlgorithm: conflictAlgorithm);
}