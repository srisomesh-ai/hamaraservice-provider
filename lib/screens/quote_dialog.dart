import 'package:flutter/material.dart';
import '../services/provider_api_service.dart';
import '../utils/parse.dart';
import '../utils/theme.dart';

/// Asks the provider for a quoted price for [booking].
/// Pre-fills with the provider's saved min price for the booking's service.
/// Returns the entered price (> 0), or null if cancelled.
/// Shared by the dashboard incoming-job alert and the Open Jobs tab.
Future<int?> showQuoteDialog(
    BuildContext context, String providerId, Map<String, dynamic> booking) async {
  final svcId = bookingServiceIdOf(booking);

  // Get provider's min/max for this service
  int minPrice = 0;
  int maxPrice = 0;
  try {
    final mysvcs = await ProviderApiService.getMyServices(providerId);
    final svcMatch =
        mysvcs.where((s) => serviceIdOf(s) == svcId && svcId.isNotEmpty).toList();
    if (svcMatch.isNotEmpty) {
      final sd = svcMatch.first;
      minPrice = asInt(sd['min_price']);
      maxPrice = asInt(sd['max_price']);
    }
  } catch (_) {}

  if (!context.mounted) return null;

  final svcName =
      (booking['svc_name'] ?? booking['service'] ?? '').toString();
  final quoteCtrl =
      TextEditingController(text: minPrice > 0 ? '$minPrice' : '');
  final quoted = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Enter Your Quote',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text(svcName,
            style: const TextStyle(
                fontSize: 13,
                color: AppColors.muted,
                fontWeight: FontWeight.w500)),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (minPrice > 0 && maxPrice > 0)
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AppColors.tealSoft,
                  borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded,
                    color: AppColors.teal, size: 16),
                const SizedBox(width: 8),
                Text('Your range: ₹$minPrice – ₹$maxPrice',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.teal,
                        fontWeight: FontWeight.w700)),
              ])),
        const SizedBox(height: 14),
        TextField(
          controller: quoteCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
              labelText: 'Your quoted price (₹)',
              prefixText: '₹ ',
              hintText: minPrice > 0 ? '$minPrice' : 'Enter price',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        ),
        const SizedBox(height: 8),
        const Text('Customer will see this price and can accept or negotiate.',
            style: TextStyle(fontSize: 11, color: AppColors.muted)),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.muted))),
        ElevatedButton(
            onPressed: () {
              final v = int.tryParse(quoteCtrl.text.trim()) ?? 0;
              if (v <= 0) return;
              Navigator.pop(ctx, v);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal),
            child: const Text('Send Quote',
                style: TextStyle(color: Colors.white))),
      ],
    ),
  );
  // Not disposing quoteCtrl here: the dialog's exit animation may still
  // reference it for a few frames.
  return quoted;
}
