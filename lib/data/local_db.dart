import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';

/// Device-first store (ACC-02). Every write lands here first and is queued
/// in `outbox` for [SyncService] to push when online.
class LocalDb {
  final Database db;
  LocalDb(this.db);

  static Future<LocalDb> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'spend.db');
    final db = await f.openDatabase(dbPath,
        options: OpenDatabaseOptions(version: 1, onCreate: (db, _) async {
          await db.execute('''CREATE TABLE captures(id TEXT PRIMARY KEY, source TEXT NOT NULL,
            source_app TEXT, captured_at TEXT NOT NULL, bill_total REAL, image_path TEXT, withdrawal_id TEXT)''');
          await db.execute('''CREATE TABLE items(id TEXT PRIMARY KEY, capture_id TEXT NOT NULL, name TEXT NOT NULL,
            amount REAL NOT NULL, category_id TEXT NOT NULL, status TEXT NOT NULL, spent_at TEXT NOT NULL,
            flag_reason TEXT, payee TEXT, updated_at TEXT NOT NULL)''');
          await db.execute('''CREATE TABLE withdrawals(id TEXT PRIMARY KEY, amount REAL NOT NULL, at TEXT NOT NULL,
            source_app TEXT)''');
          await db.execute('CREATE TABLE outbox(tbl TEXT NOT NULL, id TEXT NOT NULL, PRIMARY KEY(tbl, id))');
        }));
    return LocalDb(db);
  }

  Future<void> _put(String table, Map<String, Object?> row) => db.transaction((t) async {
        await t.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
        await t.insert('outbox', {'tbl': table, 'id': row['id']}, conflictAlgorithm: ConflictAlgorithm.ignore);
      });

  Future<void> putCapture(Capture c) => _put('captures', c.toMap());
  Future<void> putItem(Item i) => _put('items', i.toMap());
  Future<void> putWithdrawal(Withdrawal w) => _put('withdrawals', w.toMap());

  Future<List<Capture>> captures() async => (await db.query('captures')).map(Capture.fromMap).toList();
  Future<List<Item>> items() async => (await db.query('items')).map(Item.fromMap).toList();
  Future<List<Withdrawal>> withdrawals() async => (await db.query('withdrawals')).map(Withdrawal.fromMap).toList();

  Future<List<({String table, Map<String, Object?> row})>> pending() async {
    final out = <({String table, Map<String, Object?> row})>[];
    for (final o in await db.query('outbox')) {
      final t = o['tbl'] as String;
      final rows = await db.query(t, where: 'id = ?', whereArgs: [o['id']]);
      if (rows.isNotEmpty) out.add((table: t, row: rows.first));
    }
    return out;
  }

  Future<void> markSynced(String table, String id) =>
      db.delete('outbox', where: 'tbl = ? AND id = ?', whereArgs: [table, id]);

  /// Rows pulled from the server: stored without re-queueing.
  Future<void> applyRemote(String table, Map<String, Object?> row) async {
    final queued = await db.query('outbox', where: 'tbl = ? AND id = ?', whereArgs: [table, row['id']]);
    if (queued.isNotEmpty) return; // local change not yet pushed wins
    await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> wipe() async {
    for (final t in ['captures', 'items', 'withdrawals', 'outbox']) {
      await db.delete(t);
    }
  }
}
