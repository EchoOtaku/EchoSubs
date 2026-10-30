import 'dart:convert';
import 'package:drift/drift.dart';
import '../../core/model/errors.dart';
import '../../storage/app_database.dart';
import '../../storage/ledger_store.dart';
import 'sync_status.dart';

class ChannelConfig {
  ChannelConfig(
    this.kind,
    this.endpointId,
    this.enabled,
    Map<String, Object?> settings, {
    Map<String, DateTime> successes = const {},
  }) : settings = Map.unmodifiable(settings),
       successes = Map.unmodifiable(successes);
  final SyncChannelKind kind;
  final String endpointId;
  final bool enabled;
  final Map<String, Object?> settings;
  final Map<String, DateTime> successes;
  DateTime? get lastSuccess => successes.isEmpty
      ? null
      : successes.values.reduce((a, b) => a.isBefore(b) ? a : b);
}

/// Local transport settings contain no credentials; secrets are referenced by
/// opaque endpoint IDs and live exclusively in the existing KeyVault.
class SyncStateStore {
  SyncStateStore(this.database, this.ledgerId);
  final AppDatabase database;
  final String ledgerId;
  static const _successKey = '_lastSuccessUtcByEndpoint';
  Map<String, DateTime> _successes(Map<String, dynamic> body) => parseModel(() {
    final values = body[_successKey] as Map<String, dynamic>? ?? {};
    return {for (final entry in values.entries) entry.key: _utc(entry.value)};
  });
  DateTime _utc(Object? value) {
    final date = DateTime.parse(value as String);
    if (!date.isUtc) invalidModel();
    return date;
  }

  ChannelConfig _config(SyncChannelConfig row) {
    final body = jsonDecode(row.body) as Map<String, dynamic>;
    final successes = _successes(body);
    body.remove(_successKey);
    return ChannelConfig(
      SyncChannelKind.values.byName(row.channel),
      row.endpointId,
      row.enabled,
      body,
      successes: successes,
    );
  }

  Future<List<ChannelConfig>> configs() async => [
    for (final row in await (database.select(
      database.syncChannelConfigs,
    )..where((r) => r.ledgerId.equals(ledgerId))).get())
      _config(row),
  ];
  Future<void> save(ChannelConfig config) async {
    final allowed = config.kind == SyncChannelKind.webdav
        ? {'root'}
        : {'address', 'port'};
    if (config.settings.keys.any((key) => !allowed.contains(key)))
      invalidModel();
    await database.transaction(() async {
      final existing =
          await (database.select(database.syncChannelConfigs)..where(
                (r) =>
                    r.ledgerId.equals(ledgerId) &
                    r.channel.equals(config.kind.name),
              ))
              .getSingleOrNull();
      final body = <String, Object?>{...config.settings};
      if (existing != null && existing.endpointId == config.endpointId) {
        final retained =
            (jsonDecode(existing.body) as Map<String, dynamic>)[_successKey];
        if (retained != null) body[_successKey] = retained;
      }
      await database
          .into(database.syncChannelConfigs)
          .insertOnConflictUpdate(
            SyncChannelConfigsCompanion.insert(
              ledgerId: ledgerId,
              channel: config.kind.name,
              endpointId: config.endpointId,
              enabled: config.enabled,
              body: jsonEncode(body),
            ),
          );
    });
  }

  /// Change only the matching endpoint's enabled flag. Selection is checked
  /// inside the transaction, including after the asynchronous write, so a
  /// superseded operation rolls back rather than touching another ledger.
  Future<void> setEnabled(
    SyncChannelKind kind,
    String endpoint,
    bool enabled, {
    required void Function() validateSelection,
  }) => database.transaction(() async {
    validateSelection();
    final changed =
        await (database.update(database.syncChannelConfigs)..where(
              (r) =>
                  r.ledgerId.equals(ledgerId) &
                  r.channel.equals(kind.name) &
                  r.endpointId.equals(endpoint),
            ))
            .write(SyncChannelConfigsCompanion(enabled: Value(enabled)));
    validateSelection();
    if (changed != 1) throw const EchoFailure('conflict', '通道配置已变化，请重新打开设置');
  });

  /// A success write updates only the timestamp field of the *current* matching
  /// endpoint under the SQLite transaction. It cannot restore an old enabled
  /// flag, settings payload, or endpoint after the user changes configuration.
  Future<void> recordSuccess(
    SyncChannelKind kind,
    String configEndpoint,
    String transportEndpoint,
    DateTime at,
  ) => database.transaction(() async {
    final row =
        await (database.select(database.syncChannelConfigs)..where(
              (r) =>
                  r.ledgerId.equals(ledgerId) &
                  r.channel.equals(kind.name) &
                  r.endpointId.equals(configEndpoint),
            ))
            .getSingleOrNull();
    if (row == null) return;
    final body = jsonDecode(row.body) as Map<String, dynamic>;
    final successes = _successes(body);
    final previous = successes[transportEndpoint];
    if (previous == null || at.toUtc().isAfter(previous))
      successes[transportEndpoint] = at.toUtc();
    body[_successKey] = {
      for (final entry in successes.entries)
        entry.key: entry.value.toIso8601String(),
    };
    await (database.update(database.syncChannelConfigs)..where(
          (r) =>
              r.ledgerId.equals(ledgerId) &
              r.channel.equals(kind.name) &
              r.endpointId.equals(configEndpoint),
        ))
        .write(SyncChannelConfigsCompanion(body: Value(jsonEncode(body))));
  });

  Future<void> acknowledge(
    SyncChannelKind kind,
    String endpoint,
    StoredObject object,
  ) async {
    if (object.ledgerId != ledgerId) invalidModel();
    await database
        .into(database.syncObjectAcks)
        .insert(
          SyncObjectAcksCompanion.insert(
            ledgerId: ledgerId,
            channel: kind.name,
            endpointId: endpoint,
            batchId: object.batchId,
            sha256: object.sha256,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<Set<String>> acknowledgements(
    SyncChannelKind kind,
    String endpoint,
  ) async => {
    for (final row
        in await (database.select(database.syncObjectAcks)..where(
              (r) =>
                  r.ledgerId.equals(ledgerId) &
                  r.channel.equals(kind.name) &
                  r.endpointId.equals(endpoint),
            ))
            .get())
      '${row.batchId}:${row.sha256}',
  };
}
