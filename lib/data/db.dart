import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Singleton sencillo para abrir y exponer la BD.
/// Usa nombres de tablas/campos compatibles con lo que ya tenemos en la app.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final basePath = await getDatabasesPath();
    final path = p.join(basePath, 'popperscu.db');

    return openDatabase(
      path,
      version: 4,
      onCreate: (Database db, int version) async {
        // Clientes
        await db.execute('''
          CREATE TABLE IF NOT EXISTS customers(
            phone TEXT PRIMARY KEY,
            name TEXT,
            address TEXT
          );
        ''');

        // Proveedores
        await db.execute('''
          CREATE TABLE IF NOT EXISTS suppliers(
            phone TEXT PRIMARY KEY,
            name TEXT,
            address TEXT
          );
        ''');

        // Productos: sku es la llave lógica única
        await db.execute('''
          CREATE TABLE IF NOT EXISTS products(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sku TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            default_sale_price REAL NOT NULL DEFAULT 0,
            last_purchase_price REAL NOT NULL DEFAULT 0,
            stock INTEGER NOT NULL DEFAULT 0
          );
        ''');

        await db.execute('CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);');

        // Ventas
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sales(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_phone TEXT,
            payment_method TEXT,
            place TEXT,
            shipping_cost REAL NOT NULL DEFAULT 0,
            discount REAL NOT NULL DEFAULT 0,
            date TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS sale_items(
            sale_id INTEGER NOT NULL,
            product_sku TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            unit_price REAL NOT NULL,
            PRIMARY KEY(sale_id, product_sku)
          );
        ''');

        // Compras
        await db.execute('''
          CREATE TABLE IF NOT EXISTS purchases(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            folio TEXT,
            supplier_phone TEXT,
            date TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS purchase_items(
            purchase_id INTEGER NOT NULL,
            product_id INTEGER NOT NULL,
            quantity INTEGER NOT NULL,
            unit_cost REAL NOT NULL,
            PRIMARY KEY(purchase_id, product_id)
          );
        ''');

        await db.execute('CREATE INDEX IF NOT EXISTS idx_purchase_items_pid ON purchase_items(purchase_id);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_sid ON sale_items(sale_id);');
      },
      onUpgrade: (Database db, int oldV, int newV) async {
        // Asegurar columnas/índices en upgrades.
        await db.execute('''
          CREATE TABLE IF NOT EXISTS suppliers(
            phone TEXT PRIMARY KEY,
            name TEXT,
            address TEXT
          );
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS purchase_items(
            purchase_id INTEGER NOT NULL,
            product_id INTEGER NOT NULL,
            quantity INTEGER NOT NULL,
            unit_cost REAL NOT NULL,
            PRIMARY KEY(purchase_id, product_id)
          );
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_purchase_items_pid ON purchase_items(purchase_id);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_sid ON sale_items(sale_id);');
      },
    );
  }
}

/// Alias neutro para que las pantallas no dependan del nombre de la clase.
Future<Database> getDb() => AppDatabase.instance.db;