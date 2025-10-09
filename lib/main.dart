import 'package:flutter/material.dart';

// IMPORTS de UI (asegúrate que los paths existan)
import 'ui/sales_page.dart' show SalesPage;
import 'ui/sales_history_page.dart' show SalesHistoryPage;
import 'ui/clients_page.dart' show ClientsPage;
import 'ui/profit_page.dart' show ProfitPage;
import 'ui/inventory_page.dart' show InventoryPage;
import 'ui/purchases_page.dart' show PurchasesPage;
import 'ui/backup_page.dart' show BackupPage;

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

  final _pages = const [
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
    final theme = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        isDense: true,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
    );

    return MaterialApp(
      title: 'PoppersCU - Control de activos'
      theme: theme,
      home: Scaffold(
        appBar: AppBar(title: const Text('PDV Flutter')),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _pages[_index],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'Venta'),
            NavigationDestination(icon: Icon(Icons.history), label: 'Historial'),
            NavigationDestination(icon: Icon(Icons.people), label: 'Clientes'),
            NavigationDestination(icon: Icon(Icons.percent), label: 'Utilidad'),
            NavigationDestination(icon: Icon(Icons.inventory), label: 'Inventario'),
            NavigationDestination(icon: Icon(Icons.shopping_cart), label: 'Compras'),
            NavigationDestination(icon: Icon(Icons.import_export), label: 'XLSX'),
          ],
          onDestinationSelected: (i){ setState(()=>_index=i); },
        ),
      ),
    );
  }
}
