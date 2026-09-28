// Safe parsing helpers for values coming back from the PHP/MySQL API.
// MySQL DECIMAL columns (lat, lng, earnings...) are returned as JSON strings,
// so never cast API values with `as num` directly.

double asDouble(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim()) ?? fallback;
}

int asInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final s = v.toString().trim();
  final i = int.tryParse(s);
  if (i != null) return i;
  final d = double.tryParse(s);
  return d != null ? d.toInt() : fallback;
}

/// First 10 chars of a date/datetime string ("YYYY-MM-DD"), safe on short input.
String dateOnly(dynamic v) {
  final s = (v ?? '').toString();
  return s.length > 10 ? s.substring(0, 10) : s;
}

/// Upper-case first character of a name, or [fallback] when empty.
String initialOf(dynamic v, [String fallback = 'P']) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? fallback : s[0].toUpperCase();
}

/// Extract a service id from any of the shapes used across the app/API:
/// a plain String id, or a Map with svc_id / svcId / serviceId / id.
String serviceIdOf(dynamic s) {
  if (s == null) return '';
  if (s is Map) {
    final v = s['svc_id'] ?? s['svcId'] ?? s['serviceId'] ?? s['id'];
    return v?.toString() ?? '';
  }
  return s.toString();
}

/// Set of enabled service ids from a provider's `services` field
/// (List of ids / List of maps from provider_services / Map {id: true}).
Set<String> serviceIdsOf(dynamic raw) {
  final ids = <String>{};
  if (raw is Map) {
    raw.forEach((k, v) {
      final enabled = v == true || v == 1 || v == '1' ||
          (v is Map && (v['enabled'] == true || v['enabled'] == 1 || v['enabled'] == '1'));
      if (enabled) ids.add(k.toString());
    });
  } else if (raw is List) {
    for (final s in raw) {
      if (s is Map && s.containsKey('enabled')) {
        final e = s['enabled'];
        if (!(e == true || e == 1 || e == '1')) continue;
      }
      final id = serviceIdOf(s);
      if (id.isNotEmpty) ids.add(id);
    }
  }
  return ids;
}

/// Service id of a booking (bookings table uses svc_id).
String bookingServiceIdOf(Map b) =>
    (b['svc_id'] ?? b['svcId'] ?? b['serviceId'] ?? '').toString();
