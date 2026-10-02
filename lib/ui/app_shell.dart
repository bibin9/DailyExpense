import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../state/app_gate_controller.dart';
import '../state/categories_controller.dart';
import '../state/home_controller.dart';
import '../state/report_controller.dart';
import 'categories_screen.dart';
import 'home_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';

/// Bottom navigation: Home · Reports · Categories · Settings.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.gate});
  final AppGateController gate;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final session = widget.gate.session!;
  late final home = HomeController(session);
  late final reports = ReportController(session);
  late final categories = CategoriesController(session);
  int _tab = 0;

  @override
  void dispose() {
    home.dispose();
    reports.dispose();
    categories.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        controller: home,
        clientName: widget.gate.config.displayClientName,
      ),
      ReportsScreen(controller: reports),
      CategoriesScreen(controller: categories),
      SettingsScreen(
        gate: widget.gate,
        onOpenCategories: () => setState(() => _tab = 2),
      ),
    ];
    return Column(
      children: [
        if (AppConfig.devBypassActive)
          const Material(
            color: Color(0xFFB3261E),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.all(4),
                child: Text(
                  'DEVELOPMENT BYPASS – NOT FOR RELEASE',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
        Expanded(
          child: Scaffold(
            body: IndexedStack(index: _tab, children: pages),
            // Labels capped at 1.3x so "Categories" never wraps mid-word.
            bottomNavigationBar: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) {
                  // A confirmation belongs to the tab it was shown on; never let
                  // it cover the next tab's buttons (e.g. Add Expense).
                  ScaffoldMessenger.of(context).removeCurrentSnackBar();
                  if (i == 1) reports.load();
                  if (i == 2) categories.load();
                  setState(() => _tab = i);
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.bar_chart_outlined),
                    selectedIcon: Icon(Icons.bar_chart),
                    label: 'Reports',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.category_outlined),
                    selectedIcon: Icon(Icons.category),
                    label: 'Categories',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: 'Settings',
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
