import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import 'cash_screen.dart';
import 'dashboard_screen.dart';
import 'inbox_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final inbox = context.select<Repository, int>((r) => r.inboxCount);
    final pages = [
      DashboardScreen(onOpenInbox: () => setState(() => _tab = 1)),
      const InboxScreen(),
      const CashScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.pie_chart_outline), label: 'Spending'),
          NavigationDestination(
              icon: Badge(isLabelVisible: inbox > 0, label: Text('$inbox'), child: const Icon(Icons.inbox_outlined)),
              label: 'Inbox'),
          const NavigationDestination(icon: Icon(Icons.payments_outlined), label: 'Cash'),
          const NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
