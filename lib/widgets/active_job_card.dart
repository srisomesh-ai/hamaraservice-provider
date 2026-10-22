import 'package:flutter/material.dart';
import '../utils/parse.dart';
import '../utils/theme.dart';
import 'new_job_card.dart';
import 'ui.dart';

/// Amount shown for a booking (web: amount || confirmed || final || quoted).
int bookingAmount(Map<String, dynamic> b) {
  for (final k in ['amount', 'confirmed_price', 'final_price', 'quoted_price']) {
    final v = toInt(b[k]);
    if (v > 0) return v;
  }
  return 0;
}

/// "Customer has m:ss left to confirm" / "⌛ Time up — job will be released"
String quoteLeftText(DateTime? deadline) {
  if (deadline == null) return '';
  var left = (deadline.difference(DateTime.now()).inMilliseconds / 1000).round();
  if (left < 0) left = 0;
  return left > 0
      ? 'Customer has ${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')} left to confirm'
      : '⌛ Time up — job will be released';
}

/// Current job on the Jobs tab: status, progress stepper, key details and
/// one big button that opens the full job screen.
class ActiveJobCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final DateTime? quoteDeadline;
  final VoidCallback onOpen;
  final VoidCallback? onAddMoney;
  const ActiveJobCard(
      {super.key, required this.booking, this.quoteDeadline, required this.onOpen, this.onAddMoney});

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final t = Theme.of(context).textTheme;
    final st = str(b['status']);
    final paid = str(b['payment_status']) == 'paid';
    final name = str(b['contact_name'], str(b['customer_name']));
    final phone = str(b['contact_phone'], str(b['customer_phone']));
    final amount = bookingAmount(b);
    final fee = toInt(b['platform_fee']);
    final onlineOnly = (st == 'confirmed' || st == 'active') &&
        toInt(b['cash_allowed'], 1) == 0 && fee > 0;
    final slot = slotWhen(b['slot_date'], b['slot_time']);
    final place = jobPlace(b);

    String msg = '';
    Tone tone = Tone.info;
    String action = 'View job';
    IconData actionIcon = Icons.arrow_forward_rounded;
    switch (st) {
      case 'price_quoted':
        msg = 'Waiting for customer to confirm your price ₹${toInt(b['quoted_price'])}';
        tone = Tone.warning;
        break;
      case 'negotiating':
        msg = 'Customer offered ₹${toInt(b['counter_price'])} (your quote ₹${toInt(b['quoted_price'])})';
        tone = Tone.warning;
        action = 'Respond to offer';
        actionIcon = Icons.forum_outlined;
        break;
      case 'negotiation_final':
        msg = 'Final price ₹${toInt(b['final_price'])} sent — waiting for customer';
        tone = Tone.warning;
        break;
      case 'confirmed':
        if (toInt(b['start_otp_requested']) == 1) {
          msg = 'The customer has the Start OTP. Ask them for it and enter it.';
          action = 'Enter Start OTP';
          actionIcon = Icons.pin_outlined;
        } else if (str(b['travel_started_at']).isNotEmpty) {
          msg = 'On the way. Tap “I\'ve arrived” when you reach the customer.';
          action = 'I\'ve arrived';
          actionIcon = Icons.where_to_vote_rounded;
        } else {
          msg = 'Customer confirmed. Start the trip when you leave.';
          action = 'Start trip';
          actionIcon = Icons.navigation_rounded;
        }
        tone = Tone.success;
        break;
      case 'active':
        msg = toInt(b['completion_otp_requested']) == 1
            ? 'The customer has received the Completion OTP. Ask them for it and enter it.'
            : 'Job in progress. When the work is finished, request the completion OTP.';
        tone = Tone.info;
        action = 'Finish job';
        actionIcon = Icons.task_alt_rounded;
        break;
      case 'completed':
        msg = paid
            ? '₹$amount paid ${str(b['payment_method']) == 'cash' ? 'in cash' : 'online'}'
            : '₹$amount — waiting for payment';
        tone = paid ? Tone.success : Tone.warning;
        action = paid ? 'View job' : 'Payment';
        actionIcon = paid ? Icons.arrow_forward_rounded : Icons.payments_outlined;
        break;
    }
    final left = (st == 'price_quoted' || st == 'negotiation_final') ? quoteLeftText(quoteDeadline) : '';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 48, height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(14)),
                child: Text(jobIcon(b), style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(str(b['svc_name'], 'Service'),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
                  Text(str(b['id']), style: t.bodySmall),
                ]),
              ),
              const SizedBox(width: 8),
              StatusBadge(st, paymentStatus: str(b['payment_status'])),
            ]),
            const SizedBox(height: 18),
            JobStepper(status: st, paid: paid),
            const SizedBox(height: 14),
            if (name.isNotEmpty || phone.isNotEmpty)
              DetailLine(Icons.person_outline_rounded,
                  [name.isEmpty ? 'Customer' : name, if (phone.isNotEmpty) phone].join(' · ')),
            if (place.isNotEmpty) DetailLine(Icons.place_outlined, place, maxLines: 2),
            if (slot.isNotEmpty) DetailLine(Icons.schedule_rounded, slot),
            const SizedBox(height: 8),
            Row(children: [
              Text('₹$amount',
                  style: t.headlineSmall?.copyWith(color: AppColors.teal2, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (st == 'active' && str(b['started_at']).isNotEmpty)
                Text('Started ${istTime(b['started_at'])}', style: t.bodySmall),
            ]),
            if (msg.isNotEmpty) ...[
              const SizedBox(height: 10),
              Notice(msg, tone: tone),
            ],
            if (left.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(left,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
              ),
            if (onlineOnly) ...[
              const SizedBox(height: 10),
              Notice(
                'Online payment only for this job — your wallet balance is less than the platform fee ₹$fee. '
                'Tell the customer to pay online (do not collect cash), or add at least ₹$fee to your wallet to accept cash.',
                tone: Tone.error,
                icon: Icons.credit_card_rounded,
                action: onAddMoney == null
                    ? null
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: onAddMoney,
                          icon: const Icon(Icons.add_card_rounded, size: 18),
                          label: const Text('Add money'),
                        ),
                      ),
              ),
            ],
            const SizedBox(height: 14),
            BigButton(action, icon: actionIcon, onPressed: onOpen),
          ]),
        ),
      ),
    );
  }
}
