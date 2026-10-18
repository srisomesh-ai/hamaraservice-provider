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
