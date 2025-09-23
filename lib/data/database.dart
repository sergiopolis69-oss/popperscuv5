
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  Database? _db;

  Future<Database> db() async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'pdv_flutter.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE products(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            salePrice REAL NOT NULL,
            lastPurchasePrice REAL NOT NULL,
            lastPurchaseDate TEXT,
            stock INTEGER NOT NULL DEFAULT 0
          );
        ''');
        await db.execute('''
          CREATE TABLE customers(
            phone TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            address TEXT NOT NULL
          );
        ''');
        await db.execute('''
          CREATE TABLE purchases(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            supplier TEXT NOT NULL,
            note TEXT
          );
        ''');
        await db.execute('''
          CREATE TABLE purchase_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            purchaseId INTEGER NOT NULL,
            productId INTEGER NOT NULL,
            quantity INTEGER NOT NULL,
            unitCost REAL NOT NULL,
            FOREIGN KEY(purchaseId) REFERENCES purchases(id),
            FOREIGN KEY(productId) REFERENCES products(id)
          );
        ''');
        await db.execute('''
          CREATE TABLE sales(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customerPhone TEXT NOT NULL,
            paymentMethod TEXT NOT NULL,
            datetime TEXT NOT NULL,
            place TEXT NOT NULL,
            shippingCost REAL NOT NULL,
            discount REAL NOT NULL,
            FOREIGN KEY(customerPhone) REFERENCES customers(phone)
          );
        ''');
        await db.execute('''
          CREATE TABLE sale_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            saleId INTEGER NOT NULL,
            productId INTEGER NOT NULL,
            quantity INTEGER NOT NULL,
            unitPrice REAL NOT NULL,
            FOREIGN KEY(saleId) REFERENCES sales(id),
            FOREIGN KEY(productId) REFERENCES products(id)
          );
        ''');
      },
    );
    return _db!;
  }
}
