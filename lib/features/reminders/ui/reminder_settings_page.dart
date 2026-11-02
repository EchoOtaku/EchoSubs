import 'package:flutter/material.dart';
import '../../../app/design_system.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../app/services.dart';
import '../../../core/model/change_batch.dart';
import '../../../core/model/ledger.dart';
import '../../../core/model/subscription.dart';
import '../../ledger/ui/widgets.dart';
import '../reminder_adapter.dart';
import '../reminder_planner.dart';

class ReminderSettingsPage extends StatefulWidget {
  const ReminderSettingsPage({super.key, required this.services});
  final AppServices services;
  @override
  State<ReminderSettingsPage> createState() => _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends State<ReminderSettingsPage> {
  bool busy = false;
  String? message;
  AppServices get services => widget.services;
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } on Object catch (e) {
      if (mounted) message = safeError(e);
    }
    if (mounted)
      setState(() {
        busy = false;
      });
  }

  Future<void> editZone() async {
    final config = services.config;
    final state = services.snapshot;
    if (config == null || state == null) return;
    final parents = AppServices.heads(state, EntityRef(config.kind, config.id));
    final field = TextEditingController(text: config.timeZoneId);
    final form = GlobalKey<FormState>();
    try {
      final chosen = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('修改账本时区'),
          scrollable: true,
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('保存后会重新核对提醒。旅行或设备时区变化不会自动修改账本。'),
                const SizedBox(height: 16),
                EchoField(
                  label: 'IANA 时区，例如 Asia/Shanghai',
                  child: TextFormField(
                    controller: field,
                    decoration: const InputDecoration(),
                    validator: (v) {
                      try {
                        tz.getLocation(v!.trim());
                        return null;
                      } on Object {
                        return '请输入有效的 IANA 时区';
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate())
                  Navigator.pop(context, field.text.trim());
              },
              child: const Text('保存并核对'),
            ),
          ],
        ),
      );
      if (chosen != null)
        await services.saveLedgerTimeZone(
          chosen,
          expectedLedgerId: config.id,
          baseParents: parents,
        );
    } finally {
      field.dispose();
    }
  }

  Future<void> editRule(Subscription sub) async {
    final state = services.snapshot!;
    final parents = AppServices.heads(state, EntityRef(sub.kind, sub.id));
    final days = TextEditingController(
      text: sub.reminderRule.daysBefore.join(','),
    );
    final time = TextEditingController(
      text:
          '${sub.reminderRule.localHour.toString().padLeft(2, '0')}:${sub.reminderRule.localMinute.toString().padLeft(2, '0')}',
    );
    final form = GlobalKey<FormState>();
    ReminderRule parse() {
      final d = days.text.trim().isEmpty
          ? <int>[]
          : days.text
                .split(RegExp('[,，]'))
                .map((v) => int.parse(v.trim()))
                .toList();
      if (!RegExp(r'^\d{1,2}:\d{2}$').hasMatch(time.text.trim()))
        throw const FormatException();
      final t = time.text.trim().split(':').map(int.parse).toList();
      return ReminderRule(daysBefore: d, localHour: t[0], localMinute: t[1]);
    }

    try {
      final chosen = await showDialog<ReminderRule>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${sub.name}的提醒'),
          scrollable: true,
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                EchoField(
                  label: '提前天数（逗号分隔，留空关闭）',
                  child: TextFormField(
                    controller: days,
                    decoration: const InputDecoration(),
                    validator: (_) {
                      try {
                        parse();
                        return null;
                      } on Object {
                        return '请填写非负天数与有效时间';
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                EchoField(
                  label: '账本时间 HH:mm（${services.config?.timeZoneId}）',
                  child: TextFormField(
                    controller: time,
                    decoration: const InputDecoration(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('更改时间不会重复发送今天已经触发的同条目、同规则提醒。'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate())
                  Navigator.pop(context, parse());
              },
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (chosen != null)
        await services.saveSubscription(
          copySubscription(sub, {'reminderRule': chosen.toJson()}),
          expectedLedgerId: state.metadata.id,
          baseParents: parents,
        );
    } finally {
      days.dispose();
      time.dispose();
    }
  }

  Widget details(String title, Iterable<ReminderEvent> events) => ExpansionTile(
    title: Text(title),
    children: [
      for (final e in events)
        ListTile(
          title: Text(e.name),
          subtitle: Text(
            '${e.ruleId} · ${tz.TZDateTime.from(e.scheduledAtUtc, tz.getLocation(services.config?.timeZoneId ?? 'UTC'))}',
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: services,
    builder: (context, _) {
      final r = services.reminders;
      final status = r?.status ?? const ReminderStatus();
      final permission = switch (status.permission) {
        ReminderPermission.unknown => '尚未确认',
        ReminderPermission.granted => '已开启',
        ReminderPermission.denied => '已关闭',
        ReminderPermission.restricted => '系统限制',
      };
      return Scaffold(
        appBar: AppBar(title: const Text('本地提醒')),
        body: PageContent(
          children: [
            const SectionTitle('提醒与权限', subtitle: '同步数据成功与提醒安排成功分别核对'),
            Text(
              services.inAppReminders != null
                  ? 'Windows：仅应用运行时显示横幅，无后台服务或开机启动。'
                  : 'Android：在约定时刻附近提醒，不申请精确闹钟权限。',
            ),
            Text(
              '通知权限：$permission',
              key: const ValueKey('reminders.permission'),
            ),
            Text(
              r?.complete == true ? '本地提醒已核对' : '提醒未全部就绪',
              key: const ValueKey('reminders.state'),
            ),
            if (r?.suppressed.isNotEmpty == true)
              Text('${r!.suppressed.length} 个订阅或账本配置存在争议，相关日期提醒已暂停，待确认后重排。'),
            if (r?.error != null) Text(r!.error!),
            if (status.error != null) Text(status.error!),
            if (message != null) Text(message!),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: busy || r == null
                      ? null
                      : () => run(r.requestPermission),
                  child: const Text('申请通知权限'),
                ),
                OutlinedButton(
                  onPressed: busy || r == null
                      ? null
                      : () => run(() async {
                          await r.adapter.testNotification();
                          if (mounted) message = '已请求发送测试提醒，请检查本机显示';
                        }),
                  child: const Text('测试提醒'),
                ),
                TextButton(
                  onPressed: busy || r == null
                      ? null
                      : () => run(services.reconcileReminders),
                  child: const Text('重新核对'),
                ),
              ],
            ),
            const Text(
              '关闭权限后请在系统设置中开启，再返回应用核对。强行停止、省电限制、设备重启或长期不打开应用可能延迟或阻止提醒；不保证必达。手机尚未同步的电脑修改不会改变本机提醒。',
            ),
            const SizedBox(height: 20),
            ListTile(
              title: Text('账本时区：${services.config?.timeZoneId ?? '未知'}'),
              trailing: TextButton(
                onPressed: busy ? null : () => run(editZone),
                child: const Text('修改'),
              ),
            ),
            if (status.unscheduled.isNotEmpty)
              details(
                '未安排成功（${status.unscheduled.length} 条）',
                status.unscheduled,
              ),
            for (final batch in status.scheduled)
              details('已预约摘要（${batch.events.length} 条）', batch.events),
            const SectionTitle('逐条提醒规则', subtitle: '默认提前 7、3、1 天，账本时间 09:00'),
            for (final sub in services.subscriptions)
              ListTile(
                title: Text(sub.name),
                subtitle: Text(
                  sub.reminderRule.daysBefore.isEmpty
                      ? '已关闭'
                      : '提前 ${sub.reminderRule.daysBefore.join('、')} 天 · ${sub.reminderRule.localHour.toString().padLeft(2, '0')}:${sub.reminderRule.localMinute.toString().padLeft(2, '0')}',
                ),
                trailing: IconButton(
                  tooltip: '编辑提醒',
                  onPressed: busy ? null : () => run(() => editRule(sub)),
                  icon: const Icon(Icons.edit_notifications_outlined),
                ),
              ),
          ],
        ),
      );
    },
  );
}
