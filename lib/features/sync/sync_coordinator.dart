import 'dart:async';
import '../../core/crypto/ledger_keys.dart';
import '../../core/model/errors.dart';
import '../../storage/ledger_store.dart';
import 'sync_engine.dart';
import 'sync_status.dart';
import 'sync_state_store.dart';
import 'transports/sync_transport.dart';

class SyncChannel {
  const SyncChannel(this.kind, this.endpointId, this.open);
  final SyncChannelKind kind;
  final String endpointId;
  final Future<SyncTransport> Function() open;
}

class SyncCancellation implements CancellationToken {
  @override
  bool isCancelled = false;
  void cancel() => isCancelled = true;
}

/// A coordinator is bound to one ledger and one immutable channel configuration.
/// Each operation owns fresh transports. Closing is terminal.
class SyncCoordinator {
  SyncCoordinator({
    required this.store,
    required this.authenticate,
    required Iterable<SyncChannel> channels,
    this.loadChannels,
  }) : channels = List.unmodifiable(channels);
  final LedgerStore store;
  final Future<LedgerKeys> Function() authenticate;
  final List<SyncChannel> channels;
  final Future<List<SyncChannel>> Function()? loadChannels;
  final _lastSuccess = <String, DateTime>{};
  final _known = <String, Set<String>>{};
  final _events = StreamController<SyncStatus>.broadcast();
  final _active = <SyncTransport>{};
  Future<SyncReport>? _flight;
  bool _closed = false;
  SyncStatus status = const SyncStatus();
  Stream<SyncStatus> watchStatus() => _events.stream;
  void retry(SyncChannelKind kind, int attempt) => _emit(
    SyncStatus(
      running: true,
      report: status.report,
      retryMessage:
          '${kind == SyncChannelKind.webdav ? 'WebDAV' : '局域网'} 正在重试（$attempt / 2）',
    ),
  );
  void _emit(SyncStatus value) {
    status = value;
    if (!_closed) _events.add(value);
  }

  Future<SyncReport> sync({required CancellationToken token}) {
    if (_closed) return Future.error(const EchoFailure('cancelled', '同步已关闭'));
    return _flight ??= _run(token).whenComplete(() => _flight = null);
  }

  void _check(CancellationToken token) {
    if (_closed || token.isCancelled)
      throw const EchoFailure('cancelled', '同步已取消');
  }

  Future<Map<String, StoredObject>> _archive() async => {
    for (final object in [
      ...await store.objects(),
      ...(await store.quarantinedObjects()).map((q) => q.object),
    ])
      '${object.batchId}:${object.sha256}': object,
  };
  Future<SyncReport> _run(CancellationToken token) async {
    _emit(SyncStatus(running: true, report: status.report));
    final results = <SyncChannel, ChannelReport>{};
    _known.clear();
    final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (token.isCancelled || _closed) {
        for (final transport in _active.toList()) {
          unawaited(transport.close());
        }
      }
    });
    try {
      for (final channel in await loadChannels?.call() ?? channels) {
        final result = await _channel(channel, token);
        results[channel] = result;
      }
      final state = await store.snapshot();
      final archive = await _archive();
      final finalized = <SyncChannelKind, List<ChannelReport>>{};
      for (final entry in results.entries) {
        final channel = entry.key, result = entry.value;
        final known = _known[channel.endpointId] ?? {};
        final pending = archive.keys
            .where((key) => !known.contains(key))
            .length;
        final complete =
            result.errors.isEmpty &&
            pending == 0 &&
            state.projection.pendingBatchIds.isEmpty &&
            state.projection.conflicts.isEmpty &&
            state.quarantinedBatchIds.isEmpty;
        if (complete) _lastSuccess[channel.endpointId] = DateTime.now().toUtc();
        (finalized[channel.kind] ??= []).add(
          ChannelReport(
            enabled: true,
            uploaded: result.uploaded,
            downloaded: result.downloaded,
            pendingUpload: pending,
            pendingDependencies: state.projection.pendingBatchIds.length,
            conflicts: state.projection.conflicts.length,
            quarantined: state.quarantinedBatchIds.length,
            errors: result.errors,
            errorCodes: result.errorCodes,
            lastSuccess: _lastSuccess[channel.endpointId],
          ),
        );
      }
      final report = SyncReport(
        _combine(finalized[SyncChannelKind.webdav]),
        _combine(finalized[SyncChannelKind.lan]),
      );
      _emit(SyncStatus(report: report));
      return report;
    } finally {
      timer.cancel();
    }
  }

  Future<ChannelReport> _channel(
    SyncChannel channel,
    CancellationToken token,
  ) async {
    var uploaded = 0, downloaded = 0;
    final known = <String>{};
    _known[channel.endpointId] = known;
    final errors = <String>[];
    final errorCodes = <String>[];
    SyncTransport? transport;
    try {
      _check(token);
      final engine = SyncEngine(store, await authenticate());
      _check(token);
      transport = await channel.open();
      _active.add(transport);
      _check(token);
      final metadata = await store.metadata();
      await transport.publishMetadata(metadata);
      final remote = await transport.readMetadata();
      if (remote.id != metadata.id ||
          !_equal(remote.encode(), metadata.encode())) {
        throw const EchoFailure('conflict', '通道指向不同账本或恢复元数据');
      }
      await for (final ref in transport.listObjects(token)) {
        _check(token);
        final object = await transport.read(ref);
        _check(token);
        if (object.batchId != ref.batchId || object.sha256 != ref.sha256) {
          throw const EchoFailure('integrity', '通道对象与目录不匹配');
        }
        await engine.ingest(object);
        await SyncStateStore(
          store.database,
          store.ledgerId,
        ).acknowledge(channel.kind, channel.endpointId, object);
        known.add('${object.batchId}:${object.sha256}');
        downloaded++;
      }
      // Includes received objects and every authenticated collision candidate.
      for (final entry in (await _archive()).entries) {
        _check(token);
        if (known.contains(entry.key)) continue;
        await engine.ingest(entry.value); // Never relay unverified local bytes.
        await transport.put(entry.value);
        _check(token);
        known.add(entry.key);
        await SyncStateStore(
          store.database,
          store.ledgerId,
        ).acknowledge(channel.kind, channel.endpointId, entry.value);
        uploaded++;
      }
    } on Object catch (e) {
      errors.add(e is EchoFailure ? e.safeMessage : '通道暂不可用，请重试');
      errorCodes.add(e is EchoFailure ? e.code : 'unavailable');
    } finally {
      if (transport != null) {
        _active.remove(transport);
        try {
          await transport.close();
        } on Object {
          errors.add('通道关闭未完成');
          errorCodes.add('unavailable');
        }
      }
    }
    final state = await store.snapshot();
    final pending = (await _archive()).keys
        .where((key) => !known.contains(key))
        .length;
    return ChannelReport(
      enabled: true,
      uploaded: uploaded,
      downloaded: downloaded,
      pendingUpload: pending,
      pendingDependencies: state.projection.pendingBatchIds.length,
      conflicts: state.projection.conflicts.length,
      quarantined: state.quarantinedBatchIds.length,
      errors: List.unmodifiable(errors),
      errorCodes: List.unmodifiable(errorCodes),
      lastSuccess: _lastSuccess[channel.endpointId],
    );
  }

  Future<void> close() async {
    _closed = true;
    await Future.wait(_active.toList().map((t) => t.close()));
    await _flight;
    await _events.close();
  }
}

bool _equal(List<int> a, List<int> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
ChannelReport _combine(List<ChannelReport>? values) {
  if (values == null || values.isEmpty) return const ChannelReport();
  int sum(int Function(ChannelReport) field) =>
      values.fold(0, (n, r) => n + field(r));
  return ChannelReport(
    enabled: true,
    uploaded: sum((r) => r.uploaded),
    downloaded: sum((r) => r.downloaded),
    pendingUpload: sum((r) => r.pendingUpload),
    pendingDependencies: values
        .map((r) => r.pendingDependencies)
        .reduce((a, b) => a > b ? a : b),
    conflicts: values.map((r) => r.conflicts).reduce((a, b) => a > b ? a : b),
    quarantined: values
        .map((r) => r.quarantined)
        .reduce((a, b) => a > b ? a : b),
    errors: List.unmodifiable(values.expand((r) => r.errors)),
    errorCodes: List.unmodifiable(values.expand((r) => r.errorCodes)),
    lastSuccess: values.every((r) => r.lastSuccess != null)
        ? values
              .map((r) => r.lastSuccess!)
              .reduce((a, b) => a.isBefore(b) ? a : b)
        : null,
  );
}
