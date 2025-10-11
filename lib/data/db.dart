// lib/data/db.dart
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Acceso único a la base SQLite de la app.
/// Usa `AppDb.instance.database` para obtener la conexión.
class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  static const _dbFile = 'popperscu_pdv.db'; // nombre del archivo .db
  static const _dbVersion = 3; // incrementa si cambias esquema

  Database? _cached;

  Future<Database> get database async {
    if (_cached != null) return _cached!;
    _cached = await _open();
    return _cached!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbFile);

    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        // Habilita FK para ON DELETE/UPDATE
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Crea todo el esquema desde cero.
  Future<void> _onCreate(Database db, int version) async {
    // Productos (SKU = PK)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products(
        sku TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        default_sale_price REAL,
        last_purchase_price REAL,
        last_purchase_date TEXT,
        stock REAL NOT NULL DEFAULT 0
      );
    ''');

    // Clientes (teléfono = PK)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers(
        phone TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        address TEXT
      );
    ''');

    // Proveedores (id libre, puede ser teléfono u otro identificador)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT
      );
    ''');

    // Ventas (usar TEXT para permitir importar IDs/folios)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales(
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,                -- ISO8601
        customer_phone TEXT,
        payment_method TEXT,
        place TEXT,
        shipping_cost REAL NOT NULL DEFAULT 0,
        discount REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (customer_phone) REFERENCES customers(phone) ON DELETE SET NULL
      );
    ''');

    // Partidas de venta (detalle por SKU)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id TEXT NOT NULL,
        product_sku TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
        FOREIGN KEY (product_sku) REFERENCES products(sku) ON DELETE RESTRICT
      );
    ''');

    // Compras (usar TEXT para permitir importar IDs/folios)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchases(
        id TEXT PRIMARY KEY,
        folio TEXT,
        date TEXT NOT NULL,               -- ISO8601
        supplier_id TEXT,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL
      );
    ''');

    // Partidas de compra (detalle por SKU)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_id TEXT NOT NULL,
        product_sku TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_cost REAL NOT NULL,
        FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE CASCADE,
        FOREIGN KEY (product_sku) REFERENCES products(sku) ON DELETE RESTRICT
      );
    ''');

    // Índices útiles
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_date ON sales(date);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_purchase_date ON purchases(date);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase ON purchase_items(purchase_id);');
  }

  /// Migraciones ligeras y seguras: sólo crea lo que falte.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Asegura todas las tablas e índices (idempotente)
    await _onCreate(db, newVersion);

    // Ejemplos de columnas nuevas (si alguna vez se agregan):
    // try { await db.execute('ALTER TABLE products ADD COLUMN some_new_col TEXT;'); } catch (_) {}
  }
}