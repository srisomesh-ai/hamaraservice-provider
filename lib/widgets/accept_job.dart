import 'package:flutter/material.dart';
import '../services/provider_api_service.dart';
import '../utils/parse.dart';
import '../utils/theme.dart';

/// Looks up the provider's own {min_price, max_price} for [svcId] in the
/// `services` rows of providers.php?action=get.
class PriceRange {
  final int min;
  final int max;
  const PriceRange(this.min, this.max);
}

PriceRange priceRangeFor(Map<String, dynamic>? profile, String svcId) {
  final rows = profile?['services'];
  if (rows is List) {
    for (final r in rows) {
      if (r is Map && '${r['svc_id']}' == svcId) {
        return PriceRange(toInt(r['min_price']), toInt(r['max_price']));
      }
    }
  }
  return const PriceRange(0, 0);
}

/// Shows the quote dialog, then POSTs bookings.php?action=accept.
/// Returns true only when the server accepted (caller may then navigate).
/// All failures are shown to the user here.
Future<bool> acceptJobWithQuote(
  BuildContext context,
  Map<String, dynamic> booking,
  Map<String, dynamic>? profile,
) async {
  final bookingId = str(booking['id']);
  if (bookingId.isEmpty) return false;
  final svcId = str(booking['svc_id']);
  final range = priceRangeFor(profile, svcId);
  final est = toInt(booking['est_price']);
  final prefill = range.min > 0 ? range.min : (est > 0 ? est : 0);

  final quoted = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _QuoteDialog(
      svcName: str(booking['svc_name'], 'Service'),
      minPrice: range.min,
      maxPrice: range.max,
      estPrice: est,
      prefill: prefill,
    ),
  );
  if (quoted == null || quoted <= 0) return false;
  if (!context.mounted) return false;

  final res = await ProviderApiService.acceptBooking(bookingId, quoted);
  if (!context.mounted) return false;
  if (res.ok) return true;
  if (res.unauthorized) return false;

  String msg = res.error;
  if (res.status == 409 && msg.toLowerCase().contains('another provider')) {
    msg = 'Another provider took this job';
  } else if (res.status == 409 && msg.toLowerCase().contains('no longer')) {
    msg = 'This job is no longer available';
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: AppColors.red,
    behavior: SnackBarBehavior.floating,
  ));
  return false;
}

class _QuoteDialog extends StatefulWidget {
  final String svcName;
  final int minPrice, maxPrice, estPrice, prefill;
  const _QuoteDialog({
    required this.svcName,
    required this.minPrice,
    required this.maxPrice,
    required this.estPrice,
    required this.prefill,
  });
  @override
  State<_QuoteDialog> createState() => _QuoteDialogState();
}

class _QuoteDialogState extends State<_QuoteDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.prefill > 0 ? '${widget.prefill}' : '');
  String _err = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = int.tryParse(_ctrl.text.trim()) ?? 0;
    if (v <= 0) {
      setState(() => _err = 'Enter a price greater than 0');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Enter Your Quote',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text(widget.svcName,
            style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w500)),
      ]),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.minPrice > 0 || widget.maxPrice > 0)
            _info('Your range: ₹${widget.minPrice} – ₹${widget.maxPrice}'),
          if (widget.estPrice > 0) ...[
            const SizedBox(height: 6),
            _info('Customer estimate ₹${widget.estPrice}'),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Your quoted price (₹)',
              prefixText: '₹ ',
              errorText: _err.isEmpty ? null : _err,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 8),
          const Text('The customer sees this price and can accept or negotiate.',
              style: TextStyle(fontSize: 11, color: AppColors.muted)),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: AppColors.muted)),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.teal, minimumSize: const Size(110, 44)),
          child: const Text('Send Quote', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _info(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: AppColors.tealSoft, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.teal, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.teal, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}
