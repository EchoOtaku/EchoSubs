import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../app/design_system.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../app/services.dart';
import '../../../core/model/errors.dart';
import '../sync_coordinator.dart';
import '../transports/lan_identity.dart';
import '../transports/lan_pairing.dart';

class PairingPage extends StatefulWidget {
  const PairingPage({
    super.key,
    required this.services,
    this.addresses = localLanAddresses,
  });
  final AppServices services;
  final Future<List<String>> Function() addresses;
  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  late final String ledgerId;
  final address = TextEditingController(),
      port = TextEditingController(text: '43177'),
      input = TextEditingController();
  final cancellation = SyncCancellation();
  PairingOffer? offer;
  Timer? expiry;
  List<PairedPeer> peers = [];
  List<String> available = [];
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    ledgerId = widget.services.ledger.currentLedgerId!;
    widget.services.syncRuntime.confirm = confirm;
    load();
    widget.addresses().then(
      (values) {
        if (!mounted) return;
        setState(() {
          available = values;
          if (values.length == 1) address.text = values.single;
        });
      },
      onError: (Object _) {
        if (mounted) setState(() => error = '未发现可用局域网地址，请在高级设置手动填写');
      },
    );
  }

  Future<void> load() async {
    try {
      final values = await widget.services.syncRuntime.peers.list(
        widget.services.ledger.currentLedgerId!,
      );
      if (mounted) setState(() => peers = values);
    } on Object catch (e) {
      if (mounted) setState(() => error = safeError(e));
    }
  }

  Future<bool> confirm(LanCertificate peer) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('核对另一台设备身份'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('请在另一台设备核对同一设备 ID 与证书指纹。证书变化必须重新确认，自动发现不构成授权。'),
                  SelectableText('设备 ID：${peer.deviceId}'),
                  SelectableText('SHA-256：${peer.fingerprint}'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('拒绝'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('已在另一端核对并同意'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> action(Future<void> Function() work) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (ledgerId != widget.services.ledger.currentLedgerId) {
        throw const EchoFailure('conflict', '账本已切换，请重新打开配对页面');
      }
      await work();
      if (ledgerId != widget.services.ledger.currentLedgerId) return;
      await load();
    } on Object catch (e) {
      if (mounted) setState(() => error = safeError(e));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> createOffer() async {
    final value = await widget.services.syncRuntime.offer();
    expiry?.cancel();
    expiry = Timer(const Duration(seconds: 120), () {
      widget.services.syncRuntime.pairing?.cancelOffer(value);
      if (mounted) setState(() => offer = null);
    });
    if (mounted) setState(() => offer = value);
  }

  Future<void> renewIdentity() async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('更新本机局域网身份？'),
        content: const Text(
          '旧配对将全部失效，新证书指纹需要在每台设备上重新扫码并双方确认。账本、恢复密钥和历史保持不变。身份过期或损坏时可使用此操作恢复局域网连接。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认更新并重新配对'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;
    expiry?.cancel();
    setState(() => offer = null);
    await action(
      () => widget.services.syncRuntime.renewLanIdentity(
        confirmed: true,
        expectedLedgerId: ledgerId,
      ),
    );
  }

  Future<void> join(String value) async {
    final parsed = PairingOffer.decode(value);
    input.clear();
    await widget.services.syncRuntime.joinPairing(parsed, cancellation);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    cancellation.cancel();
    expiry?.cancel();
    if (offer != null) widget.services.syncRuntime.pairing?.cancelOffer(offer!);
    widget.services.syncRuntime.confirm = null;
    address.dispose();
    port.dispose();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('局域网配对')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              '仅同一可达局域网。启用后仅在前台监听指定端口；请填写此设备的局域网 IP，双方都需确认设备 ID 和证书指纹。',
            ),
            OutlinedButton(
              onPressed: busy ? null : renewIdentity,
              child: const Text('更新本机局域网身份'),
            ),
            if (available.isNotEmpty)
              EchoField(
                label: '选择与另一台设备相同网络的地址',
                child: DropdownButtonFormField<String>(
                  initialValue: available.length == 1 ? available.single : null,
                  isExpanded: true,
                  decoration: const InputDecoration(),
                  borderRadius: BorderRadius.circular(8),
                  items: [
                    for (final value in available)
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: (value) {
                    if (value != null) address.text = value;
                  },
                ),
              ),
            ExpansionTile(
              title: const Text('高级设置 / 手动地址'),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: EchoField(
                    label: '此设备局域网 IP',
                    child: TextField(
                      controller: address,
                      decoration: const InputDecoration(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: EchoField(
                    label: '固定监听端口',
                    child: TextField(
                      controller: port,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(),
                    ),
                  ),
                ),
              ],
            ),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => action(
                      () => widget.services.syncRuntime.configureLan(
                        address.text.trim(),
                        int.parse(port.text),
                        enabled: true,
                        expectedLedgerId: ledgerId,
                      ),
                    ),
              child: const Text('启用局域网通道'),
            ),
            if (widget.services.syncRuntime.pairing != null) ...[
              SelectableText(
                '本机设备 ID：${widget.services.syncRuntime.pairing!.identity.deviceId}',
              ),
              SelectableText(
                '本机 SHA-256：${widget.services.syncRuntime.pairing!.identity.certificate.fingerprint}',
              ),
            ],
            OutlinedButton(
              onPressed: busy ? null : () => action(createOffer),
              child: const Text('为此账本生成一次性二维码'),
            ),
            if (offer != null) ...[
              const Text('120 秒内有效，仅使用一次。不要公开分享二维码或配对文本。'),
              Center(child: QrImageView(data: offer!.encode(), size: 240)),
              TextButton(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: offer!.encode())),
                child: const Text('复制一次性配对文本'),
              ),
            ],
            const Divider(),
            const Text(
              '加入会保留原账本，验证完整历史后切换。仅通过配对加入的设备没有原恢复密钥；需要保管原设备的恢复密钥才能离线恢复。',
            ),
            EchoField(
              label: '粘贴另一端的一次性配对文本',
              child: TextField(
                controller: input,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(),
              ),
            ),
            if (Platform.isAndroid)
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final text = await Navigator.push<String>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const _ScannerPage(),
                          ),
                        );
                        if (text != null && mounted)
                          await action(() => join(text));
                      },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('扫码（此时才请求相机权限）'),
              ),
            for (final peer in peers)
              ListTile(
                title: Text(peer.certificate.deviceId),
                subtitle: Text(peer.certificate.fingerprint),
                trailing: IconButton(
                  tooltip: '停用此配对',
                  icon: const Icon(Icons.link_off),
                  onPressed: () => action(() async {
                    await widget.services.syncRuntime.peers.revoke(
                      peer.ledgerId,
                      peer.certificate.deviceId,
                    );
                    await widget.services.syncRuntime.rebind();
                  }),
                ),
              ),
            const Text('停用配对只阻止后续直连，不会擦除其他设备已有数据或密钥。'),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    ),
    bottomNavigationBar: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            children: [
              FilledButton(
                onPressed: busy
                    ? null
                    : () => action(() => join(input.text.trim())),
                child: Text(busy ? '等待双方确认…' : '验证并加入账本'),
              ),
              TextButton(
                onPressed: () {
                  cancellation.cancel();
                  Navigator.pop(context);
                },
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<List<String>> localLanAddresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  );
  final result = <String>{};
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      final parts = address.rawAddress;
      if (parts[0] == 10 ||
          (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) ||
          (parts[0] == 192 && parts[1] == 168))
        result.add(address.address);
    }
  }
  return result.toList()..sort();
}

class _ScannerPage extends StatefulWidget {
  const _ScannerPage();
  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  final controller = MobileScannerController(autoStart: false);
  bool received = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.start();
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('扫描一次性配对码')),
    body: MobileScanner(
      controller: controller,
      onDetect: (capture) {
        final value = capture.barcodes.firstOrNull?.rawValue;
        if (received || value == null) return;
        received = true;
        Navigator.pop(context, value);
      },
    ),
  );
}
