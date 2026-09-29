import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/parse.dart';

// ─────────────────────────────────────────────────────────────
// ProviderApiService — all data calls go to Hostinger MySQL
// Provider uses JWT token (no Firebase Auth)
// ─────────────────────────────────────────────────────────────

class ProviderApiService {
  static const String _base = 'https://hamaraservice.com/api';
  static const String _tokenKey = 'provider_jwt';

  /// Error message from the most recent failed API call. Read it only right
  /// after a call reported failure.
  static String lastError = '';

  /// HTTP status of the most recent failed API call (e.g. 429 when too many
  /// wrong OTP attempts were made). Read it only right after a failure.
  static int lastStatus = 0;

  static Map<String,dynamic> _decode(http.Response resp) {
    Map<String,dynamic> res;
    try {
      final decoded = jsonDecode(resp.body);
      res = decoded is Map<String,dynamic>
          ? decoded
          : <String,dynamic>{'success': false, 'error': 'Unexpected server response'};
    } catch (_) {
      res = <String,dynamic>{
        'success': false,
        'error': resp.statusCode == 429
            ? 'Too many attempts. Please wait a moment and try again.'
            : 'Server error (${resp.statusCode})',
      };
    }
    // A non-2xx status is always a failure, whatever the body says.
    if (resp.statusCode >= 400 && res['success'] == true) {
      res = {...res, 'success': false};
    }
    // Only written on failure, so a concurrent successful poll can't wipe
    // the message before the failing caller reads it.
    if (res['success'] != true) {
      lastStatus = resp.statusCode;
      final err = (res['error'] ?? res['message'] ?? '').toString();
      lastError = err.isNotEmpty
          ? err
          : (resp.statusCode == 429
              ? 'Too many attempts. Please wait a moment and try again.'
              : 'Request failed');
    }
    return res;
  }

  // ── Token storage ────────────────────────────────────────
  static Future<String> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey) ?? '';
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove('provider_id');
    await prefs.remove('provider_logged_in');
    await prefs.remove('provider_data');
    await prefs.remove('provider_email');
  }

  // ── HTTP helpers ─────────────────────────────────────────
  static Future<Map<String,dynamic>> _get(
      String endpoint, {Map<String,String>? params}) async {
    var uri = Uri.parse('$_base/$endpoint');
    if (params != null) uri = uri.replace(queryParameters: params);
    final token = await getToken();
    final resp = await http.get(uri, headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    }).timeout(const Duration(seconds: 15));
    return _decode(resp);
  }

  static Future<Map<String,dynamic>> _post(
      String endpoint, Map<String,dynamic> body,
      {Map<String,String>? params}) async {
    var uri = Uri.parse('$_base/$endpoint');
    if (params != null) uri = uri.replace(queryParameters: params);
    final token = await getToken();
    final resp = await http.post(uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));
    return _decode(resp);
  }

  // ── AUTH ─────────────────────────────────────────────────

  static Future<Map<String,dynamic>?> login(String email, String password) async {
    final res = await _post('providers.php',
        {'email': email, 'password': password},
        params: {'action': 'login'});
    if (res['success'] == true) {
      final data = res['data'] as Map<String,dynamic>;
      await saveToken(data['token']?.toString() ?? '');
      // Cache provider data
      final prefs = await SharedPreferences.getInstance();
      final provider = data['provider'] as Map<String,dynamic>? ?? {};
      final status = (provider['status'] ?? data['status'] ?? '').toString();
      await prefs.setString('provider_id', provider['id']?.toString() ?? '');
      // Only approved providers are auto-logged-in on next launch.
      // Pending/suspended/rejected must go through the login screen again.
      await prefs.setBool('provider_logged_in', status == 'approved');
      await prefs.setString('provider_data', jsonEncode(provider));
      return data;
    }
    return null;
  }

  /// Registers a provider. Returns the server-generated provider ID on
  /// success ('' if the server did not return one), or null on failure.
  static Future<String?> register(Map<String,dynamic> data) async {
    final res = await _post('providers.php', data,
        params: {'action': 'register'});
    if (res['success'] != true) return null;
    final d = res['data'];
    return d is Map ? (d['id']?.toString() ?? '') : '';
  }

  static Future<void> logout() async {
    await clearToken();
  }

  /// Check if email already registered — returns true if exists
  static Future<bool> checkEmailExists(String email) async {
    try {
      final res = await _get('providers.php',
          params: {'action': 'check_email', 'email': email});
      return res['exists'] == true;
    } catch (_) { return false; }
  }

  // ── PROVIDER PROFILE ─────────────────────────────────────

  static Future<Map<String,dynamic>?> getProfile(String id) async {
    final res = await _get('providers.php',
        params: {'action': 'get', 'id': id});
    if (res['success'] == true) return res['data'] as Map<String,dynamic>?;
    return null;
  }

  static Future<bool> updateProfile(Map<String,dynamic> data) async {
    final res = await _post('providers.php', data,
        params: {'action': 'update'});
    return res['success'] == true;
  }

  static Future<bool> saveFcmToken(String fcmToken) async {
    final res = await _post('providers.php',
        {'fcm_token': fcmToken},
        params: {'action': 'fcm'});
    return res['success'] == true;
  }

  static Future<bool> setAvailable(bool available) async {
    try {
      final res = await _post('providers.php',
          {'available': available},
          params: {'action': 'available'});
      if (res['success'] == true) {
        // Update cache
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString('provider_data');
        if (cached != null) {
          final data = jsonDecode(cached) as Map<String,dynamic>;
          data['available'] = available ? 1 : 0;
          await prefs.setString('provider_data', jsonEncode(data));
        }
        return true;
      }
      return false;
    } catch (_) { return false; }
  }

  // ── SERVICES ─────────────────────────────────────────────

  static Future<List<Map<String,dynamic>>> getMyServices(String providerId) async {
    final res = await _get('providers.php',
        params: {'action': 'services', 'id': providerId});
    if (res['success'] == true) {
      return (res['data'] as List).cast<Map<String,dynamic>>();
    }
    return [];
  }

  static Future<bool> saveMyServices(List<Map<String,dynamic>> services) async {
    final res = await _post('providers.php',
        {'services': services},
        params: {'action': 'services'});
    return res['success'] == true;
  }

  /// Save per-option prices for a service
  /// prices: {groupKey_optionKey: price} e.g. {'sweep_studio': 300, 'sweep_1bhk': 400}
  static Future<bool> saveServiceOptionPrices(
      String svcId, Map<String,int> prices) async {
    final res = await _post('providers.php',
        {'svc_id': svcId, 'option_prices': prices},
        params: {'action': 'save_option_prices'});
    return res['success'] == true;
  }

  /// Get per-option prices for all services
  static Future<Map<String,dynamic>> getServiceOptionPrices() async {
    final res = await _get('providers.php',
        params: {'action': 'get_option_prices'});
    if (res['success'] == true) return res['data'] as Map<String,dynamic>;
    return {};
  }

  static Future<Map<String,dynamic>> getServicePrices(String svcId) async {
    final res = await _get('services.php',
        params: {'action': 'prices', 'id': svcId});
    if (res['success'] == true) return res['data'] as Map<String,dynamic>;
    return {};
  }

  static Future<List<Map<String,dynamic>>> getAllServices() async {
    final res = await _get('services.php', params: {'action': 'all'});
    if (res['success'] == true) {
      return (res['data'] as List).cast<Map<String,dynamic>>();
    }
    return [];
  }

  // ── BOOKINGS ─────────────────────────────────────────────

  /// Get open/available bookings near provider
  static Future<List<Map<String,dynamic>>> getOpenBookings(String providerId) async {
    final profile = await getProfile(providerId);
    if (profile == null) return [];
    final lat = asDouble(profile['lat']);
    final lng = asDouble(profile['lng']);
    // Registration sends `radius`; DB column / profile uses `radius_km`.
    var radius = asDouble(profile['radius_km'] ?? profile['radius'], 10);
    if (radius <= 0) radius = 10;

    // Get active bookings in MySQL
    final res = await _get('bookings.php', params: {
      'action': 'open',
    });
    if (res['success'] != true) return [];
    final all = (res['data'] as List).cast<Map<String,dynamic>>();

    // Filter by distance
    return all.where((b) {
      final bLat = asDouble(b['lat']);
      final bLng = asDouble(b['lng']);
      if (bLat == 0 || bLng == 0) return true;
      if (lat == 0) return true;
      final dist = _haversine(lat, lng, bLat, bLng);
      return dist <= radius;
    }).toList();
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final sinLat = math.sin(dLat / 2);
    final sinLon = math.sin(dLon / 2);
    final a = sinLat * sinLat +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * sinLon * sinLon;
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }
  static double _rad(double d) => d * math.pi / 180;

  static Future<Map<String,dynamic>?> getBooking(String bookingId) async {
    final res = await _get('bookings.php',
        params: {'action': 'get', 'id': bookingId});
    if (res['success'] == true) return res['data'] as Map<String,dynamic>?;
    return null;
  }

  /// Get provider's active booking
  static Future<Map<String,dynamic>?> getActiveBooking(String providerId) async {
    final res = await _get('bookings.php', params: {
      'action': 'active',
      'id':     providerId,
      'role':   'provider',
    });
    if (res['success'] == true && res['data'] != null) {
      return res['data'] as Map<String,dynamic>;
    }
    return null;
  }

  /// Provider accepts booking and quotes price
  static Future<bool> acceptBooking(String bookingId, int quotedPrice) async {
    final res = await _post('bookings.php', {
      'booking_id':   bookingId,
      'quoted_price': quotedPrice,
    }, params: {'action': 'accept'});
    return res['success'] == true;
  }

  /// Provider sends final offer
  static Future<bool> sendFinalOffer(String bookingId, int finalPrice) async {
    final res = await _post('bookings.php', {
      'booking_id':  bookingId,
      'final_price': finalPrice,
    }, params: {'action': 'final_offer'});
    return res['success'] == true;
  }

  /// Provider accepts customer counter
  static Future<bool> acceptCounter(String bookingId) async {
    final res = await _post('bookings.php',
        {'booking_id': bookingId},
        params: {'action': 'accept_counter'});
    return res['success'] == true;
  }

  /// Provider verifies OTP
  static Future<Map<String,dynamic>?> verifyOtp(String bookingId, String otp) async {
    final res = await _post('bookings.php', {
      'booking_id': bookingId,
      'otp':        otp,
    }, params: {'action': 'verify_otp'});
    if (res['success'] == true) return res['data'] as Map<String,dynamic>?;
    return null;
  }

  /// Provider finished the work: server generates the completion OTP and
  /// pushes it to the customer. The OTP is NOT returned to the provider;
  /// the customer reads it out and the provider submits it via [completeBooking].
  static Future<bool> requestCompletionOtp(String bookingId) async {
    final res = await _post('bookings.php',
        {'booking_id': bookingId},
        params: {'action': 'request_completion_otp'});
    return res['success'] == true;
  }

  /// Completes the job with the completion OTP the customer shared.
  static Future<bool> completeBooking(String bookingId, String completionOtp) async {
    final res = await _post('bookings.php', {
      'booking_id':     bookingId,
      'completion_otp': completionOtp,
    }, params: {'action': 'complete'});
    return res['success'] == true;
  }

  /// Genuine cancellation of a booking (stored with cancel_reason and
  /// cancelled_by='provider'). To back out of a job before work starts use
  /// [releaseBooking] instead, which returns it to other providers.
  static Future<bool> cancelBooking(String bookingId, {String reason = ''}) async {
    final res = await _post('bookings.php', {
      'booking_id': bookingId,
      if (reason.isNotEmpty) 'reason': reason,
    }, params: {'action': 'cancel'});
    return res['success'] == true;
  }

  /// Assigned provider backs out before work starts (price_quoted,
  /// negotiating, negotiation_final, confirmed). The booking goes back to
  /// 'searching' and the server notifies the customer.
  static Future<bool> releaseBooking(String bookingId) async {
    final res = await _post('bookings.php',
        {'booking_id': bookingId},
        params: {'action': 'release'});
    return res['success'] == true;
  }

  /// Live location while travelling to / working on a confirmed|active job.
  static Future<bool> trackLocation(String bookingId, double lat, double lng) async {
    final res = await _post('bookings.php', {
      'booking_id': bookingId,
      'lat':        lat,
      'lng':        lng,
    }, params: {'action': 'track'});
    return res['success'] == true;
  }

  /// Provider rates the customer (once) after a completed booking.
  static Future<bool> rateCustomer(String bookingId, int rating, {String comment = ''}) async {
    final res = await _post('bookings.php', {
      'booking_id': bookingId,
      'rating':     rating,
      if (comment.isNotEmpty) 'comment': comment,
    }, params: {'action': 'rate_customer'});
    return res['success'] == true;
  }

  /// Provider confirms the customer's cash payment (payment_status
  /// 'cash_pending' -> 'paid').
  static Future<bool> markPaid(String bookingId) async {
    final res = await _post('bookings.php',
        {'booking_id': bookingId},
        params: {'action': 'mark_paid'});
    return res['success'] == true;
  }

  /// Get booking history for provider
  static Future<List<Map<String,dynamic>>> getBookingHistory(String providerId) async {
    final res = await _get('bookings.php', params: {
      'action': 'history',
      'id':     providerId,
      'role':   'provider',
    });
    if (res['success'] == true) {
      return (res['data'] as List).cast<Map<String,dynamic>>();
    }
    return [];
  }

  // ── EARNINGS / PAYOUTS ───────────────────────────────────

  static Future<Map<String,dynamic>> getBalance(String providerId) async {
    final res = await _get('payouts.php',
        params: {'action': 'balance', 'id': providerId});
    if (res['success'] == true) return res['data'] as Map<String,dynamic>;
    return {};
  }

  static Future<bool> requestPayout(Map<String,dynamic> data) async {
    final res = await _post('payouts.php', data,
        params: {'action': 'request'});
    return res['success'] == true;
  }

  static Future<List<Map<String,dynamic>>> getPayoutHistory(String providerId) async {
    final res = await _get('payouts.php',
        params: {'action': 'history', 'id': providerId});
    if (res['success'] == true) {
      return (res['data'] as List).cast<Map<String,dynamic>>();
    }
    return [];
  }

  /// Cancels a withdrawal request that is still 'pending'; the amount is
  /// returned to the withdrawable balance.
  static Future<bool> cancelPayout(String payoutId) async {
    final res = await _post('payouts.php',
        {'payout_id': payoutId},
        params: {'action': 'cancel'});
    return res['success'] == true;
  }

  /// Penalties applied to this provider (provider sees only their own).
  static Future<List<Map<String,dynamic>>> getPenalties() async {
    final res = await _get('penalties.php', params: {'action': 'list'});
    if (res['success'] != true) return [];
    final d = res['data'];
    final list = d is List ? d : (d is Map ? (d['rows'] ?? d['penalties']) : null);
    if (list is! List) return [];
    return list.whereType<Map>().map((m) => Map<String,dynamic>.from(m)).toList();
  }

  // ── AVAILABILITY SCHEDULE ────────────────────────────────

  /// Weekly schedule: {mon:{on:true,from:"09:00",to:"18:00"}, ... sun}.
  /// Read it back from [getProfile] (`schedule`).
  static Future<bool> saveSchedule(Map<String,dynamic> schedule) async {
    final res = await _post('providers.php',
        {'schedule': schedule},
        params: {'action': 'schedule'});
    return res['success'] == true;
  }

  // ── REVIEWS ──────────────────────────────────────────────

  static Future<List<Map<String,dynamic>>> getReviews(String providerId) async {
    final res = await _get('reviews.php',
        params: {'action': 'provider', 'id': providerId});
    if (res['success'] == true) {
      return (res['data'] as List).cast<Map<String,dynamic>>();
    }
    return [];
  }

  // ── CACHED PROVIDER DATA ─────────────────────────────────

  static Future<Map<String,dynamic>?> getCachedProvider() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('provider_data');
    if (s == null) return null;
    return jsonDecode(s) as Map<String,dynamic>;
  }

  static Future<void> cacheProvider(Map<String,dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('provider_data', jsonEncode(data));
  }
}
