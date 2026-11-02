import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_subs/core/model/change_batch.dart';
import 'package:echo_subs/core/model/civil_date.dart';
import 'package:echo_subs/core/model/errors.dart';
import 'package:echo_subs/core/model/ids.dart';
import 'package:echo_subs/core/model/ledger.dart';
import 'package:echo_subs/core/model/money.dart';
import 'package:echo_subs/core/model/payment.dart';
import 'package:echo_subs/core/model/subscription.dart';

const a = '00000000000000000000000000000001';
const b = '00000000000000000000000000000002';
const c = '00000000000000000000000000000003';
void main() {
  test('IDs are 128 bit random lowercase hexadecimal', () {
    expect(newId(), matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(newId(), isNot(newId()));
    expect(() => validateId('bad'), throwsA(isA<EchoFailure>()));
  });
  test('all immutable entities round trip with value equality', () {
    final values = <LedgerEntity>[
      LedgerConfig(a, 'Asia/Shanghai'),
      Category(a, 'Example'),
      Subscription(
        id: a,
        name: 'Example',
        provider: 'Example provider',
        purchaseChannel: 'Voucher',
        paymentMethod: 'Example card',
        websiteUrl: 'https://example.invalid',
        notes: 'Fictional',
        categoryId: b,
        status: SubscriptionStatus.active,
        billingType: BillingType.fixed,
        price: Money('CNY', 100, 2),
        cycle: BillingCycle(CycleUnit.month, 1),
        cycleAnchor: CivilDate(2028, 1, 31),
        startDate: CivilDate(2028, 1, 1),
        entitlementEnd: CivilDate(2029, 4, 30),
        nextRenewalDate: CivilDate(2029, 1, 31),
        autoRenew: true,
        reminderRule: ReminderRule(
          daysBefore: [2, 0],
          localHour: 10,
          localMinute: 30,
        ),
      ),
      Payment(
        id: a,
        subscriptionId: b,
        amount: Money('CNY', 0, 2),
        paidOn: CivilDate(2028, 1, 1),
        periodStart: CivilDate(2028, 1, 1),
        periodEnd: CivilDate(2029, 4, 30),
      ),
    ];
    for (final entity in values) {
      final mutation = Mutation(EntityRef(entity.kind, a), [b], entity);
      final batch = ChangeBatch(
        id: c,
        ledgerId: a,
        deviceId: b,
        createdAtUtc: DateTime.utc(2028),
        mutations: [mutation],
      );
      final restored = ChangeBatch.fromJson(
        jsonDecode(jsonEncode(batch.toJson())) as Map<String, dynamic>,
      );
      expect(restored, batch);
      expect(restored.hashCode, batch.hashCode);
      expect(restored.mutations.single.value, entity);
      if (entity is Subscription) {
        final value = restored.mutations.single.value! as Subscription;
        expect(
          [
            value.provider,
            value.purchaseChannel,
            value.paymentMethod,
            value.websiteUrl,
            value.notes,
            value.categoryId,
          ],
          [
            'Example provider',
            'Voucher',
            'Example card',
            'https://example.invalid',
            'Fictional',
            b,
          ],
        );
        expect(
          value.reminderRule,
          ReminderRule(daysBefore: [2, 0], localHour: 10, localMinute: 30),
        );
        expect(value.entitlementEnd, CivilDate(2029, 4, 30));
        expect(value.nextRenewalDate, CivilDate(2029, 1, 31));
      }
      expect(() => batch.mutations.clear(), throwsUnsupportedError);
    }
  });
  test(
    'tombstones collection ordering and JSON map order preserve equality',
    () {
      final left = Mutation(EntityRef(EntityKind.category, a), [b, c], null);
      final right = Mutation(EntityRef(EntityKind.category, a), [c, b], null);
      expect(left, right);
      expect(left.hashCode, right.hashCode);
      final category = Category.fromJson({'name': 'Example', 'id': a});
      expect(category, Category(a, 'Example'));
      expect(ReminderRule().daysBefore, [7, 3, 1]);
      expect(() => ReminderRule().daysBefore.clear(), throwsUnsupportedError);
      final conflict = Conflict(
        id: a,
        competingBatchIds: [b, c],
        affectedRefs: [EntityRef(EntityKind.category, a)],
      );
      expect(Conflict.fromJson(conflict.toJson()), conflict);
      final projection = LedgerProjection(
        entities: {EntityRef(EntityKind.category, a): category},
        conflicts: [conflict],
        pendingBatchIds: [b],
      );
      expect(LedgerProjection.fromJson(projection.toJson()), projection);
    },
  );
  test('invalid refs dates reminders batches and refund rejected safely', () {
    expect(
      () => Mutation(
        EntityRef(EntityKind.payment, a),
        [],
        Category(a, 'Example'),
      ),
      throwsA(isA<EchoFailure>()),
    );
    expect(() => ReminderRule(daysBefore: [-1]), throwsA(isA<EchoFailure>()));
    expect(() => ReminderRule(localHour: 24), throwsA(isA<EchoFailure>()));
    expect(
      () => Payment(
        id: a,
        subscriptionId: b,
        amount: Money('CNY', 1, 2),
        paidOn: CivilDate(2028, 1, 1),
        periodStart: CivilDate(2028, 2, 1),
        periodEnd: CivilDate(2028, 1, 1),
      ),
      throwsA(isA<EchoFailure>()),
    );
    expect(
      () => ChangeBatch.fromJson({'private-secret': 'do not echo'}),
      throwsA(
        isA<EchoFailure>().having(
          (error) => error.toString(),
          'safe error',
          isNot(contains('do not echo')),
        ),
      ),
    );
    expect(
      () => ChangeBatch(
        id: c,
        ledgerId: a,
        deviceId: b,
        createdAtUtc: DateTime.utc(2028),
        mutations: [],
      ),
      throwsA(isA<EchoFailure>()),
    );
  });
  test(
    'batch atomic unit cannot contain duplicate refs or local timestamp',
    () {
      final mutation = Mutation(
        EntityRef(EntityKind.category, a),
        [],
        Category(a, 'Example'),
      );
      expect(
        () => ChangeBatch(
          id: c,
          ledgerId: a,
          deviceId: b,
          createdAtUtc: DateTime.utc(2028),
          mutations: [mutation, mutation],
        ),
        throwsA(isA<EchoFailure>()),
      );
      expect(
        () => ChangeBatch(
          id: c,
          ledgerId: a,
          deviceId: b,
          createdAtUtc: DateTime(2028),
          mutations: [mutation],
        ),
        throwsA(isA<EchoFailure>()),
      );
      expect(
        () => Mutation(
          EntityRef(EntityKind.category, b),
          [],
          Category(a, 'Example'),
        ),
        throwsA(isA<EchoFailure>()),
      );
    },
  );
}
