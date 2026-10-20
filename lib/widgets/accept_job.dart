import 'package:flutter/material.dart';
import '../services/provider_api_service.dart';
import '../utils/parse.dart';
import 'ui.dart';

/// Provider's own {min_price, max_price} for a service.
class PriceRange {
  final int min;
  final int max;
  const PriceRange(this.min, this.max);
}

/// Looks up the provider's range for [svcId] in the `services` rows of
/// providers.php?action=get.
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

/// "My saved price" for a job — same order as the website's myPriceFor():
/// 1. lowest option price the provider saved for the service
///    (providers.php?action=get_option_prices),
/// 2. the provider's own minimum (price range),
/// 3. the admin default price for the service (services.php price_ranges).
int savedPriceFor(
  String svcId, {
  Map<String, dynamic>? optionPrices,
  PriceRange range = const PriceRange(0, 0),
  Map<String, dynamic>? adminRanges,
}) {
  final sv = optionPrices?[svcId];
  if (sv is Map) {
    final vals = sv.values.map((v) => toInt(v)).where((n) => n > 0).toList();
    if (vals.isNotEmpty) {
      vals.sort();
      return vals.first;
    }
  }
  if (range.min > 0) return range.min;
  final ad = adminRanges?[svcId];
  final ap = ad is Map ? ad['admin_prices'] : null;
  if (ap is Map) {
    for (final v in ap.values) {
      final n = toInt(v);
      if (n > 0) return n;
    }
  }
  return 0;
}

/// POST bookings.php?action=accept with the provider's price.
/// Shows the result as a SnackBar (web wording) and returns true on success.
Future<bool> sendQuote(BuildContext context, String bookingId, int price) async {
  if (price < 1) {
    showSnack(context, 'Enter your price for this job', tone: Tone.error);
    return false;
  }
  final res = await ProviderApiService.acceptBooking(bookingId, price);
  if (!context.mounted) return false;
  if (res.ok) {
    showSnack(context, '✅ Quote sent to customer!', tone: Tone.success);
    return true;
  }
  if (res.unauthorized) return false;
  // 409 taken / busy, 402 commission dues — the server text explains it.
  showSnack(context, res.error.isNotEmpty ? res.error : 'Job no longer available',
      tone: Tone.error);
  return false;
}
