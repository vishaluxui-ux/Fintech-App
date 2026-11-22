import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../services/notification_bridge.dart';
import 'cash_screen.dart';
import 'dashboard_screen.dart';
import 'inbox_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkShared());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _checkShared();
      context.read<NotificationBridge>().drain();
    }
  }

  /// A screenshot shared from a UPI app: read it like a bill.
  Future<void> _checkShared() async {
    final path = await context.read<NotificationBridge>().takeSharedImage().catchError((_) => null);
    if (path == null || !mounted) return;
    setState(() => _tab = 1);
    await scanBillFile(context, path);
  }

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
