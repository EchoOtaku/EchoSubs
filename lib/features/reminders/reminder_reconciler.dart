import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import '../../core/model/change_batch.dart';
import '../../core/model/ledger.dart';
import '../../storage/ledger_store.dart';
import 'reminder_adapter.dart';
import 'reminder_planner.dart';

class ReminderReconciler extends ChangeNotifier {
  ReminderReconciler({
    required this.snapshot,
    required this.adapter,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now {
    tzdata.initializeTimeZones();
  }
  final Future<LedgerSnapshot?> Function() snapshot;
  final ReminderAdapter adapter;
  final DateTime Function() now;
  Set<EntityRef> suppressed = {};
  String? error;
  bool _closed = false;
  bool _running = false;
  Future<void> _tail = Future.value();
  ReminderStatus get status => adapter.status;
  bool get complete =>
      !_running && error == null && suppressed.isEmpty && status.complete;
  Future<void> reconcile() {
    if (_closed) return Future.value();
    return _tail = _tail.then((_) async {
      if (_closed) return;
      _running = true;
      notifyListeners();
      try {
        final state = await snapshot();
        suppressed = state == null
            ? {}
            : {
                    ...state.causal.unsafeRefs,
                    ...state.projection.conflicts.expand((c) => c.affectedRefs),
                  }
                  .where(
                    (r) =>
                        r.kind == EntityKind.subscription ||
                        r.kind == EntityKind.ledgerConfig,
                  )
                  .toSet();
        final configMissing =
            state != null &&
            state.projection.entities[EntityRef(
                  EntityKind.ledgerConfig,
                  state.metadata.id,
                )]
                is! LedgerConfig;
        error = state == null
            ? '账本不可用，已停止预约'
            : configMissing
            ? '账本配置缺失或待确认，已停止预约'
            : null;
        await adapter.replace(
          state == null || configMissing
              ? []
              : planReminders(
                  state.projection,
                  now().toUtc(),
                  unsafeRefs: state.causal.unsafeRefs,
                ),
        );
      } on Object {
        error = '提醒计划暂不可用，已尝试取消旧预约';
        await adapter.replace([]);
      }
      _running = false;
      if (!_closed) notifyListeners();
    });
  }

  Future<void> requestPermission() async {
    await adapter.requestPermission();
    await reconcile();
  }

  Future<void> close() async {
    _closed = true;
    await _tail;
    await adapter.close();
    super.dispose();
  }
}
