import 'package:flutter/material.dart';
import '../../../app/services.dart';
import '../../../core/model/change_batch.dart';
import '../../../core/model/ledger.dart';
import '../../../core/model/subscription.dart';
import '../../../core/model/payment.dart';
import '../../ledger/ui/widgets.dart';
import '../../../storage/ledger_store.dart';

class ConflictsPage extends StatelessWidget {
  const ConflictsPage({super.key, required this.services});
  final AppServices services;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: services,
    builder: (context, _) {
      final snapshot = services.snapshot;
      return Scaffold(
        appBar: AppBar(title: const Text('同步冲突')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('竞争版本不会按设备时间自动覆盖。关联付款与权益均为待确认，未计入已确认付款。'),
            if (snapshot == null)
              const Text('账本暂不可用')
            else ...[
              if (snapshot.projection.conflicts.isEmpty)
                const Text('没有待解决的业务冲突'),
              for (final conflict in snapshot.projection.conflicts)
                Card(
                  child: ListTile(
                    title: Text('待确认：${conflict.affectedRefs.length} 个关联实体'),
                    subtitle: Text('竞争批次：${conflict.competingBatchIds.length}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => _ConflictEditor(
                          services: services,
                          snapshot: snapshot,
                          conflict: conflict,
                        ),
                      ),
                    ),
                  ),
                ),
              if (snapshot.quarantinedObjects.isNotEmpty) ...[
                const Text('隔离警告：认证对象存在标识碰撞或无效因果关系。原始证据保留，不自动选择胜者。'),
                for (final candidate in snapshot.quarantinedObjects)
                  ListTile(
                    title: Text(candidate.batch.id),
                    subtitle: Text(
                      '摘要：${candidate.object.sha256}\n原因：${candidate.reason.name}',
                    ),
                  ),
              ],
            ],
          ],
        ),
      );
    },
  );
}

class _ConflictEditor extends StatefulWidget {
  const _ConflictEditor({
    required this.services,
    required this.snapshot,
    required this.conflict,
  });
  final AppServices services;
  final LedgerSnapshot snapshot;
  final Conflict conflict;
  @override
  State<_ConflictEditor> createState() => _ConflictEditorState();
}

class _ConflictEditorState extends State<_ConflictEditor> {
  final choices = <EntityRef, LedgerEntity?>{};
  String? error;
  bool busy = false;
  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.services
          .resolveConflict(widget.snapshot.metadata.id, widget.conflict, [
            for (final ref in widget.conflict.affectedRefs)
              Mutation(
                ref,
                (widget.snapshot.causal.heads[ref] ?? {}).toList(),
                choices[ref],
              ),
          ]);
      if (mounted) Navigator.pop(context);
    } on Object catch (e) {
      if (mounted)
        setState(() {
          busy = false;
          error = safeError(e);
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('对比与明确解决')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('逐一明确保留一个版本或删除。所有关联订阅和付款必须一并选择；保存将生成引用全部竞争版本的解决记录。'),
        for (final ref in widget.conflict.affectedRefs) _entity(ref),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 80),
      ],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed:
              busy || choices.length != widget.conflict.affectedRefs.length
              ? null
              : save,
          child: Text(busy ? '保存中…' : '确认全部选择并解决'),
        ),
      ),
    ),
  );
  Widget _entity(EntityRef ref) {
    final heads = widget.snapshot.causal.heads[ref] ?? {};
    final variants = <LedgerEntity?>[
      for (final batch in widget.snapshot.batches.where(
        (b) => heads.contains(b.id),
      ))
        for (final mutation in batch.mutations.where((m) => m.ref == ref))
          mutation.value,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_entityKind(ref.kind)} · ${ref.id}'),
            for (var i = 0; i < variants.length; i++) ...[
              Text(
                '版本 ${i + 1}：${variants[i] == null ? '删除标记' : describeConflictEntity(variants[i]!)}',
              ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => setState(() => choices[ref] = variants[i]),
                child: Text('保留版本 ${i + 1}'),
              ),
            ],
            TextButton(
              key: ValueKey('conflict.delete.${ref.id}'),
              onPressed: busy
                  ? null
                  : () => setState(() => choices[ref] = null),
              child: const Text('明确删除此实体'),
            ),
            Text(
              !choices.containsKey(ref)
                  ? '尚未选择'
                  : choices[ref] == null
                  ? '已选择：删除'
                  : '已选择：保留版本 ${variants.indexOf(choices[ref]) + 1}',
            ),
          ],
        ),
      ),
    );
  }
}

String _entityKind(EntityKind kind) => switch (kind) {
  EntityKind.subscription => '订阅',
  EntityKind.payment => '付款',
  EntityKind.category => '分类',
  EntityKind.ledgerConfig => '账本设置',
};
String describeConflictEntity(LedgerEntity entity) {
  const labels = {
    'name': '名称',
    'provider': '服务提供商',
    'purchaseChannel': '购买渠道',
    'paymentMethod': '付款方式',
    'websiteUrl': '网址',
    'notes': '备注',
    'status': '状态',
    'billingType': '计费类型',
    'price': '价格',
    'cycle': '周期',
    'cycleAnchor': '周期锚点',
    'startDate': '开始日期',
    'entitlementEnd': '权益到期',
    'nextRenewalDate': '预计续费',
    'autoRenew': '自动续费',
    'reminderRule': '提醒规则',
    'categoryId': '分类 ID',
    'subscriptionId': '关联订阅',
    'amount': '实际付款',
    'paidOn': '付款日期',
    'periodStart': '付费周期开始',
    'periodEnd': '付费周期结束',
    'timeZoneId': '账本时区',
  };
  String value(String key, Object? raw) {
    if (entity is Subscription) {
      final s = entity;
      switch (key) {
        case 'price':
          return moneyText(s.price);
        case 'cycle':
          return cycleText(s);
        case 'status':
          return statusText(s.status);
        case 'billingType':
          return billingText(s.billingType);
        case 'autoRenew':
          return s.autoRenew ? '是（仅预期）' : '否';
        case 'reminderRule':
          final r = s.reminderRule;
          return r.daysBefore.isEmpty
              ? '已关闭'
              : '提前 ${r.daysBefore.join('、')} 天，账本时间 ${r.localHour.toString().padLeft(2, '0')}:${r.localMinute.toString().padLeft(2, '0')}';
        case 'cycleAnchor':
          return dateText(s.cycleAnchor);
        case 'startDate':
          return dateText(s.startDate);
        case 'entitlementEnd':
          return dateText(s.entitlementEnd);
        case 'nextRenewalDate':
          return dateText(s.nextRenewalDate);
      }
    }
    if (entity is Payment) {
      final p = entity;
      switch (key) {
        case 'amount':
          return moneyText(p.amount);
        case 'paidOn':
          return dateText(p.paidOn);
        case 'periodStart':
          return dateText(p.periodStart);
        case 'periodEnd':
          return dateText(p.periodEnd);
      }
    }
    return raw.toString();
  }

  return entity
      .toJson()
      .entries
      .where((e) => e.key != 'id' && e.value != null)
      .map((e) => '${labels[e.key] ?? e.key}：${value(e.key, e.value)}')
      .join('\n');
}
