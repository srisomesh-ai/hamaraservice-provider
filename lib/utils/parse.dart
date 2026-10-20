import 'dart:convert';

// Defensive parsers for MySQL rows: DECIMAL columns arrive as strings,
// integer columns may arrive as int or string, and anything may be null.

double? toDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

double toDouble(dynamic v, [double fallback = 0]) =>
    toDoubleOrNull(v) ?? fallback;

int toInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.round();
  final s = '$v';
  return int.tryParse(s) ?? double.tryParse(s)?.round() ?? fallback;
}

String str(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final s = '$v';
  return s.isEmpty ? fallback : s;
}

bool toBool(dynamic v) =>
    v == true || v == 1 || v == '1' || v == 'true';

/// Formats a 'YYYY-MM-DD' or 'YYYY-MM-DD HH:MM:SS' value as e.g. "18 Oct 2026".
/// Never throws; returns the raw text (or '') when it cannot be parsed.
String fmtDate(dynamic v) {
  final s = str(v).trim();
  if (s.isEmpty) return '';
  final d = DateTime.tryParse(s.replaceFirst(' ', 'T'));
  if (d == null) return s;
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
             'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

/// Parses a MySQL 'YYYY-MM-DD HH:MM:SS' timestamp. Returns null on failure.
DateTime? parseDateTime(dynamic v) {
  final s = str(v).trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s.replaceFirst(' ', 'T'));
}

/// Booking `summary` is a JSON string (array of strings or objects); may also
/// already be a List. Returns readable lines.
List<String> parseSummary(dynamic v) {
  dynamic data = v;
  if (data is String) {
    final t = data.trim();
    if (t.isEmpty) return const [];
    try {
      data = jsonDecode(t);
    } catch (_) {
      return [t];
    }
  }
  if (data is List) {
    return data.map((e) {
      if (e is Map) {
        final label = str(e['label'] ?? e['name'] ?? e['title'] ?? e['option']);
        final val = str(e['value'] ?? e['choice'] ?? e['qty']);
        if (label.isNotEmpty && val.isNotEmpty) return '$label: $val';
        return label.isNotEmpty ? label : val;
      }
      final s = '$e';
      final parts = s.split(' > ');
      return parts.length > 1 ? parts.sublist(1).join(' > ') : s;
    }).where((s) => s.isNotEmpty).toList();
  }
  if (data is Map) {
    return data.entries.map((e) => '${e.key}: ${e.value}').toList();
  }
  return const [];
}

/// Photo paths from upload.php are site-relative ("/uploads/providers/x.jpg").
String photoUrl(dynamic v) {
  final s = str(v);
  if (s.isEmpty) return '';
  if (s.startsWith('http')) return s;
  return 'https://hamaraservice.com${s.startsWith('/') ? '' : '/'}$s';
}

// ── Booking day / IST times ─────────────────────────────────────────────

const _kWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _kMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Current wall-clock time in India (IST, UTC+05:30), as a UTC-less DateTime.
DateTime nowIst() =>
    DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Booking `slot_date` ('YYYY-MM-DD') → "Today · ", "Tomorrow · " or
/// "Wed 21 Oct · ". Empty when there is no date.
String slotDayLabel(dynamic slotDate) {
  final s = str(slotDate).trim();
  if (s.isEmpty) return '';
  final day = s.length >= 10 ? s.substring(0, 10) : s;
  final today = nowIst();
  if (day == _ymd(today)) return 'Today · ';
  if (day == _ymd(today.add(const Duration(days: 1)))) return 'Tomorrow · ';
  final d = DateTime.tryParse(day);
  if (d == null) return '$s · ';
  return '${_kWeekdays[d.weekday - 1]} ${d.day} ${_kMonths[d.month - 1]} · ';
}

/// "Today · Morning (8 AM – 12 PM) · 9 AM" — slot day followed by slot_time.
String slotWhen(dynamic slotDate, dynamic slotTime) {
  final day = slotDayLabel(slotDate);
  final time = str(slotTime).trim();
  if (time.isEmpty) {
    return day.endsWith(' · ') ? day.substring(0, day.length - 3) : day;
  }
  return '$day$time';
}

/// Server timestamps are IST wall-clock "YYYY-MM-DD HH:MM:SS" (+05:30).
/// Returns the exact instant (UTC), or null.
DateTime? parseIst(dynamic v) {
  final s = str(v).trim();
  if (s.isEmpty) return null;
  final base = s.replaceFirst(' ', 'T');
  final hasZone = RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(base);
  return DateTime.tryParse(hasZone ? base : '$base+05:30');
}

/// IST server time → "9:05 AM" (today) or "21 Oct, 9:05 AM".
String istTime(dynamic v) {
  final utc = parseIst(v);
  if (utc == null) return str(v);
  final d = utc.toUtc().add(const Duration(hours: 5, minutes: 30));
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final t = '$h12:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  return _ymd(d) == _ymd(nowIst()) ? t : '${d.day} ${_kMonths[d.month - 1]}, $t';
}

/// Duration between two IST server times → "1 h 25 min" / "40 min" ('' if invalid).
String istDuration(dynamic from, dynamic to) {
  final a = parseIst(from), b = parseIst(to);
  if (a == null || b == null) return '';
  final secs = b.difference(a).inSeconds;
  if (secs < 0) return '';
  final h = secs ~/ 3600;
  final m = ((secs % 3600) / 60).round();
  return '${h > 0 ? '$h h ' : ''}$m min';
}
