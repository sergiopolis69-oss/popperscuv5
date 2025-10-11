import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseProvider {
  DatabaseProvider._();
  static final DatabaseProvider instance = DatabaseProvider._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'popperscu.db');
    return openDatabase(
      path,
      version: 6,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS products(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sku TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            category TEXT,
            default_sale_price REAL,
            last_purchase_price REAL,
            last_purchase_date TEXT,
            stock REAL DEFAULT 0
          );
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS customers(
            phone TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            address TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS suppliers(
            phone TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            address TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS sales(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            customer_phone TEXT,
            payment_method TEXT,
            place TEXT,
            shipping_cost REAL DEFAULT 0,
            discount REAL DEFAULT 0
          );
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_date ON sales(date);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_customer ON sales(customer_phone);');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS sale_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sale_id INTEGER NOT NULL,
            product_sku TEXT NOT NULL,
            product_name TEXT NOT NULL,
            quantity REAL NOT NULL,
            unit_price REAL NOT NULL
          );
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id);');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS purchases(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            folio TEXT,
            date TEXT NOT NULL,
            supplier_id TEXT
          );
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_purchases_date ON purchases(date);');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS purchase_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            purchase_id INTEGER NOT NULL,
            product_sku TEXT NOT NULL,
            product_name TEXT NOT NULL,
            quantity REAL NOT NULL,
            unit_cost REAL NOT NULL
          );
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase ON purchase_items(purchase_id);');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute('CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);');
        }
        if (oldV < 3) {
          await db.execute('ALTER TABLE products ADD COLUMN default_sale_price REAL;');
        }
        if (oldV < 4) {
          await db.execute('ALTER TABLE products ADD COLUMN last_purchase_price REAL;');
          await db.execute('ALTER TABLE products ADD COLUMN last_purchase_date TEXT;');
        }
        if (oldV < 5) {
          await db.execute('ALTER TABLE products ADD COLUMN stock REAL DEFAULT 0;');
        }
        if (oldV < 6) {
          await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_customer ON sales(customer_phone);');
        }
      },
    );
  }
}