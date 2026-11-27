import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/local_db.dart';
import 'data/repository.dart';
import 'data/settings.dart';
import 'services/auth_service.dart';
import 'services/bill_parser.dart';
import 'services/alert_ingestor.dart';
import 'services/alert_reader.dart';
import 'services/notification_bridge.dart';
import 'services/refresh_service.dart';
import 'services/reminder_service.dart';
import 'services/sync_service.dart';
import 'services/voice_service.dart';
import 'ui/home_shell.dart';
import 'ui/sign_in_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabasePublishableKey);
  final client = Supabase.instance.client;
  final db = await LocalDb.open();
  final settings = Settings(await SharedPreferences.getInstance());
  final sync = SyncService(db, client);
  final repo = Repository(db, settings, onLocalChange: sync.sync);
  sync.repo = repo;
  await repo.load();
  sync.start();

  final bridge = NotificationBridge(AlertIngestor(repo, AlertReader(client).read))..start();
  final refresher = RefreshService(repo, bridge, sync);
  final reminders = ReminderService(repo);
  await reminders.init();

  runApp(MultiProvider(providers: [
    ChangeNotifierProvider.value(value: repo),
    ChangeNotifierProvider.value(value: settings),
    Provider.value(value: AuthService(client)),
    Provider.value(value: BillParser(client)),
    Provider.value(value: bridge),
    Provider.value(value: refresher),
    Provider.value(value: VoiceService()),
    Provider.value(value: reminders),
    Provider.value(value: sync),
  ], child: const SpendApp()));
}

class SpendApp extends StatelessWidget {
  const SpendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpendSense',
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, _) {
          final signedIn = Supabase.instance.client.auth.currentSession != null;
          if (signedIn) context.read<SyncService>().sync();
          return signedIn ? const HomeShell() : const SignInScreen();
        },
      ),
    );
  }
}
