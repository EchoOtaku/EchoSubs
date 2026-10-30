import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:xml/xml.dart';
import 'package:echo_subs/features/reminders/reminder_adapter.dart';
import 'package:echo_subs/features/reminders/reminder_planner.dart';
import 'package:echo_subs/storage/app_database.dart';

/// Two controlled launches using support/run_native.ps1. After phase one, the
/// controller force-stops ONLY the integration package and relaunches this target.
/// No production bootstrap, secure vault, personal ledger or app data cleanup.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('isolated Android real plugin registration and force-stop recovery', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('EchoSubs 隔离提醒测试（虚构条目）'))),
      ),
    );
    await tester.runAsync(() async {
      if (!Platform.isAndroid)
        throw StateError('This target verifies Android only');
      final support = await getApplicationSupportDirectory();
      if (!support.path.contains('/dev.echootaku.echo_subs.integration/'))
        throw StateError('Refusing non-isolated support directory');
      Future<List<int>> persistedIds() async {
        final file = File(
          '${support.parent.path}/shared_prefs/scheduled_notifications.xml',
        );
        final document = XmlDocument.parse(await file.readAsString());
        final cache = document
            .findAllElements('string')
            .singleWhere(
              (e) => e.getAttribute('name') == 'scheduled_notifications',
            );
        return (jsonDecode(cache.innerText) as List)
            .map((e) => (e as Map)['id'] as int)
            .toList();
      }

      tzdata.initializeTimeZones();
      final directory = Directory('${support.path}/task9-reminders-v1');
      await directory.create(recursive: true);
      final marker = File('${directory.path}/checkpoint.json');
      final old = await marker.exists()
          ? jsonDecode(await marker.readAsString()) as Map<String, dynamic>
          : null;
      if (old != null && !['restart-ready', 'complete'].contains(old['phase']))
        throw StateError(
          'Unknown fixture state retained; inspect before retry',
        );
      final recovering = old != null;
      final anchor = old == null
          ? DateTime.now().toUtc().add(const Duration(days: 2))
          : DateTime.parse(old['anchor'] as String);
      final events = <ReminderEvent>[
        for (var i = 1; i <= 3; i++)
          ReminderEvent(
            ledgerId: '00000000000000000000000000000900',
            stableKey: 'fictional-native/$i',
            subscriptionId: '00000000000000000000000000000901',
            scheduledAtUtc: anchor.add(Duration(days: i)),
            ruleId: 'fictional:$i',
            name: '虚构原生测试订阅',
          ),
      ];
      final db = await AppDatabase.open(
        File('${directory.path}/mapping.sqlite'),
      );
      final platform = AndroidReminderPlatform();
      final adapter = DurableReminderAdapter(ReminderStateStore(db), platform);
      var success = false;
      try {
        final before = await platform.permission();
        debugPrint(
          'REMINDERS_NATIVE_PERMISSION_BEFORE=${before.name}; Android12 has no Android13 runtime dialog',
        );
        // The task explicitly authorizes this native notification test. On API32
        // this only checks the existing setting, never auto-grants anything.
        expect(await platform.requestPermission(), ReminderPermission.granted);
        if (recovering) {
          expect(
            (await ReminderStateStore(db).all()).map((r) => r.id).toList(),
            old['ids'],
          );
          debugPrint('REMINDERS_NATIVE_REOPEN_DURABLE_IDS_VERIFIED');
        }
        await adapter.replace(events);
        expect(adapter.status.complete, true, reason: adapter.status.error);
        final records = await ReminderStateStore(db).all();
        final ids = records.map((r) => r.id).toList()..sort();
        expect(ids.length, 3);
        expect((await platform.pending()).keys, containsAll(ids));
        expect(await persistedIds(), unorderedEquals(ids));
        await adapter.replace(events); // same key and same IDs, never duplicate
        expect((await platform.pending()).keys.where(ids.contains).length, 3);
        await platform.testNotification();
        expect(
          (await platform.plugin.getActiveNotifications()).any(
            (n) => n.id == 0 && n.title == 'EchoSubs 测试提醒',
          ),
          true,
        );
        await platform.cancel(0);
        if (recovering) {
          await adapter.replace([]);
          expect(adapter.status.complete, true);
          expect((await platform.pending()).keys.where(ids.contains), isEmpty);
          expect(await persistedIds(), isEmpty);
          debugPrint('REMINDERS_NATIVE_DURABLE_CACHE_EMPTY_NO_DELAY');
          // No fixed delay: production schedule/cancel Futures now include the
          // native SharedPreferences commit barrier. Host inspects disk directly.
          await marker.writeAsString(
            jsonEncode({
              'phase': 'complete',
              'anchor': anchor.toIso8601String(),
              'ids': ids,
            }),
            flush: true,
          );
          debugPrint('REMINDERS_NATIVE_RECOVERY_AND_CANCELLATION_OK');
        } else {
          await marker.writeAsString(
            jsonEncode({
              'phase': 'restart-ready',
              'anchor': anchor.toIso8601String(),
              'ids': ids,
            }),
            flush: true,
          );
          debugPrint('REMINDERS_NATIVE_READY_FOR_ISOLATED_FORCE_STOP ids=$ids');
        }
        success = true;
      } finally {
        if (!success) {
          await adapter.replace([]);
          await platform.cancel(0);
        }
        await adapter.close();
        await db.close();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}
