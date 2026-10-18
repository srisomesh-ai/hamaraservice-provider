import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────
// ProviderApiService — every data call goes to the HamaraService PHP API
// (docs/API_CONTRACT.md). Providers authenticate with the JWT returned by
// providers.php?action=login, sent as `Authorization: Bearer <jwt>`.
// ─────────────────────────────────────────────────────────────

/// Result of an API call. `ok` mirrors the server's `success` flag;
/// `error` is the server's message (or a readable network/parse error).
class ApiResult {
  final bool ok;
  final dynamic data;
  final String error;
  final int status; // HTTP status, 0 = network error / no response

  const ApiResult(this.ok, this.data, this.error, this.status);

  bool get unauthorized => status == 401;
  bool get conflict => status == 409;
  bool get networkError => status == 0;

  Map<String, dynamic>? get map =>
      data is Map ? Map<String, dynamic>.from(data as Map) : null;

  List<Map<String, dynamic>> get list => data is List
      ? (data as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList()
      : <Map<String, dynamic>>[];
}

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

class ProviderApiService {
  static const String base = 'https://hamaraservice.com/api';
  static const String _tokenKey = 'provider_jwt';
  static const Duration _timeout = Duration(seconds: 20);

  /// Called once whenever an authenticated request gets HTTP 401
  /// (expired/rotated JWT). main.dart wires this to "clear token → login".
  static void Function()? onUnauthorized;
  static bool _handling401 = false;

  // ── Token storage ────────────────────────────────────────
  static Future<String> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey) ?? '';
  }

  static Future<bool> hasToken() async => (await getToken()).isNotEmpty;

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    _handling401 = false;
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove('provider_id');
    await prefs.remove('provider_logged_in');
    await prefs.remove('provider_data');
    await prefs.remove('provider_email');
  }

  // ── HTTP core ────────────────────────────────────────────
  static Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await getToken();
    return {
      if (json) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Uri _uri(String endpoint, Map<String, String>? params) {
    final uri = Uri.parse('$base/$endpoint');
    return params == null ? uri : uri.replace(queryParameters: params);
  }

  static Future<ApiResult> _send(
      Future<http.Response> Function(Map<String, String> headers) call,
      {bool json = true}) async {
    final headers = await _headers(json: json);
    final hadToken = headers.containsKey('Authorization');
    http.Response resp;
    try {
      resp = await call(headers).timeout(_timeout);
    } on TimeoutException {
      return const ApiResult(false, null, 'Server is taking too long. Check your internet and try again.', 0);
    } on SocketException {
      return const ApiResult(false, null, 'No internet connection.', 0);
    } catch (e) {
      return ApiResult(false, null, 'Network error: $e', 0);
    }
    return _parse(resp, hadToken);
  }

  static ApiResult _parse(http.Response resp, bool hadToken) {
    final code = resp.statusCode;
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      body = null;
    }

    if (code == 401 && hadToken) _notifyUnauthorized();

    if (body is! Map) {
      final msg = code >= 500
          ? 'Server error ($code). Please try again shortly.'
          : code == 401
              ? 'Session expired. Please log in again.'
              : 'Unexpected server response ($code).';
      return ApiResult(false, null, msg, code);
    }
    final success = body['success'] == true && code >= 200 && code < 300;
    if (success) {
      // check_email returns {exists, success} at the top level
      final data = body.containsKey('data') ? body['data'] : body;
      return ApiResult(true, data, '', code);
    }
    var err = '${body['error'] ?? body['message'] ?? ''}'.trim();
    if (err.isEmpty) err = 'Request failed ($code).';
    if (code == 401) err = 'Session expired. Please log in again.';
    return ApiResult(false, body['data'], err, code);
  }

  static void _notifyUnauthorized() {
    if (_handling401) return;
    _handling401 = true;
    clearToken();
    final cb = onUnauthorized;
    if (cb != null) cb();
  }

  static Future<ApiResult> get(String endpoint,
      {Map<String, String>? params}) {
    return _send((h) => http.get(_uri(endpoint, params), headers: h));
  }

  static Future<ApiResult> post(String endpoint, Map<String, dynamic> body,
      {Map<String, String>? params}) {
    return _send((h) =>
        http.post(_uri(endpoint, params), headers: h, body: jsonEncode(body)));
  }

  static Future<ApiResult> _bk(String action, Map<String, dynamic> body) =>
      post('bookings.php', body, params: {'action': action});

  // ── AUTH ─────────────────────────────────────────────────

  /// Logs in. On success saves the JWT + provider cache. `provider_logged_in`
  /// is only persisted for approved providers.
  static Future<ApiResult> login(String email, String password) async {
    final res = await post('providers.php',
        {'email': email, 'password': password},
        params: {'action': 'login'});
    if (!res.ok) return res;
    final data = res.map ?? {};
    final token = '${data['token'] ?? ''}';
    if (token.isEmpty) {
      return ApiResult(false, null, 'Login failed: no token returned.', res.status);
    }
    await saveToken(token);
    final provider = data['provider'] is Map
        ? Map<String, dynamic>.from(data['provider'] as Map)
        : <String, dynamic>{};
    final status = '${data['status'] ?? provider['status'] ?? 'pending'}';
    provider['status'] = status;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('provider_id', '${provider['id'] ?? ''}');
    await prefs.setString('provider_data', jsonEncode(provider));
    await prefs.setBool('provider_logged_in', status == 'approved');
    return res;
  }

  static Future<void> markLoggedIn(bool approved) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('provider_logged_in', approved);
  }

  static Future<ApiResult> register(Map<String, dynamic> data) =>
      post('providers.php', data, params: {'action': 'register'});

  /// Logout: go offline (best effort), drop the JWT and cached data.
  static Future<void> logout() async {
    try {
      if (await hasToken()) await setAvailable(false);
    } catch (_) {}
    await clearToken();
  }

  /// true / false, or null when the check itself failed.
  static Future<bool?> checkEmailExists(String email) async {
    final res = await get('providers.php',
        params: {'action': 'check_email', 'email': email});
    if (!res.ok) return null;
    final m = res.map ?? {};
    return m['exists'] == true;
  }

  // ── PROVIDER PROFILE ─────────────────────────────────────

  /// Own full profile (no id) — includes `services` rows.
  static Future<ApiResult> getMyProfile() async {
    final res = await get('providers.php', params: {'action': 'get'});
    if (res.ok && res.map != null) await cacheProvider(res.map!);
    return res;
  }

  static Future<ApiResult> updateProfile(Map<String, dynamic> data) =>
      post('providers.php', data, params: {'action': 'update'});

  /// Upload profile photo (multipart field 'photo'). Returns {photo: url}.
  static Future<ApiResult> uploadPhoto(File file) async {
    return _send((h) async {
      final req = http.MultipartRequest(
          'POST', _uri('upload.php', {'action': 'provider_photo'}));
      req.headers.addAll(h);
      req.files.add(await http.MultipartFile.fromPath('photo', file.path));
      final streamed = await req.send();
      return http.Response.fromStream(streamed);
    }, json: false);
  }

  static Future<ApiResult> saveFcmToken(String fcmToken) =>
      post('providers.php', {'fcm_token': fcmToken}, params: {'action': 'fcm'});

  static Future<ApiResult> setAvailable(bool available) async {
    final res = await post('providers.php', {'available': available ? 1 : 0},
        params: {'action': 'available'});
    if (res.ok) {
      final cached = await getCachedProvider();
      if (cached != null) {
        cached['available'] = available ? 1 : 0;
        await cacheProvider(cached);
      }
    }
    return res;
  }

  static Future<ApiResult> sendLocation(double lat, double lng) =>
      post('providers.php', {'lat': lat, 'lng': lng},
          params: {'action': 'location'});

  // ── SERVICES ─────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getMyServices(String providerId) async {
    final res = await get('providers.php',
        params: {'action': 'services', 'id': providerId});
    if (!res.ok) throw ApiException(res.error, res.status);
    return res.list;
  }

  static Future<void> saveMyServices(List<Map<String, dynamic>> services) async {
    final res = await post('providers.php', {'services': services},
        params: {'action': 'services'});
    if (!res.ok) throw ApiException(res.error, res.status);
  }

  /// Save per-option prices for a service
  /// prices: {groupKey_optionKey: price} e.g. {'sweep_studio': 300}
  static Future<void> saveServiceOptionPrices(
      String svcId, Map<String, int> prices) async {
    final res = await post('providers.php',
        {'svc_id': svcId, 'option_prices': prices},
        params: {'action': 'save_option_prices'});
    if (!res.ok) throw ApiException(res.error, res.status);
  }

  /// Per-option prices for all services
  static Future<Map<String, dynamic>> getServiceOptionPrices() async {
    final res = await get('providers.php', params: {'action': 'get_option_prices'});
    return res.ok ? (res.map ?? {}) : {};
  }

  static Future<Map<String, dynamic>> getServicePrices(String svcId) async {
    final res = await get('services.php', params: {'action': 'prices', 'id': svcId});
    return res.ok ? (res.map ?? {}) : {};
  }

  // ── BOOKINGS ─────────────────────────────────────────────

  /// Open jobs — already filtered server-side by my services + radius/city,
  /// with PII stripped and `distance_km` added.
  static Future<ApiResult> getOpenBookings() =>
      get('bookings.php', params: {'action': 'open'});

  static Future<ApiResult> getBooking(String bookingId) =>
      get('bookings.php', params: {'action': 'get', 'id': bookingId});

  /// My current booking (includes completed-but-unpaid) or data == null.
  static Future<ApiResult> getActiveBooking() =>
      get('bookings.php', params: {'action': 'active'});

  static Future<ApiResult> getBookingHistory() =>
      get('bookings.php', params: {'action': 'history'});

  static Future<ApiResult> acceptBooking(String bookingId, int quotedPrice) =>
      _bk('accept', {'booking_id': bookingId, 'quoted_price': quotedPrice});

  static Future<ApiResult> sendFinalOffer(String bookingId, int finalPrice) =>
      _bk('final_offer', {'booking_id': bookingId, 'final_price': finalPrice});

  static Future<ApiResult> acceptCounter(String bookingId) =>
      _bk('accept_counter', {'booking_id': bookingId});

  /// Provider gives up the job before it starts → back to `searching`.
  static Future<ApiResult> releaseBooking(String bookingId) =>
      _bk('release', {'booking_id': bookingId});

  /// START OTP (shown by the customer at the door).
  static Future<ApiResult> verifyStartOtp(String bookingId, String otp) =>
      _bk('verify_otp', {'booking_id': bookingId, 'otp': otp});

  static Future<ApiResult> requestCompletionOtp(String bookingId) =>
      _bk('request_completion_otp', {'booking_id': bookingId});

  static Future<ApiResult> completeBooking(String bookingId, String completionOtp) =>
      _bk('complete', {'booking_id': bookingId, 'completion_otp': completionOtp});

  static Future<ApiResult> cashCollected(String bookingId) =>
      _bk('cash_collected', {'booking_id': bookingId});

  static Future<ApiResult> requestReview(String bookingId) =>
      _bk('request_review', {'booking_id': bookingId});

  // ── EARNINGS / PAYOUTS ───────────────────────────────────

  static Future<ApiResult> getBalance() =>
      get('payouts.php', params: {'action': 'balance'});

  static Future<ApiResult> requestPayout(Map<String, dynamic> data) =>
      post('payouts.php', data, params: {'action': 'request'});

  static Future<ApiResult> getPayoutHistory() =>
      get('payouts.php', params: {'action': 'history'});

  // ── REVIEWS ──────────────────────────────────────────────

  static Future<ApiResult> getMyReviews() =>
      get('reviews.php', params: {'action': 'provider'});

  // ── CACHED PROVIDER DATA ─────────────────────────────────

  static Future<Map<String, dynamic>?> getCachedProvider() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('provider_data');
    if (s == null) return null;
    try {
      final d = jsonDecode(s);
      return d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> cacheProvider(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('provider_data', jsonEncode(data));
  }
}
