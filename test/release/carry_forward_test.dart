import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/core/model/civil_date.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/core/model/subscription.dart';
import 'package:echo_subs/features/ledger/ui/widgets.dart';
import 'package:echo_subs/features/reminders/reminder_adapter.dart';
import 'package:echo_subs/features/reminders/reminder_planner.dart';
import 'package:echo_subs/features/sync/transports/dav_response_parser.dart';
import '../support/ledger_harness.dart';
import '../reminders/reconciler_test.dart' show FakeReminderPlatform;
import '../reminders/planner_test.dart' show due, projection;
import 'package:timezone/data/latest_all.dart' as tzdata;

class CancelFailurePlatform extends FakeReminderPlatform {
  bool fail = false;
  @override
  Future<void> cancel(int id) async {
    if (fail) throw const EchoFailure('unavailable', '取消失败');
    await super.cancel(id);
  }
}

void main() {
  test(
    'immutable snapshot reuses its already computed causal projection',
    () async {
      final h = await LedgerHarness.create();
      try {
        final state = await h.repo.snapshot();
        expect(identical(state.projection, state.causal.projection), true);
        expect(identical(state.causal, state.causal), true);
      } finally {
        await h.close();
      }
    },
  );
  test('XML quoted terminators cannot bypass the 64 element depth bound', () {
    final text =
        '<d:multistatus xmlns:d="DAV:"><d:response><d:href>/objects/</d:href><d:status>HTTP/1.1 200 OK</d:status>${'<a x="/>">' * 65}${'<b x=">"/></a>' * 65}</d:response></d:multistatus>';
    expect(
      () => parseDavListing(
        Uint8List.fromList(utf8.encode(text)),
        Uri.parse('https://example.invalid/objects/'),
      ),
      throwsA(isA<EchoFailure>()),
    );
    final legal =
        '<d:multistatus xmlns:d="DAV:" x="/> >"><d:response><d:href>/objects/</d:href><d:status>HTTP/1.1 200 OK</d:status></d:response></d:multistatus>';
    expect(
      parseDavListing(
        Uint8List.fromList(utf8.encode(legal)),
        Uri.parse('https://example.invalid/objects/'),
      ),
      isEmpty,
    );
  });
  test(
    'first cancel failure preserves every old risk with desired empty',
    () async {
      tzdata.initializeTimeZones();
      final h = await LedgerHarness.create();
      final platform = CancelFailurePlatform();
      final adapter = DurableReminderAdapter(
        ReminderStateStore(h.db),
        platform,
        now: () => DateTime.utc(2026, 10, 20),
      );
      try {
        final events = planReminders(
          projection([due()]),
          DateTime.utc(2026, 10, 20),
        );
        await adapter.replace(events);
        expect(platform.queued, hasLength(3));
        platform.fail = true;
        await adapter.replace([]);
        expect(adapter.status.complete, false);
        expect(
          adapter.status.unscheduled.map((e) => e.stableKey).toSet(),
          events.map((e) => e.stableKey).toSet(),
        );
        expect(adapter.status.error, contains('旧提醒可能仍有效'));
        platform.fail = false;
        await adapter.replace([]);
        expect(platform.queued, isEmpty);
        // A stale platform cache can still report a durably cancelled ID. Its
        // cancellation must be confirmed again before removing it from risk.
        final saved = await ReminderStateStore(h.db).all();
        for (final record in saved) {
          platform.queued[record.id] = record.batch.fingerprint;
        }
        platform.fail = true;
        await adapter.replace([]);
        expect(
          adapter.status.unscheduled.map((e) => e.stableKey).toSet(),
          events.map((e) => e.stableKey).toSet(),
        );
        platform.fail = false;
        await adapter.replace([]);
      } finally {
        await adapter.close();
        await h.close();
      }
    },
  );
  testWidgets('gift entitlement stays valid when expected renewal is overdue', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubscriptionRow(
            value: Subscription(
              id: '00000000000000000000000000000001',
              name: '虚构赠送会员',
              entitlementEnd: CivilDate(2027, 1, 31),
              nextRenewalDate: CivilDate(2026, 10, 1),
            ),
            today: CivilDate(2026, 10, 30),
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.textContaining('预计续费已逾期'), findsOneWidget);
    expect(find.textContaining('权益已过期'), findsNothing);
  });
}
