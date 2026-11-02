import 'dart:async';
import 'package:bonsoir/bonsoir.dart';
import '../../../core/model/errors.dart';
import 'lan_pairing.dart';
import 'lan_transport.dart';

/// mDNS is an untrusted address hint, never a trust or credential source.
class LanDiscovery {
  static const serviceType = '_echosubs._tcp';
  BonsoirDiscovery? _discovery;
  BonsoirBroadcast? _broadcast;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  final _events = StreamController<BonsoirService>.broadcast();
  bool _closed = false;
  void _requireOpen() {
    if (_closed) throw const EchoFailure('cancelled', '局域网发现已关闭');
  }

  Stream<BonsoirService> get candidates => _events.stream;
  Future<void> start({
    required bool enabled,
    required bool foreground,
    required String deviceId,
    required int port,
  }) async {
    if (!enabled || !foreground) {
      await stop();
      return;
    }
    _requireOpen();
    if (_discovery != null) return;
    final discovery = BonsoirDiscovery(type: serviceType, printLogs: false);
    final broadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: 'EchoSubs-$deviceId',
        type: serviceType,
        port: port,
        attributes: {'device': deviceId, 'version': '1'},
      ),
      printLogs: false,
    );
    _discovery = discovery;
    _broadcast = broadcast;
    try {
      await discovery.initialize();
      _requireOpen();
      _subscription = discovery.eventStream?.listen(
        (event) {
          if (_closed) return;
          if (event is BonsoirDiscoveryServiceFoundEvent) {
            discovery.serviceResolver.resolveService(event.service);
          }
          if (event is BonsoirDiscoveryServiceResolvedEvent) {
            _events.add(event.service);
          }
        },
        onError: (Object _) {
          if (_closed) return;
          _events.addError(
            const EchoFailure('unavailable', '局域网发现不可用，请使用扫码地址'),
          );
        },
      );
      await discovery.start();
      _requireOpen();
      await broadcast.initialize();
      _requireOpen();
      await broadcast.start();
      _requireOpen();
    } on Object {
      await stop();
      // stop may have run while initialize was pending. Clean those late-ready
      // local handles too; a closed instance must never publish in background.
      await _stopHandles(discovery, broadcast);
      throw const EchoFailure('unavailable', '局域网发现不可用，请使用扫码地址');
    }
  }

  /// Call before accepting a discovery result. Successful authentication does not
  /// mutate the saved pin; forged advertisements cannot replace the certificate.
  static Future<LanTransport> connect(
    BonsoirService hint,
    PairedPeer peer,
    LanPeerStore peers,
  ) async {
    if (hint.type != serviceType ||
        hint.attributes['device'] != peer.certificate.deviceId ||
        hint.attributes['version'] != '1' ||
        hint.hostAddress == null) {
      throw const EchoFailure('authentication', '局域网发现身份不匹配');
    }
    final transport = LanTransport(
      peer: peer,
      localDeviceId: peer.localDeviceId,
      peers: peers,
      address: hint.hostAddress,
      port: hint.port,
    );
    try {
      await transport.readMetadata();
      return transport;
    } on Object {
      await transport.close();
      rethrow;
    }
  }

  Future<void> stop() async {
    _closed = true;
    final discovery = _discovery, broadcast = _broadcast;
    _discovery = null;
    _broadcast = null;
    await _subscription?.cancel();
    _subscription = null;
    await _stopHandles(discovery, broadcast);
  }

  Future<void> _stopHandles(
    BonsoirDiscovery? discovery,
    BonsoirBroadcast? broadcast,
  ) async {
    try {
      if (discovery?.isReady == true && discovery?.isStopped != true)
        await discovery?.stop();
    } finally {
      if (broadcast?.isReady == true && broadcast?.isStopped != true)
        await broadcast?.stop();
    }
  }

  Future<void> close() async {
    await stop();
    await _events.close();
  }
}
