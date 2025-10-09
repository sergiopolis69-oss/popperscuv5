import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();
  static Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final base = await getDatabasesPath();
    final dbPath = p.join(base, 'pdv.sqlite');
    final database = await openDatabase(
      dbPath,
      version: 3, // súbelo si ya usabas 2
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    await _ensureSkuColumns(database);
    return database;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers(
        phone TEXT PRIMARY KEY,
        name TEXT,
        address TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        phone TEXT UNIQUE,
        address TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sku TEXT UNIQUE,
        name TEXT,
        category TEXT,
        default_sale_price REAL,
        last_purchase_price REAL,
        last_purchase_date TEXT,
        stock INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_phone TEXT,
        payment_method TEXT,
        place TEXT,
        shipping_cost REAL,
        discount REAL,
        date TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER,
        product_id INTEGER,
        sku TEXT,
        quantity INTEGER,
        unit_price REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchases(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER,
        folio TEXT,
        date TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_id INTEGER,
        product_id INTEGER,
        sku TEXT,
        quantity INTEGER,
        unit_cost REAL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await _ensureSkuColumns(db);
  }

  /// Asegura columnas SKU en items y hace backfill desde products
  Future<void> _ensureSkuColumns(Database db) async {
    // sale_items.sku
    final saleCols = await db.rawQuery('PRAGMA table_info(sale_items)');
    final hasSaleSku = saleCols.any((c) => c['name'] == 'sku');
    if (!hasSaleSku) {
      await db.execute('ALTER TABLE sale_items ADD COLUMN sku TEXT');
      await db.execute('''
        UPDATE sale_items SET sku = (
          SELECT p.sku FROM products p WHERE p.id = sale_items.product_id
        )
      ''');
    }

    // purchase_items.sku
    final purchCols = await db.rawQuery('PRAGMA table_info(purchase_items)');
    final hasPurchSku = purchCols.any((c) => c['name'] == 'sku');
    if (!hasPurchSku) {
      await db.execute('ALTER TABLE purchase_items ADD COLUMN sku TEXT');
      await db.execute('''
        UPDATE purchase_items SET sku = (
          SELECT p.sku FROM products p WHERE p.id = purchase_items.product_id
        )
      ''');
    }

    // Forzar REAL en costos (por si vienen como texto desde XLSX)
    await db.execute('UPDATE products SET last_purchase_price = CAST(IFNULL(last_purchase_price,0) AS REAL)');
  }
}