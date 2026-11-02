import 'dart:async';
import '../../core/crypto/ledger_keys.dart';
import '../../core/model/errors.dart';
import '../../storage/ledger_store.dart';
import 'sync_engine.dart';
import 'sync_status.dart';
import 'sync_state_store.dart';
import 'transports/sync_transport.dart';

class SyncChannel {
  const SyncChannel(
    this.kind,
    this.endpointId,
    this.open, {
    String? configEndpointId,
  }) : configEndpointId = configEndpointId ?? endpointId;
  final SyncChannelKind kind;
  final String endpointId;
  final String configEndpointId;
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
  String _identity(SyncChannel channel) =>
      '${channel.kind.name}:${channel.configEndpointId}:${channel.endpointId}';
  Future<SyncReport> _history(List<SyncChannel> active) async {
    final configs = await SyncStateStore(
      store.database,
      store.ledgerId,
    ).configs();
    final values = <SyncChannelKind, List<ChannelReport>>{};
    for (final channel in active) {
      final config = configs
          .where(
            (c) =>
                c.kind == channel.kind &&
                c.endpointId == channel.configEndpointId,
          )
          .firstOrNull;
      if (config != null) {
        final time = config.successes[channel.endpointId];
        if (time != null) _lastSuccess[_identity(channel)] = time;
      }
      (values[channel.kind] ??= []).add(
        ChannelReport(lastSuccess: _lastSuccess[_identity(channel)]),
      );
    }
    ChannelReport report(SyncChannelKind kind) {
      final reports = values[kind];
      final time = reports == null
          ? configs.where((c) => c.kind == kind).firstOrNull?.lastSuccess
          : _combine(reports).lastSuccess;
      return ChannelReport(lastSuccess: time);
    }

    return SyncReport(
      report(SyncChannelKind.webdav),
      report(SyncChannelKind.lan),
    );
  }

  Future<void> restoreStatus() async {
    final active = await loadChannels?.call() ?? channels;
    _emit(SyncStatus(report: await _history(active)));
  }

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
      final active = await loadChannels?.call() ?? channels;
      final history = await _history(active);
      _emit(SyncStatus(running: true, report: history));
      for (final channel in active) {
        final result = await _channel(channel, token);
        results[channel] = result;
      }
      final state = await store.snapshot();
      final archive = await _archive();
      final finalized = <SyncChannelKind, List<ChannelReport>>{};
      for (final entry in results.entries) {
        final channel = entry.key, result = entry.value;
        final cancelled = _closed || token.isCancelled;
        final known = _known[channel.endpointId] ?? {};
        final pending = archive.keys
            .where((key) => !known.contains(key))
            .length;
        final complete =
            !_closed &&
            !token.isCancelled &&
            result.errors.isEmpty &&
            pending == 0 &&
            state.projection.pendingBatchIds.isEmpty &&
            state.projection.conflicts.isEmpty &&
            state.quarantinedBatchIds.isEmpty;
        if (complete) {
          final now = DateTime.now().toUtc();
          await SyncStateStore(store.database, store.ledgerId).recordSuccess(
            channel.kind,
            channel.configEndpointId,
            channel.endpointId,
            now,
          );
          _lastSuccess[_identity(channel)] = now;
        }
        (finalized[channel.kind] ??= []).add(
          ChannelReport(
            enabled: true,
            uploaded: result.uploaded,
            downloaded: result.downloaded,
            pendingUpload: pending,
            pendingDependencies: state.projection.pendingBatchIds.length,
            conflicts: state.projection.conflicts.length,
            quarantined: state.quarantinedBatchIds.length,
            errors: cancelled && !result.cancelled
                ? [...result.errors, '同步已取消']
                : result.errors,
            errorCodes: cancelled && !result.cancelled
                ? [...result.errorCodes, 'cancelled']
                : result.errorCodes,
            lastSuccess: _lastSuccess[_identity(channel)],
          ),
        );
      }
      final report = SyncReport(
        finalized.containsKey(SyncChannelKind.webdav)
            ? _combine(finalized[SyncChannelKind.webdav])
            : history.webdav,
        finalized.containsKey(SyncChannelKind.lan)
            ? _combine(finalized[SyncChannelKind.lan])
            : history.lan,
      );
      _emit(SyncStatus(report: report));
      return report;
    } on Object catch (error, stack) {
      const codes = {
        'validation',
        'locked',
        'incompatible',
        'authentication',
        'integrity',
        'conflict',
        'unavailable',
        'cancelled',
      };
      final failure = error is EchoFailure && codes.contains(error.code)
          ? error
          : const EchoFailure('unavailable', '同步状态读取或保存失败，请重试');
      ChannelReport failed(ChannelReport previous) => ChannelReport(
        enabled: previous.enabled,
        uploaded: previous.uploaded,
        downloaded: previous.downloaded,
        pendingUpload: previous.pendingUpload,
        pendingDependencies: previous.pendingDependencies,
        conflicts: previous.conflicts,
        quarantined: previous.quarantined,
        errors: [...previous.errors, failure.safeMessage],
        errorCodes: [...previous.errorCodes, failure.code],
        lastSuccess: previous.lastSuccess,
      );
      _emit(
        SyncStatus(
          report: SyncReport(
            failed(status.report.webdav),
            failed(status.report.lan),
          ),
          failure: failure.safeMessage,
          failureCode: failure.code,
        ),
      );
      Error.throwWithStackTrace(failure, stack);
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
      lastSuccess: _lastSuccess[_identity(channel)],
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
