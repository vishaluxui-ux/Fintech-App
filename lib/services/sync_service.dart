import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local_db.dart';
import '../data/repository.dart';

/// ACC-02: pushes the local outbox to Supabase when online, then pulls.
/// Rows carry `user_id`; RLS on the server limits each user to their own rows.
class SyncService {
  final LocalDb db;
  final SupabaseClient client;
  Repository? repo;
  bool _running = false;
  StreamSubscription? _sub;

  SyncService(this.db, this.client);

  void start() {
    _sub = Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) sync();
    });
    sync();
  }

  void dispose() => _sub?.cancel();

  Future<void> sync() async {
    final user = client.auth.currentUser;
    if (_running || user == null) return;
    _running = true;
    try {
      for (final p in await db.pending()) {
        final row = {...p.row, 'user_id': user.id};
        if (p.table == 'captures') row['image_path'] = null; // photos never leave the phone
        await client.from(p.table).upsert(row);
        await db.markSynced(p.table, p.row['id'] as String);
      }
      for (final t in ['captures', 'items', 'withdrawals']) {
        final rows = await client.from(t).select().eq('user_id', user.id);
        for (final r in rows) {
          final row = Map<String, Object?>.from(r)
            ..remove('user_id')
            ..remove('created_at');
          if (t == 'captures') row['image_path'] = null; // photos stay on device
          await db.applyRemote(t, row);
        }
      }
      await repo?.load();
    } catch (_) {
      // Offline or server error: the outbox keeps everything for the next attempt.
    } finally {
      _running = false;
    }
  }
}
