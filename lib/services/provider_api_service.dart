import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────
// ProviderApiService — all data calls go to Hostinger MySQL
// Provider uses JWT token (no Firebase Auth)
// ─────────────────────────────────────────────────────────────

class ProviderApiService {
  static const String _base = 'https://hamaraservice.com/api';
  static const String _tokenKey = 'provider_jwt';

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
    return jsonDecode(resp.body) as Map<String,dynamic>;
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
    return jsonDecode(resp.body) as Map<String,dynamic>;
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
      await prefs.setString('provider_id', provider['id']?.toString() ?? '');
      await prefs.setBool('provider_logged_in', true);
      await prefs.setString('provider_data', jsonEncode(provider));
      return data;
    }
    return null;
  }

  static Future<bool> register(Map<String,dynamic> data) async {
    final res = await _post('providers.php', data,
        params: {'action': 'register'});
    return res['success'] == true;
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
    final lat = (profile['lat'] as num?)?.toDouble() ?? 0;
    final lng = (profile['lng'] as num?)?.toDouble() ?? 0;
    final radius = (profile['radius_km'] as num?)?.toDouble() ?? 10;

    // Get active bookings in MySQL
    final res = await _get('bookings.php', params: {
      'action': 'open',
    });
    if (res['success'] != true) return [];
    final all = (res['data'] as List).cast<Map<String,dynamic>>();

    // Filter by distance
    return all.where((b) {
      final bLat = (b['lat'] as num?)?.toDouble() ?? 0;
      final bLng = (b['lng'] as num?)?.toDouble() ?? 0;
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
    final a = _sin2(dLat/2) + _sin2(dLon/2) * _cos(_rad(lat1)) * _cos(_rad(lat2));
    return r * 2 * _asin(_sqrt(a));
  }
  static double _rad(double d) => d * 3.141592653589793 / 180;
  static double _sin2(double x) => _sin(x) * _sin(x);
  static double _sin(double x) => x - x*x*x/6 + x*x*x*x*x/120;
  static double _cos(double x) => 1 - x*x/2 + x*x*x*x/24;
  static double _asin(double x) => x + x*x*x/6;
  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double r = x; for (int i = 0; i < 20; i++) r = (r + x/r) / 2; return r;
  }

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

  /// Cancel/decline booking
  static Future<bool> cancelBooking(String bookingId) async {
    final res = await _post('bookings.php',
        {'booking_id': bookingId},
        params: {'action': 'cancel'});
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
