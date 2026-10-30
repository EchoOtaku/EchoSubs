import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import '../core/model/errors.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// Optional diagnostics run inside the migration transaction. Throwing aborts it.
typedef MigrationCheckpoint = Future<void> Function();

@DriftDatabase(
  tables: [
    LedgerRecords,
    EntityVersions,
    ChangeBatches,
    CipherObjects,
    PendingUploads,
    ReceivedBatches,
    StoredConflicts,
    NotificationStates,
    QuarantinedObjects,
    SyncChannelConfigs,
    SyncObjectAcks,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase._(super.executor, this._migrationCheckpoint);
  final MigrationCheckpoint? _migrationCheckpoint;
  static Future<AppDatabase> open(
    File file, {
    MigrationCheckpoint? migrationCheckpoint,
  }) async {
    final db = AppDatabase._(
      NativeDatabase(
        file,
        setup: (connection) {
          final version =
              connection.select('PRAGMA user_version').first['user_version']
                  as int;
          if (version > 4) {
            throw const EchoFailure('incompatible', '数据库版本较新');
          }
        },
      ),
      migrationCheckpoint,
    );
    try {
      await db.customSelect('SELECT 1').get();
      return db;
    } on Object {
      await db.close();
      rethrow;
    }
  }

  static Future<AppDatabase> openDefault() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return open(
      File('${directory.path}${Platform.pathSeparator}echosubs.sqlite'),
    );
  }

  @override
  int get schemaVersion => 4;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => transaction(() async {
      await m.createAll();
      await customStatement('PRAGMA user_version = 4');
    }),
    onUpgrade: (m, from, to) async {
      if (from < 1 || from > 3 || to != 4)
        throw const EchoFailure('incompatible', '无法迁移数据库');
      await transaction(() async {
        if (from < 2) await m.createTable(notificationStates);
        if (from < 3) await m.createTable(quarantinedObjects);
        await m.createTable(syncChannelConfigs);
        await m.createTable(syncObjectAcks);
        // Drift normally updates user_version after onUpgrade returns. Write
        // it here as well so a crash cannot commit the schema without its version.
        await customStatement('PRAGMA user_version = 4');
        await _migrationCheckpoint?.call();
      });
    },
  );
}
