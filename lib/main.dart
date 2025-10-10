import 'package:flutter/material.dart';
import 'db.dart';
import 'ui/sales_page.dart';
import 'ui/purchases_page.dart';
import 'ui/inventory_page.dart';
import 'ui/backup_page.dart';
import 'ui/sales_history_page.dart';
import 'ui/clients_page.dart';
import 'ui/profit_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DB.ensureInitialized();
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
      cardTheme: CardTheme(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        isDense: true,
      ),
      appBarTheme: AppBarTheme(backgroundColor: scheme.surface, foregroundColor: scheme.onSurface, elevation: 0),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PDV Flutter',
      theme: theme,
      home: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset('assets/images/logo.jpg', width: 32, height: 32, fit: BoxFit.cover),
              ),
              const SizedBox(width: 8),
              const Text('PDV Flutter'),
            ],
          ),
        ),
        body: AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: _pages[_index]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i)=>setState(()=>_index=i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'Venta'),
            NavigationDestination(icon: Icon(Icons.history), label: 'Historial'),
            NavigationDestination(icon: Icon(Icons.people), label: 'Clientes'),
            NavigationDestination(icon: Icon(Icons.percent), label: 'Utilidad'),
            NavigationDestination(icon: Icon(Icons.inventory), label: 'Inventario'),
            NavigationDestination(icon: Icon(Icons.shopping_cart), label: 'Compras'),
            NavigationDestination(icon: Icon(Icons.table_view), label: 'XLSX'),
          ],
        ),
      ),
    );
  }
}