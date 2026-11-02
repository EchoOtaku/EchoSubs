import 'package:flutter/material.dart';
import '../../../app/design_system.dart';
import '../../../app/services.dart';
import '../../../core/model/payment.dart';
import 'widgets.dart';

class PaymentsPage extends StatelessWidget {
  const PaymentsPage({super.key, required this.services, this.subscriptionId});
  final AppServices services;
  final String? subscriptionId;
  @override
  Widget build(BuildContext context) {
    final payments =
        services.payments
            .where(
              (p) =>
                  subscriptionId == null || p.subscriptionId == subscriptionId,
            )
            .toList()
          ..sort((a, b) => b.paidOn.compareTo(a.paidOn));
    return PageContent(
      children: [
        const SectionTitle('付款记录', subtitle: '查看已发生的付款、日期与对应周期'),
        if (payments.isEmpty)
          const EchoPanel(child: Text('暂无付款记录。在订阅详情中选择「记录付款 / 续费」。')),
        for (final payment in payments)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PaymentCard(
              payment: payment,
              name:
                  services.subscriptions
                      .where((value) => value.id == payment.subscriptionId)
                      .firstOrNull
                      ?.name ??
                  '已删除的订阅',
            ),
          ),
      ],
    );
  }
}

class PaymentCard extends StatelessWidget {
  const PaymentCard({super.key, required this.payment, required this.name});
  final Payment payment;
  final String name;
  @override
  Widget build(BuildContext context) {
    final amount = moneyText(payment.amount), paid = dateText(payment.paidOn);
    final start = dateText(payment.periodStart),
        end = dateText(payment.periodEnd);
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 5),
        Text('付款日期 $paid', style: Theme.of(context).textTheme.bodySmall),
        if (payment.periodStart != null || payment.periodEnd != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '对应周期 $start 至 $end',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (payment.notes?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              payment.notes!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    );
    final paidAmount = Text(
      '实付 $amount',
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return EchoPanel(
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ServiceAvatar(name),
            const SizedBox(width: 14),
            Expanded(
              child: constraints.maxWidth >= 620
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: details),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topRight,
                            child: paidAmount,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        details,
                        const SizedBox(height: 12),
                        paidAmount,
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
