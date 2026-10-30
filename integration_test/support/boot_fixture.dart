import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:xml/xml.dart';
import 'package:echo_subs/features/reminders/reminder_adapter.dart';
import 'package:echo_subs/features/reminders/reminder_planner.dart';
import 'package:echo_subs/storage/app_database.dart';

/// Normal debug-only isolated entrypoint. No integration_test binding/teardown,
/// production bootstrap, vault, implicit reboot, or automatic re-registration
/// on reopen: inspect the OS first, then explicitly reconcile/cancel below.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isAndroid) throw StateError('Android fixture only');
  final support = await getApplicationSupportDirectory();
  if (!support.path.contains('/dev.echootaku.echo_subs.integration/')) {
    throw StateError('Refusing non-isolated application');
  }
  tzdata.initializeTimeZones();
  final directory = Directory('${support.path}/task11-boot-v1');
  await directory.create(recursive: true);
  runApp(
    MaterialApp(
      home: BootFixture(directory: directory, support: support),
    ),
  );
}

class BootFixture extends StatefulWidget {
  const BootFixture({
    super.key,
    required this.directory,
    required this.support,
  });
  final Directory directory, support;
  @override
  State<BootFixture> createState() => _BootFixtureState();
}

class _BootFixtureState extends State<BootFixture> {
  AppDatabase? db;
  AndroidReminderPlatform? platform;
  DurableReminderAdapter? adapter;
  List<ReminderEvent> events = [];
  List<int> ids = [];
  String message = '正在检查独立测试资源';
  bool busy = true, complete = false;
  File get marker => File('${widget.directory.path}/checkpoint.json');
  Future<List<int>> diskIds() async {
    final file = File(
      '${widget.support.parent.path}/shared_prefs/scheduled_notifications.xml',
    );
    if (!await file.exists()) return [];
    final xml = XmlDocument.parse(await file.readAsString());
    final entry = xml
        .findAllElements('string')
        .where((e) => e.getAttribute('name') == 'scheduled_notifications')
        .firstOrNull;
    return entry == null
          ? []
          : (jsonDecode(entry.innerText) as List)
                .map((e) => (e as Map)['id'] as int)
                .toList()
      ..sort();
  }

  Future<void> checkpoint(String phase) async => marker.writeAsString(
    jsonEncode({
      'phase': phase,
      'ids': ids,
      'events': events.map((e) => e.toJson()).toList(),
      'diskIds': await diskIds(),
    }),
    flush: true,
  );
  @override
  void initState() {
    super.initState();
    prepare();
  }

  Future<void> prepare() async {
    try {
      db = await AppDatabase.open(
        File('${widget.directory.path}/mapping.sqlite'),
      );
      platform = AndroidReminderPlatform();
      adapter = DurableReminderAdapter(ReminderStateStore(db!), platform!);
      if (await marker.exists()) {
        final saved =
            jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
        ids = (saved['ids'] as List).cast<int>();
        events = (saved['events'] as List)
            .map(
              (e) =>
                  ReminderEvent.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
        complete = saved['phase'] == 'complete';
        message = complete ? '本次预约已取消' : '已重开，尚未重新安排。请先检查系统预约，再核对原 ID。';
      } else {
        if (await platform!.permission() != ReminderPermission.granted)
          throw StateError(
            'Permission unavailable; no request or grant performed',
          );
        if ((await platform!.pending()).isNotEmpty ||
            (await diskIds()).isNotEmpty)
          throw StateError('Existing test alarms must be accounted for first');
        final anchor = DateTime.now().toUtc().add(const Duration(days: 7));
        events = [
          for (var i = 1; i <= 3; i++)
            ReminderEvent(
              ledgerId: '00000000000000000000000000001100',
              subscriptionId: '00000000000000000000000000001101',
              stableKey: 'task11-boot/$i',
              scheduledAtUtc: anchor.add(Duration(hours: i)),
              ruleId: 'fictional:$i',
              name: '虚构重启验收预约',
            ),
        ];
        await adapter!.replace(events);
        if (!adapter!.status.complete)
          throw StateError('Registration not confirmed');
        ids = (await ReminderStateStore(db!).all()).map((r) => r.id).toList()
          ..sort();
        if (jsonEncode(await diskIds()) != jsonEncode(ids))
          throw StateError('Durable readback mismatch');
        await checkpoint('seeded');
        message = '已准备 3 条约七天后的虚构预约；尚未重启设备。';
      }
    } catch (e) {
      message = '准备失败；请检查本任务日志。';
      // Cancel only mappings in this new fixture's database.
      await adapter?.replace([]);
      debugPrint('BOOT_FIXTURE_PREPARE_FAILED ${e.runtimeType}');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> action(bool cancel) async {
    setState(() => busy = true);
    try {
      await adapter!.replace(cancel ? [] : events);
      if (!adapter!.status.complete)
        throw StateError('Reconciliation incomplete');
      final after = await diskIds();
      if (cancel ? after.isNotEmpty : jsonEncode(after) != jsonEncode(ids))
        throw StateError('Durable readback mismatch');
      await checkpoint(cancel ? 'complete' : 'reconciled');
      complete = cancel;
      message = cancel ? '本次预约已取消，持久缓存为空' : '原 ID 已核对，请随后取消本次预约';
    } catch (_) {
      message = '操作未完成，旧预约可能仍有效，请重试';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('EchoSubs 隔离重启验收')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message),
          const SizedBox(height: 16),
          Text('测试 ID：${ids.join(', ')}'),
          for (final e in events) Text(e.scheduledAtUtc.toIso8601String()),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: busy || complete || events.isEmpty
                ? null
                : () => action(false),
            child: const Text('核对原 ID'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy || complete || events.isEmpty
                ? null
                : () => action(true),
            child: const Text('取消本次预约'),
          ),
        ],
      ),
    ),
  );
}
