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
          if (version > 2) {
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
  int get schemaVersion => 2;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => transaction(() async {
      await m.createAll();
      await customStatement('PRAGMA user_version = 2');
    }),
    onUpgrade: (m, from, to) async {
      if (from != 1 || to != 2)
        throw const EchoFailure('incompatible', '无法迁移数据库');
      await transaction(() async {
        await m.createTable(notificationStates);
        // Drift normally updates user_version after onUpgrade returns. Write
        // it here as well so a crash cannot commit the schema without its version.
        await customStatement('PRAGMA user_version = 2');
        await _migrationCheckpoint?.call();
      });
    },
  );
}
