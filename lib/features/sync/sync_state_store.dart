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
    Map<String, Object?> settings,
  ) : settings = Map.unmodifiable(settings);
  final SyncChannelKind kind;
  final String endpointId;
  final bool enabled;
  final Map<String, Object?> settings;
}

/// Local transport settings contain no credentials; secrets are referenced by
/// opaque endpoint IDs and live exclusively in the existing KeyVault.
class SyncStateStore {
  SyncStateStore(this.database, this.ledgerId);
  final AppDatabase database;
  final String ledgerId;
  Future<List<ChannelConfig>> configs() async => [
    for (final row in await (database.select(
      database.syncChannelConfigs,
    )..where((r) => r.ledgerId.equals(ledgerId))).get())
      ChannelConfig(
        SyncChannelKind.values.byName(row.channel),
        row.endpointId,
        row.enabled,
        (jsonDecode(row.body) as Map<String, dynamic>),
      ),
  ];
  Future<void> save(ChannelConfig config) async {
    final allowed = config.kind == SyncChannelKind.webdav
        ? {'root'}
        : {'address', 'port'};
    if (config.settings.keys.any((key) => !allowed.contains(key)))
      invalidModel();
    await database
        .into(database.syncChannelConfigs)
        .insertOnConflictUpdate(
          SyncChannelConfigsCompanion.insert(
            ledgerId: ledgerId,
            channel: config.kind.name,
            endpointId: config.endpointId,
            enabled: config.enabled,
            body: jsonEncode(config.settings),
          ),
        );
  }

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
