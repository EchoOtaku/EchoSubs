import 'package:flutter/material.dart';
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
        const SectionTitle('付款记录', subtitle: '真实付款，独立于预计续费与权益期限'),
        if (payments.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text('暂无付款记录。在订阅详情中选择「记录付款 / 续费」。'),
            ),
          ),
        for (final payment in payments)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PaymentCard(
              payment: payment,
              name:
                  services.subscriptions
                      .where((s) => s.id == payment.subscriptionId)
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
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text(name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('实付 ${moneyText(payment.amount)}'),
          Text('付款日期 ${dateText(payment.paidOn)}'),
          if (payment.periodStart != null || payment.periodEnd != null)
            Text(
              '对应周期 ${dateText(payment.periodStart)} 至 ${dateText(payment.periodEnd)}',
            ),
          if (payment.notes?.isNotEmpty == true) Text(payment.notes!),
        ],
      ),
    ),
  );
}
