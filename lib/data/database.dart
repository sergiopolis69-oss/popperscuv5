import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const _dbName = 'pdv.db';
  static const _dbVersion = 7; // sube versión para aplicar migraciones

  Database? _db;
  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // productos: SKU único y requerido
    await db.execute('''
      CREATE TABLE products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sku TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        category TEXT,
        default_sale_price REAL DEFAULT 0,
        last_purchase_price REAL DEFAULT 0,
        last_purchase_date TEXT,
        stock INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE customers(
        phone TEXT PRIMARY KEY,
        name TEXT,
        address TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE suppliers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        phone TEXT UNIQUE,
        name TEXT,
        address TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sales(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_phone TEXT,
        payment_method TEXT,
        place TEXT,
        shipping_cost REAL DEFAULT 0,
        discount REAL DEFAULT 0,
        date TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sale_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE purchases(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        folio TEXT,
        supplier_id INTEGER,
        date TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE purchase_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        unit_cost REAL NOT NULL
      )
    ''');

    // Índices útiles
    await db.execute('CREATE INDEX idx_products_sku ON products(sku)');
    await db.execute('CREATE INDEX idx_products_name ON products(name)');
    await db.execute('CREATE INDEX idx_sales_date ON sales(date)');
    await db.execute('CREATE INDEX idx_purchases_date ON purchases(date)');
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    // Migraciones defensivas para colocar UNIQUE sku y columna sku si faltara
    if (oldV < 6) {
      final tables = await db.rawQuery("PRAGMA table_info(products)");
      final hasSku = tables.any((c) => (c['name'] == 'sku'));
      if (!hasSku) {
        await db.execute('ALTER TABLE products ADD COLUMN sku TEXT');
      }
      // Normaliza y aplica UNIQUE:
      // crea tabla temporal con constraint y vuelca datos
      await db.execute('''
        CREATE TABLE IF NOT EXISTS _products_new(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sku TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL,
          category TEXT,
          default_sale_price REAL DEFAULT 0,
          last_purchase_price REAL DEFAULT 0,
          last_purchase_date TEXT,
          stock INTEGER DEFAULT 0
        )
      ''');
      await db.execute('''
        INSERT OR IGNORE INTO _products_new(id, sku, name, category, default_sale_price, last_purchase_price, last_purchase_date, stock)
        SELECT id,
               COALESCE(NULLIF(TRIM(sku),''), printf('MIGR-%d', id)),
               COALESCE(NULLIF(TRIM(name),''), printf('Producto %d', id)),
               category, default_sale_price, last_purchase_price, last_purchase_date, stock
        FROM products
      ''');
      await db.execute('DROP TABLE products');
      await db.execute('ALTER TABLE _products_new RENAME TO products');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_products_name ON products(name)');
    }

    if (oldV < 7) {
      // Asegura REAL en last_purchase_price
      await db.execute('UPDATE products SET last_purchase_price = CAST(IFNULL(last_purchase_price,0) AS REAL)');
    }
  }
}