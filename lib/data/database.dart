import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._();
  DatabaseHelper._();

  Database? _db;
  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final p = join(await getDatabasesPath(), 'pdv.db');
    return await openDatabase(
      p,
      version: 7, // ⬅ subimos versión
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE customers(
            phone TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            address TEXT DEFAULT ''
          );
        ''');

        await db.execute('''
          CREATE TABLE suppliers(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT DEFAULT '',
            address TEXT DEFAULT ''
          );
        ''');

        await db.execute('''
          CREATE TABLE products(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sku TEXT UNIQUE,
            name TEXT NOT NULL,
            category TEXT DEFAULT '',
            stock INTEGER NOT NULL DEFAULT 0,
            last_purchase_price REAL NOT NULL DEFAULT 0,
            last_purchase_date TEXT,
            default_sale_price REAL NOT NULL DEFAULT 0,   -- ⬅ nuevo
            initial_cost REAL NOT NULL DEFAULT 0          -- ⬅ nuevo
          );
        ''');

        await db.execute('''
          CREATE TABLE sales(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_phone TEXT,
            payment_method TEXT NOT NULL,
            place TEXT DEFAULT '',
            shipping_cost REAL NOT NULL DEFAULT 0,
            discount REAL NOT NULL DEFAULT 0,
            date TEXT NOT NULL
          );
        ''');

        await db.execute('''
          CREATE TABLE sale_items(
            sale_id INTEGER NOT NULL,
            product_id INTEGER NOT NULL,
            quantity INTEGER NOT NULL,
            unit_price REAL NOT NULL,
            FOREIGN KEY(sale_id) REFERENCES sales(id) ON DELETE CASCADE
          );
        ''');

        await db.execute('''
          CREATE TABLE purchases(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            folio TEXT NOT NULL,
            supplier_id INTEGER NOT NULL,
            date TEXT NOT NULL,
            FOREIGN KEY(supplier_id) REFERENCES suppliers(id)
          );
        ''');

        await db.execute('''
          CREATE TABLE purchase_items(
            purchase_id INTEGER NOT NULL,
            product_id INTEGER NOT NULL,
            quantity INTEGER NOT NULL,
            unit_cost REAL NOT NULL,
            FOREIGN KEY(purchase_id) REFERENCES purchases(id) ON DELETE CASCADE
          );
        ''');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 5) {
          await db.execute('CREATE TABLE IF NOT EXISTS suppliers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT DEFAULT "", address TEXT DEFAULT "");');
          await db.execute('CREATE TABLE IF NOT EXISTS purchases(id INTEGER PRIMARY KEY AUTOINCREMENT, folio TEXT NOT NULL, supplier_id INTEGER NOT NULL, date TEXT NOT NULL);');
          await db.execute('CREATE TABLE IF NOT EXISTS purchase_items(purchase_id INTEGER NOT NULL, product_id INTEGER NOT NULL, quantity INTEGER NOT NULL, unit_cost REAL NOT NULL);');
          await db.execute('ALTER TABLE products ADD COLUMN last_purchase_price REAL NOT NULL DEFAULT 0;');
          await db.execute('ALTER TABLE products ADD COLUMN last_purchase_date TEXT;');
        }
        if (oldV < 7) {
          await db.execute('ALTER TABLE products ADD COLUMN default_sale_price REAL NOT NULL DEFAULT 0;');
          await db.execute('ALTER TABLE products ADD COLUMN initial_cost REAL NOT NULL DEFAULT 0;');
        }
      },
    );
  }
}