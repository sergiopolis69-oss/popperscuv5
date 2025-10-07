import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static const _dbName = 'pdv_flutter.db';
  static const _dbVersion = 5; // <- aumenta si haces cambios estructurales
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _database;

  Future<Database> get db async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), _dbName);
    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // --- CLIENTES ---
    await db.execute('''
      CREATE TABLE customers (
        phone TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        address TEXT
      );
    ''');

    // --- PROVEEDORES ---
    await db.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL UNIQUE,
        address TEXT
      );
    ''');

    // --- PRODUCTOS ---
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sku TEXT,
        name TEXT NOT NULL,
        category TEXT,
        stock INTEGER DEFAULT 0,
        last_purchase_price REAL DEFAULT 0,
        last_purchase_date TEXT,
        default_sale_price REAL DEFAULT 0,
        initial_cost REAL DEFAULT 0
      );
    ''');

    // --- COMPRAS ---
    await db.execute('''
      CREATE TABLE purchases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        folio TEXT NOT NULL,
        supplier_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        FOREIGN KEY(supplier_id) REFERENCES suppliers(id)
      );
    ''');

    await db.execute('''
      CREATE TABLE purchase_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        unit_cost REAL NOT NULL,
        FOREIGN KEY(purchase_id) REFERENCES purchases(id),
        FOREIGN KEY(product_id) REFERENCES products(id)
      );
    ''');

    // --- VENTAS ---
    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_phone TEXT NOT NULL,
        payment_method TEXT,
        place TEXT,
        shipping_cost REAL DEFAULT 0,
        discount REAL DEFAULT 0,
        date TEXT NOT NULL,
        FOREIGN KEY(customer_phone) REFERENCES customers(phone)
      );
    ''');

    await db.execute('''
      CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        FOREIGN KEY(sale_id) REFERENCES sales(id),
        FOREIGN KEY(product_id) REFERENCES products(id)
      );
    ''');

    // Índices recomendados
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_customer ON sales(customer_phone);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_suppliers_phone ON suppliers(phone);');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migraciones defensivas
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS suppliers(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          phone TEXT NOT NULL UNIQUE,
          address TEXT
        );
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_suppliers_phone ON suppliers(phone);');
    }

    if (oldVersion < 3) {
      await db.execute('ALTER TABLE products ADD COLUMN initial_cost REAL DEFAULT 0;');
    }

    if (oldVersion < 4) {
      await db.execute('ALTER TABLE sales ADD COLUMN shipping_cost REAL DEFAULT 0;');
      await db.execute('ALTER TABLE sales ADD COLUMN discount REAL DEFAULT 0;');
    }

    if (oldVersion < 5) {
      // Asegurar índices
      await db.execute('CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_customer ON sales(customer_phone);');
    }
  }

  // Helper: limpiar tablas
  Future<void> clearAll() async {
    final db = await this.db;
    await db.transaction((txn) async {
      await txn.delete('sale_items');
      await txn.delete('sales');
      await txn.delete('purchase_items');
      await txn.delete('purchases');
      await txn.delete('products');
      await txn.delete('customers');
      await txn.delete('suppliers');
    });
  }

  // Helper: obtener conteos resumidos
  Future<Map<String, int>> counts() async {
    final db = await this.db;
    final tables = ['customers', 'suppliers', 'products', 'sales', 'purchases'];
    final counts = <String, int>{};
    for (final t in tables) {
      final c = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $t')) ?? 0;
      counts[t] = c;
    }
    return counts;
  }
}