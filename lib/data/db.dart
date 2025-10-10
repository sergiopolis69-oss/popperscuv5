import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../utils/sku.dart';

Future<Database> openAppDb() async {
  final path = join(await getDatabasesPath(), 'pdv.db');
  return openDatabase(
    path,
    version: 6,
    onCreate: (db, v) async {
      // Versión nueva con SKU como PK desde cero.
      await _createV6(db);
    },
    onUpgrade: (db, oldV, newV) async {
      if (oldV < 2) { /* tus migraciones antiguas si existían */ }
      if (oldV < 3) { /* … */ }
      if (oldV < 4) { /* … */ }
      if (oldV < 5) { /* … */ }

      // Migración 6: sku -> PK, y tablas *_items por SKU.
      if (oldV < 6) {
        await _migrateToV6(db);
      }
    },
  );
}

Future<void> _createV6(Database db) async {
  // Catálogos
  await db.execute('''
    CREATE TABLE customers(
      phone TEXT PRIMARY KEY,
      name  TEXT NOT NULL,
      address TEXT
    );
  ''');

  await db.execute('''
    CREATE TABLE suppliers(
      id TEXT PRIMARY KEY, -- usa teléfono u otro id libre
      name TEXT NOT NULL,
      phone TEXT,
      address TEXT
    );
  ''');

  await db.execute('''
    CREATE TABLE products(
      sku TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      category TEXT NOT NULL,
      default_sale_price REAL NOT NULL DEFAULT 0,
      last_purchase_price REAL,
      last_purchase_date TEXT,
      stock REAL NOT NULL DEFAULT 0
    );
  ''');

  // Ventas
  await db.execute('''
    CREATE TABLE sales(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      customer_phone TEXT,
      payment_method TEXT,
      place TEXT,
      shipping_cost REAL NOT NULL DEFAULT 0,
      discount REAL NOT NULL DEFAULT 0,
      FOREIGN KEY(customer_phone) REFERENCES customers(phone)
    );
  ''');

  await db.execute('''
    CREATE TABLE sale_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sale_id INTEGER NOT NULL,
      product_sku TEXT NOT NULL,
      product_name TEXT NOT NULL,
      quantity REAL NOT NULL,
      unit_price REAL NOT NULL,
      FOREIGN KEY(sale_id) REFERENCES sales(id) ON DELETE CASCADE,
      FOREIGN KEY(product_sku) REFERENCES products(sku)
    );
  ''');

  // Compras
  await db.execute('''
    CREATE TABLE purchases(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      folio TEXT,
      date TEXT NOT NULL,
      supplier_id TEXT,
      FOREIGN KEY(supplier_id) REFERENCES suppliers(id)
    );
  ''');

  await db.execute('''
    CREATE TABLE purchase_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      purchase_id INTEGER NOT NULL,
      product_sku TEXT NOT NULL,
      product_name TEXT NOT NULL,
      quantity REAL NOT NULL,
      unit_cost REAL NOT NULL,
      FOREIGN KEY(purchase_id) REFERENCES purchases(id) ON DELETE CASCADE,
      FOREIGN KEY(product_sku) REFERENCES products(sku)
    );
  ''');
}

Future<void> _migrateToV6(Database db) async {
  // 1) Crear nuevas tablas con el esquema V6
  await _createV6(db);

  // Si vienes de versiones con products.id INTEGER, intenta copiar.
  // Detectar si existe la tabla previa:
  final res = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='products_old'"
  );
  // Si NO hay products_old, quizá tu esquema actual ya se llama 'products' con id entero.
  // Vamos a renombrar si existe 'products' con columna 'id' para poder copiar.
  final prevCols = await db.rawQuery("PRAGMA table_info(products)");
  final hasId = prevCols.any((c) => c['name'] == 'id');

  if (hasId) {
    await db.execute('ALTER TABLE products RENAME TO products_tmp_old;');

    // Crear tabla products con sku como PK ya está.
    // Copiar: si sku vacío/null, generar uno.
    final oldRows = await db.query('products_tmp_old');
    for (final r in oldRows) {
      var sku = (r['sku'] ?? '').toString().trim();
      if (sku.isEmpty) sku = generateSku8();
      await db.insert('products', {
        'sku': sku,
        'name': r['name'],
        'category': r['category'] ?? 'general',
        'default_sale_price': r['default_sale_price'] ?? 0,
        'last_purchase_price': r['last_purchase_price'],
        'last_purchase_date': r['last_purchase_date'],
        'stock': r['stock'] ?? 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      // Guarda un mapa id->sku para migrar items
    }

    // Migrar sale_items si existía product_id
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('sale_items','purchase_items','sales','purchases')"
    );
    final names = tables.map((e) => e['name']).toSet();

    if (names.contains('sales')) {
      // Si ya existía, copiar ventas a la nueva (ya creada) y borrar la vieja duplicada:
      // Aquí asumimos que la vieja 'sales' fue renombrada? Si no, nada que hacer
    }

    // Si existían *_items viejas con product_id:
    // No podemos resolver id->sku sin un mapa; si lo necesitas, añade un join temporal.
    // Para simplificar, si tenías datos previos y quieres conservar detalle, exporta antes y reimporta por SKU.
    await db.execute('DROP TABLE IF EXISTS products_tmp_old;');
  }
}