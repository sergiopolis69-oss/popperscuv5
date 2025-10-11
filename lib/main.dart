import 'package:flutter/material.dart';

// Asegúrate de que estos archivos existan con estas clases:
import 'ui/sales_page.dart';          // -> class SalesPage
import 'ui/sales_history_page.dart';  // -> class SalesHistoryPage
import 'ui/clients_page.dart';        // -> class ClientsPage
import 'ui/profit_page.dart';         // -> class ProfitPage
import 'ui/inventory_page.dart';      // -> class InventoryPage
import 'ui/purchases_page.dart';      // -> class PurchasesPage
import 'ui/backup_page.dart';         // -> class BackupPage

void main() {
  runApp(const PDVApp());
}

class PDVApp extends StatefulWidget {
  const PDVApp({super.key});
  @override
  State<PDVApp> createState() => _PDVAppState();
}

class _PDVAppState extends State<PDVApp> {
  int _index = 0;

  final _pages = const <Widget>[
    SalesPage(),
    SalesHistoryPage(),
    ClientsPage(),
    ProfitPage(),
    InventoryPage(),
    PurchasesPage(),
    BackupPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final seed = const Color(0xFF3B5BA9);
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);

    return MaterialApp(
      title: 'PDV Flutter',
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          isDense: true,
        ),
        cardTheme: CardTheme(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/images/logo.jpg',
                  width: 32, height: 32, fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 8),
              const Text('PoppersCU'),
            ],
          ),
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _pages[_index],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'Venta'),
            NavigationDestination(icon: Icon(Icons.history), label: 'Historial'),
            NavigationDestination(icon: Icon(Icons.people), label: 'Clientes'),
            NavigationDestination(icon: Icon(Icons.percent), label: 'Utilidad'),
            NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Inventario'),
            NavigationDestination(icon: Icon(Icons.shopping_cart), label: 'Compras'),
            NavigationDestination(icon: Icon(Icons.import_export), label: 'XLSX'),
          ],
        ),
      ),
    );
  }
}