import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Nombre y versión del esquema
const _dbName = 'popperscu.db'; // usa este nombre fijo
const _dbVersion = 4;

/// Punto único de apertura de BD
Future<Database> openAppDb() async {
  final base = await getDatabasesPath();
  final path = p.join(base, _dbName);
  return openDatabase(
    path,
    version: _dbVersion,
    onCreate: (db, _) async {
      // Clientes (PK = phone)
      await db.execute('''
        CREATE TABLE customers(
          phone TEXT PRIMARY KEY,
          name TEXT NOT NULL DEFAULT '',
          address TEXT NOT NULL DEFAULT ''
        )
      ''');

      // Proveedores (PK = id = phone)
      await db.execute('''
        CREATE TABLE suppliers(
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL DEFAULT '',
          phone TEXT NOT NULL DEFAULT '',
          address TEXT NOT NULL DEFAULT ''
        )
      ''');

      // Productos (PK = sku)
      await db.execute('''
        CREATE TABLE products(
          sku TEXT PRIMARY KEY,
          name TEXT NOT NULL DEFAULT '',
          category TEXT NOT NULL DEFAULT '',
          default_sale_price REAL NOT NULL DEFAULT 0,
          last_purchase_price REAL NOT NULL DEFAULT 0,
          last_purchase_date TEXT,
          stock REAL NOT NULL DEFAULT 0
        )
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
          total REAL NOT NULL DEFAULT 0
        )
      ''');

      await db.execute('''
        CREATE TABLE sale_items(
          sale_id INTEGER NOT NULL,
          product_sku TEXT NOT NULL,
          product_name TEXT NOT NULL DEFAULT '',
          quantity REAL NOT NULL DEFAULT 0,
          unit_price REAL NOT NULL DEFAULT 0
        )
      ''');

      // Compras
      await db.execute('''
        CREATE TABLE purchases(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          folio TEXT,
          date TEXT NOT NULL,
          supplier_id TEXT,
          total REAL NOT NULL DEFAULT 0
        )
      ''');

      await db.execute('''
        CREATE TABLE purchase_items(
          purchase_id INTEGER NOT NULL,
          product_sku TEXT NOT NULL,
          product_name TEXT NOT NULL DEFAULT '',
          quantity REAL NOT NULL DEFAULT 0,
          unit_cost REAL NOT NULL DEFAULT 0
        )
      ''');
    },

    onUpgrade: (db, oldV, newV) async {
      // Ajustes defensivos por si vienes de esquemas previos
      if (oldV < 2) {
        await db.execute('ALTER TABLE products ADD COLUMN category TEXT NOT NULL DEFAULT ""');
      }
      if (oldV < 3) {
        await db.execute('ALTER TABLE sales ADD COLUMN total REAL NOT NULL DEFAULT 0');
        await db.execute('ALTER TABLE purchases ADD COLUMN total REAL NOT NULL DEFAULT 0');
      }
      if (oldV < 4) {
        await db.execute('ALTER TABLE products ADD COLUMN last_purchase_date TEXT');
      }
    },
  );
}