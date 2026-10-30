import 'package:flutter/material.dart';
import '../../../app/services.dart';
import '../../../core/model/civil_date.dart';
import '../../../core/model/change_batch.dart';
import '../../../core/model/errors.dart';
import '../../../core/model/ids.dart';
import '../../../core/model/ledger.dart';
import '../../../core/model/money.dart';
import '../../../core/model/subscription.dart';
import '../cycle_calculator.dart';
import 'widgets.dart';

class SubscriptionEditor extends StatefulWidget {
  const SubscriptionEditor({super.key, required this.services, this.value});
  final AppServices services;
  final Subscription? value;
  @override
  State<SubscriptionEditor> createState() => _SubscriptionEditorState();
}

class _SubscriptionEditorState extends State<SubscriptionEditor> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  late BillingType _type;
  late SubscriptionStatus _status;
  late CycleUnit _unit;
  late bool _autoRenew;
  bool _saving = false;
  String? _error;
  late final LedgerId _ledgerId;
  late final List<BatchId> _baseParents;
  late final bool _baseMatches;
  TextEditingController field(String key) => _fields[key]!;
  @override
  void initState() {
    super.initState();
    final s = widget.value;
    _ledgerId = widget.services.ledger.currentLedgerId!;
    final editable =
        s == null || widget.services.canEdit(EntityRef(s.kind, s.id));
    _baseMatches =
        editable &&
        (s == null ||
            widget.services.snapshot!.projection.entities[EntityRef(
                  s.kind,
                  s.id,
                )] ==
                s);
    if (!editable) _error = '此记录待确认，请返回详情处理冲突';
    _baseParents = s == null || !editable
        ? []
        : widget.services.snapshot!.causal.parentsFor(EntityRef(s.kind, s.id));
    final initial = <String, String>{
      'name': s?.name ?? '',
      'provider': s?.provider ?? '',
      'price': s?.price == null ? '' : decimalText(s!.price!),
      'currency': s?.price?.currency ?? 'CNY',
      'scale': '${s?.price?.scale ?? 2}',
      'count': '${s?.cycle?.count ?? 1}',
      'start': s?.startDate?.toJson() ?? '',
      'anchor': s?.cycleAnchor?.toJson() ?? '',
      'end': s?.entitlementEnd?.toJson() ?? '',
      'renewal': s?.nextRenewalDate?.toJson() ?? '',
      'category':
          widget.services.categories
              .where((c) => c.id == s?.categoryId)
              .firstOrNull
              ?.name ??
          '',
      'channel': s?.purchaseChannel ?? '',
      'method': s?.paymentMethod ?? '',
      'website': s?.websiteUrl ?? '',
      'notes': s?.notes ?? '',
    };
    for (final entry in initial.entries) {
      _fields[entry.key] = TextEditingController(text: entry.value);
    }
    _type = s?.billingType ?? BillingType.fixed;
    _status = s?.status ?? SubscriptionStatus.active;
    _unit = s?.cycle?.unit ?? CycleUnit.month;
    _autoRenew = s?.autoRenew ?? false;
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String text(String key) => field(key).text.trim();
  CivilDate? date(String key) =>
      text(key).isEmpty ? null : CivilDate.fromJson(text(key));
  Widget input(
    String key,
    String label, {
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboard,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey('field.$key'),
      controller: field(key),
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator: validator,
      keyboardType: keyboard,
      maxLines: lines,
      textInputAction: lines == 1
          ? TextInputAction.next
          : TextInputAction.newline,
    ),
  );
  Widget dateInput(String key, String label) => input(
    key,
    label,
    hint: 'YYYY-MM-DD（可留空）',
    validator: (v) {
      if (v == null || v.trim().isEmpty) return null;
      try {
        CivilDate.fromJson(v.trim());
        return null;
      } on Object {
        return '请输入有效日期，例如 2026-10-30';
      }
    },
    keyboard: TextInputType.datetime,
  );
  Future<void> save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final cycle = _type == BillingType.fixed
          ? BillingCycle(_unit, int.parse(text('count')))
          : null;
      final price = text('price').isEmpty
          ? null
          : Money.fromDecimal(
              text('price'),
              text('currency').toUpperCase(),
              int.parse(text('scale')),
            );
      final value = Subscription(
        id: widget.value?.id ?? newId(),
        name: text('name'),
        provider: text('provider'),
        purchaseChannel: text('channel'),
        paymentMethod: text('method'),
        websiteUrl: text('website'),
        notes: text('notes'),
        status: _status,
        billingType: _type,
        price: price,
        cycle: cycle,
        cycleAnchor: date('anchor'),
        startDate: date('start'),
        entitlementEnd: date('end'),
        nextRenewalDate: _type == BillingType.lifetime ? null : date('renewal'),
        autoRenew: _type == BillingType.lifetime ? false : _autoRenew,
        reminderRule: widget.value?.reminderRule ?? ReminderRule(),
      );
      if (!_baseMatches) throw const EchoFailure('conflict', '记录已更新，请重新打开表单');
      await widget.services.saveSubscription(
        value,
        categoryName: text('category'),
        expectedLedgerId: _ledgerId,
        baseParents: _baseParents,
      );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted)
        setState(() {
          _error = safeError(e);
          _saving = false;
        });
    }
  }

  void suggestDate() {
    if (!_form.currentState!.validate()) return;
    try {
      final anchor = date('anchor') ?? date('start');
      if (anchor == null) {
        setState(() {
          _error = '请先填写周期锚点或开始日期';
        });
        return;
      }
      field('renewal').text = occurrence(
        anchor,
        BillingCycle(_unit, int.parse(text('count'))),
        1,
      ).toJson();
      setState(() {
        _error = null;
      });
    } on Object {
      setState(() {
        _error = '请检查周期与日期';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.value == null ? '添加订阅' : '编辑订阅'),
      leading: IconButton(
        key: const ValueKey('editor.cancel'),
        tooltip: '取消，不保存',
        onPressed: _saving ? null : () => Navigator.pop(context),
        icon: const Icon(Icons.close),
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (!_baseMatches) const Text('此记录待确认或已更新，请返回详情处理冲突'),
              const SectionTitle(
                '基本信息',
                subtitle: '价格、权益到期与预计续费分别记录。保存订阅不会自动生成付款。',
              ),
              input(
                'name',
                '服务名称 *',
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '请填写服务名称' : null,
              ),
              input('provider', '服务提供商'),
              input('category', '分类', hint: '输入已有分类或创建新分类'),
              DropdownButtonFormField<BillingType>(
                key: const ValueKey('field.billingType'),
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '计费类型'),
                items: BillingType.values
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(billingText(v)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  _type = v!;
                }),
              ),
              const SizedBox(height: 16),
              input(
                'price',
                _type == BillingType.metered ? '参考价格（可不填）' : '价格（未知请留空）',
                keyboard: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  try {
                    Money.fromDecimal(
                      v.trim(),
                      text('currency').toUpperCase(),
                      int.parse(text('scale')),
                    );
                    return null;
                  } on Object {
                    return '请填写有效金额，并检查币种和小数位数';
                  }
                },
              ),
              input(
                'currency',
                '币种代码',
                hint: 'CNY / USD / JPY',
                validator: (v) =>
                    RegExp(r'^[A-Za-z]{3}$').hasMatch(v?.trim() ?? '')
                    ? null
                    : '请输入三位币种代码',
              ),
              input(
                'scale',
                '金额小数位数',
                hint: 'CNY / USD 为 2，JPY 为 0',
                keyboard: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  return n == null || n < 0 || n > 18 ? '请输入 0–18' : null;
                },
              ),
              if (_type == BillingType.fixed) ...[
                input(
                  'count',
                  '周期数量',
                  keyboard: TextInputType.number,
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return n == null || n <= 0 ? '请输入正整数' : null;
                  },
                ),
                DropdownButtonFormField<CycleUnit>(
                  key: const ValueKey('field.cycleUnit'),
                  initialValue: _unit,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '周期单位'),
                  items: const [
                    DropdownMenuItem(value: CycleUnit.day, child: Text('天')),
                    DropdownMenuItem(value: CycleUnit.week, child: Text('周')),
                    DropdownMenuItem(value: CycleUnit.month, child: Text('月')),
                    DropdownMenuItem(value: CycleUnit.year, child: Text('年')),
                  ],
                  onChanged: (v) => setState(() {
                    _unit = v!;
                  }),
                ),
                const SizedBox(height: 16),
                dateInput('anchor', '周期锚点'),
              ],
              const SizedBox(height: 8),
              const SectionTitle('权益与续费', subtitle: '赠送的使用时间可以比已付费周期更长。'),
              dateInput('start', '开始日期'),
              dateInput('end', '权益到期'),
              if (_type != BillingType.lifetime) ...[
                dateInput('renewal', '预计续费'),
                if (_type == BillingType.fixed)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: suggestDate,
                      icon: const Icon(Icons.event_repeat),
                      label: const Text('按锚点计算下一期'),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自动续费'),
                  value: _autoRenew,
                  onChanged: (v) => setState(() {
                    _autoRenew = v;
                  }),
                ),
              ],
              const SizedBox(height: 16),
              DropdownButtonFormField<SubscriptionStatus>(
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '状态'),
                items: SubscriptionStatus.values
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(statusText(v)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  _status = v!;
                }),
              ),
              const SizedBox(height: 24),
              const SectionTitle('补充信息'),
              input('channel', '购买渠道'),
              input('method', '付款方式'),
              input('website', '服务网址'),
              input('notes', '备注', lines: 3),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
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
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: FilledButton.icon(
            key: const ValueKey('editor.save'),
            onPressed: _saving ? null : save,
            icon: const Icon(Icons.check),
            label: Text(_saving ? '保存中…' : '保存订阅'),
          ),
        ),
      ),
    ),
  );
}
