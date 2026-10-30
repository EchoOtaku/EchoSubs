import 'package:flutter/material.dart';
import '../../../app/services.dart';
import '../../../core/model/civil_date.dart';
import '../../../core/model/ids.dart';
import '../../../core/model/money.dart';
import '../../../core/model/payment.dart';
import '../../../core/model/subscription.dart';
import 'subscription_editor.dart';
import 'payments_page.dart';
import 'widgets.dart';

class SubscriptionDetailPage extends StatefulWidget {
  const SubscriptionDetailPage({
    super.key,
    required this.services,
    required this.subscriptionId,
  });
  final AppServices services;
  final String subscriptionId;
  @override
  State<SubscriptionDetailPage> createState() => _SubscriptionDetailPageState();
}

class _SubscriptionDetailPageState extends State<SubscriptionDetailPage> {
  String? error;
  bool busy = false;
  Future<void> perform(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on Object catch (e) {
      if (mounted)
        setState(() {
          error = safeError(e);
        });
    }
    if (mounted)
      setState(() {
        busy = false;
      });
  }

  Future<void> remove(Subscription s) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除订阅？'),
        content: Text('将删除「${s.name}」。已有付款记录会保留，可在付款记录中查看。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('delete.confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await perform(() async {
      await widget.services.deleteSubscription(s);
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.services,
    builder: (context, _) {
      final s = widget.services.subscriptions
          .where((s) => s.id == widget.subscriptionId)
          .firstOrNull;
      if (s == null)
        return Scaffold(
          appBar: AppBar(title: const Text('订阅详情')),
          body: const Center(child: Text('该订阅已删除或存在未解决的冲突。')),
        );
      final category =
          widget.services.categories
              .where((c) => c.id == s.categoryId)
              .firstOrNull
              ?.name ??
          '未分类';
      final payments =
          widget.services.payments
              .where((p) => p.subscriptionId == s.id)
              .toList()
            ..sort((a, b) => b.paidOn.compareTo(a.paidOn));
      return Scaffold(
        appBar: AppBar(
          title: const Text('订阅详情'),
          actions: [
            IconButton(
              key: const ValueKey('detail.edit'),
              tooltip: '编辑订阅',
              onPressed: busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => SubscriptionEditor(
                          services: widget.services,
                          value: s,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        body: PageContent(
          children: [
            SectionTitle(
              s.name,
              subtitle: [
                s.provider,
                category,
                statusText(s.status),
              ].whereType<String>().where((v) => v.isNotEmpty).join(' · '),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      moneyText(s.price),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(cycleText(s)),
                    const SizedBox(height: 20),
                    _line('开始日期', dateText(s.startDate)),
                    _line('权益到期', dateText(s.entitlementEnd)),
                    _line(
                      '预计续费',
                      s.billingType == BillingType.lifetime
                          ? '买断，无周期续费'
                          : dateText(s.nextRenewalDate),
                    ),
                    _line('自动续费', s.autoRenew ? '已开启' : '未开启'),
                    if (s.cycleAnchor != null)
                      _line('周期锚点', dateText(s.cycleAnchor)),
                    if (s.purchaseChannel?.isNotEmpty == true)
                      _line('购买渠道', s.purchaseChannel!),
                    if (s.paymentMethod?.isNotEmpty == true)
                      _line('付款方式', s.paymentMethod!),
                    if (s.websiteUrl?.isNotEmpty == true)
                      _line('服务网址', s.websiteUrl!),
                    if (s.notes?.isNotEmpty == true) _line('备注', s.notes!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('detail.renew'),
              onPressed: busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            RenewalEditor(services: widget.services, value: s),
                      ),
                    ),
              icon: const Icon(Icons.add_card),
              label: const Text('记录付款 / 续费'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('detail.archive'),
                  onPressed: busy
                      ? null
                      : () => perform(
                          () => widget.services.saveSubscription(
                            copySubscription(s, {
                              'status': s.status == SubscriptionStatus.archived
                                  ? SubscriptionStatus.active.name
                                  : SubscriptionStatus.archived.name,
                            }),
                          ),
                        ),
                  icon: const Icon(Icons.archive_outlined),
                  label: Text(
                    s.status == SubscriptionStatus.archived ? '恢复使用' : '归档订阅',
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('detail.delete'),
                  onPressed: busy ? null : () => remove(s),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除订阅'),
                ),
              ],
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 28),
            const SectionTitle('实际付款', subtitle: '赠送权益不等于实际付款，不会自动增加支出。'),
            if (payments.isEmpty) const Text('暂无付款记录'),
            for (final p in payments)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PaymentCard(payment: p, name: s.name),
              ),
          ],
        ),
      );
    },
  );
  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text('$label：$value'),
  );
}

class RenewalEditor extends StatefulWidget {
  const RenewalEditor({super.key, required this.services, required this.value});
  final AppServices services;
  final Subscription value;
  @override
  State<RenewalEditor> createState() => _RenewalEditorState();
}

class _RenewalEditorState extends State<RenewalEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final s = widget.value;
    final values = {
      'amount': s.price == null ? '' : decimalText(s.price!),
      'currency': s.price?.currency ?? 'CNY',
      'scale': '${s.price?.scale ?? 2}',
      'paidOn': widget.services.today.toJson(),
      'periodStart': '',
      'periodEnd': '',
      'end': s.entitlementEnd?.toJson() ?? '',
      'renewal': s.nextRenewalDate?.toJson() ?? '',
      'notes': '',
    };
    for (final e in values.entries) {
      fields[e.key] = TextEditingController(text: e.value);
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String text(String k) => fields[k]!.text.trim();
  CivilDate? date(String k) =>
      text(k).isEmpty ? null : CivilDate.fromJson(text(k));
  Widget input(
    String key,
    String label, {
    bool isDate = false,
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey('payment.$key'),
      controller: fields[key],
      decoration: InputDecoration(
        labelText: label,
        hintText: isDate ? 'YYYY-MM-DD' : null,
      ),
      validator: (v) {
        if (required && (v == null || v.trim().isEmpty)) return '请填写此项';
        if (isDate && v != null && v.trim().isNotEmpty) {
          try {
            CivilDate.fromJson(v.trim());
          } on Object {
            return '请输入有效日期';
          }
        }
        return null;
      },
    ),
  );
  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final amount = Money.fromDecimal(
        text('amount'),
        text('currency').toUpperCase(),
        int.parse(text('scale')),
      );
      final payment = Payment(
        id: newId(),
        subscriptionId: widget.value.id,
        amount: amount,
        paidOn: date('paidOn')!,
        periodStart: date('periodStart'),
        periodEnd: date('periodEnd'),
        notes: text('notes'),
      );
      final updated = copySubscription(widget.value, {
        'entitlementEnd': date('end')?.toJson(),
        'nextRenewalDate': widget.value.billingType == BillingType.lifetime
            ? null
            : date('renewal')?.toJson(),
      });
      await widget.services.renew(updated, payment);
      if (mounted) Navigator.pop(context);
    } on Object catch (e) {
      if (mounted)
        setState(() {
          error = safeError(e);
          saving = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('记录付款 / 续费')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              SectionTitle(
                widget.value.name,
                subtitle: '仅记录已发生的付款。付款日期、付费周期与赠送权益可以不同。',
              ),
              input('amount', '实际付款金额 *', required: true),
              input('currency', '币种 *', required: true),
              input('scale', '金额小数位数 *', required: true),
              input('paidOn', '实际付款日期 *', isDate: true, required: true),
              input('periodStart', '本次付费周期开始', isDate: true),
              input('periodEnd', '本次付费周期结束', isDate: true),
              const SectionTitle('更新权益', subtitle: '没有变化时保留原日期；不按付款金额推断到期日。'),
              input('end', '更新后的权益到期', isDate: true),
              if (widget.value.billingType != BillingType.lifetime)
                input('renewal', '更新后的预计续费', isDate: true),
              input('notes', '付款备注'),
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
    ),
    bottomNavigationBar: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            key: const ValueKey('payment.save'),
            onPressed: saving ? null : save,
            icon: const Icon(Icons.check),
            label: Text(saving ? '保存中…' : '保存付款与权益'),
          ),
        ),
      ),
    ),
  );
}
