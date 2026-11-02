import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:echo_subs/features/reminders/reminder_adapter.dart';
import 'package:echo_subs/core/model/civil_date.dart';
import 'package:echo_subs/features/reminders/reminder_planner.dart';
import '../support/ledger_harness.dart';
import 'planner_test.dart';

/// Exercise the real Android adapter and plugin Dart method-channel protocol.
/// Memory registration changes before the separate persistence reply arrives.
/// Only the native integration test below can prove real Android disk writes.
class ChannelHarness {
  static const plugin = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  static const persistence = MethodChannel(
    'dev.echootaku.echo_subs/reminder_persistence',
  );
  final memory = <int, String>{};
  final disk = <int, String>{};
  final trace = <String>[];
  Completer<void> entered = Completer<void>();
  Completer<bool> release = Completer<bool>();
  void gate() {
    entered = Completer<void>();
    release = Completer<bool>();
  }

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(plugin, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'createNotificationChannel':
          return null;
        case 'areNotificationsEnabled':
          return true;
        case 'getNotificationChannels':
          return <Object>[];
        case 'pendingNotificationRequests':
          return [
            for (final e in memory.entries)
              {'id': e.key, 'payload': e.value, 'title': null, 'body': null},
          ];
        case 'zonedSchedule':
          final args = call.arguments as Map;
          memory[args['id'] as int] = args['payload'] as String;
          trace.add('schedule:${args['id']}');
          return null;
        case 'cancel':
          final id = (call.arguments as Map)['id'] as int;
          memory.remove(id);
          trace.add('cancel:$id');
          return null;
        default:
          throw StateError('Unexpected plugin method ${call.method}');
      }
    });
    messenger.setMockMethodCallHandler(persistence, (call) async {
      expect(call.method, 'flushScheduledNotifications');
      trace.add('barrier');
      if (!entered.isCompleted) entered.complete();
      final ok = await release.future;
      if (ok) {
        disk
          ..clear()
          ..addAll(memory);
      }
      return ok;
    });
  }

  void close() {
    if (!release.isCompleted) release.complete(false);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(plugin, null);
    messenger.setMockMethodCallHandler(persistence, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    tzdata.initializeTimeZones();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });
  for (final scenario in ['schedule', 'cancel', 'expired']) {
    final cancel = scenario == 'cancel';
    final expired = scenario == 'expired';
    test(
      'real Android channel $scenario waits for durable barrier and retries matching memory after failure',
      () async {
        final h = await LedgerHarness.create();
        final wire = ChannelHarness()..install();
        var now = DateTime.utc(2099, 10, 20);
        final a = DurableReminderAdapter(
          ReminderStateStore(h.db),
          AndroidReminderPlatform(),
          now: () => now,
        );
        final events = [
          planReminders(
            projection([due(date: CivilDate(2099, 10, 31))]),
            now,
          ).first,
        ];
        Future<void>? operation;
        try {
          if (cancel) {
            wire.release.complete(true);
            await a.replace(events);
            expect(a.status.complete, true);
            wire.gate();
            wire.trace.clear();
          }
          operation = a.replace(cancel ? [] : events);
          await Future.any([
            wire.entered.future,
            operation,
          ]).timeout(const Duration(seconds: 5));
          expect(
            wire.entered.isCompleted,
            true,
            reason: 'plugin success must be followed by persistence channel',
          );
          expect(wire.trace, [cancel ? 'cancel:1' : 'schedule:1', 'barrier']);
          expect(a.status.complete, false);
          expect(wire.memory.isEmpty, cancel);
          expect(wire.disk.isEmpty, !cancel);
          expect(
            (await ReminderStateStore(h.db).all()).single.phase,
            cancel ? ReminderPhase.cancelling : ReminderPhase.scheduling,
          );
          wire.release.complete(false);
          await operation;
          expect(a.status.complete, false);
          expect(a.status.error, isNotNull);
          expect(a.status.unscheduled, isNotEmpty);
          expect(
            (await ReminderStateStore(h.db).all()).single.phase,
            cancel ? ReminderPhase.cancelling : ReminderPhase.scheduling,
          );
          wire.gate();
          wire.trace.clear();
          if (expired) now = DateTime.utc(2099, 10, 24, 2);
          operation = a.replace(cancel ? [] : events);
          await Future.any([
            wire.entered.future,
            operation,
          ]).timeout(const Duration(seconds: 5));
          expect(
            wire.entered.isCompleted,
            true,
            reason: 'matching memory is not durable evidence after failure',
          );
          expect(wire.trace, [
            cancel || expired ? 'cancel:1' : 'schedule:1',
            'barrier',
          ]);
          expect(a.status.complete, false);
          wire.release.complete(true);
          await operation;
          expect(a.status.complete, true);
          expect(wire.disk, wire.memory);
          final saved = (await ReminderStateStore(h.db).all()).single;
          expect(saved.id, 1);
          expect(
            saved.phase,
            cancel || expired
                ? ReminderPhase.cancelled
                : ReminderPhase.scheduled,
          );
        } finally {
          if (!wire.release.isCompleted) wire.release.complete(false);
          await operation;
          await a.close();
          wire.close();
          await h.close();
        }
      },
    );
  }
}
