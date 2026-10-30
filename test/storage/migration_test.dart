import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/storage/app_database.dart';
import '../ledger/repository_test.dart' as fixtures;

void main() {
  for (final interrupt in [true, false]) {
    test('fictional v1 fixture migration interruption=$interrupt', () async {
      final f = fixtures.Fixture();
      await f.init();
      try {
        final objects = await f.repo.store.objects();
        await f.db.customStatement('DROP TABLE notification_states');
        await f.db.customStatement('DROP TABLE quarantined_objects');
        await f.db.customStatement('DROP TABLE sync_channel_configs');
        await f.db.customStatement('DROP TABLE sync_object_acks');
        await f.db.customStatement('PRAGMA user_version = 1');
        await f.db.close();
        if (interrupt) {
          await expectLater(
            AppDatabase.open(
              f.file,
              migrationCheckpoint: () async => throw StateError('interrupted'),
            ),
            throwsStateError,
          );
          // SQLite header's user_version remains 1 after aborted migration.
          final bytes = await File(f.file.path).readAsBytes();
          expect(bytes[63], 1);
        }
        f.db = await AppDatabase.open(f.file);
        final version = await f.db
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), 4);
        expect((await f.db.select(f.db.notificationStates).get()), isEmpty);
        final restored = await f.db.select(f.db.cipherObjects).get();
        expect(restored.length, objects.length);
        for (final object in objects) {
          expect(
            restored.singleWhere((r) => r.batchId == object.batchId).bytes,
            object.bytes,
          );
        }
      } finally {
        await f.dispose();
      }
    });
  }
  for (final interrupt in [true, false]) {
    test(
      'v3 to v4 preserves bytes and rollback interrupt=$interrupt',
      () async {
        final f = fixtures.Fixture();
        await f.init();
        try {
          final objects = await f.repo.store.objects();
          await f.db.customStatement('DROP TABLE sync_channel_configs');
          await f.db.customStatement('DROP TABLE sync_object_acks');
          await f.db.customStatement('PRAGMA user_version = 3');
          await f.db.close();
          if (interrupt) {
            await expectLater(
              AppDatabase.open(
                f.file,
                migrationCheckpoint: () async => throw StateError('interrupt'),
              ),
              throwsStateError,
            );
            expect((await f.file.readAsBytes())[63], 3);
          }
          f.db = await AppDatabase.open(f.file);
          expect(
            (await f.db.customSelect('PRAGMA user_version').getSingle())
                .read<int>('user_version'),
            4,
          );
          expect(await f.db.select(f.db.syncChannelConfigs).get(), isEmpty);
          expect(await f.db.select(f.db.syncObjectAcks).get(), isEmpty);
          final restored = await f.db.select(f.db.cipherObjects).get();
          expect(restored.length, objects.length);
          for (final object in objects) {
            expect(
              restored.singleWhere((o) => o.batchId == object.batchId).bytes,
              object.bytes,
            );
          }
        } finally {
          await f.dispose();
        }
      },
    );
  }
}
