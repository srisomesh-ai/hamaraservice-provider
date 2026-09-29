import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/provider_api_service.dart';
import '../utils/theme.dart';

/// Weekly availability schedule editor.
/// Loads `schedule` from providers.php?action=get and saves it via
/// providers.php?action=schedule as
/// {mon:{on:true,from:"09:00",to:"18:00"}, ... sun}.
class ScheduleScreen extends StatefulWidget {
  final String providerId;
  const ScheduleScreen({super.key, required this.providerId});
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  static const _days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  static const _labels = {
    'mon': 'Monday', 'tue': 'Tuesday', 'wed': 'Wednesday', 'thu': 'Thursday',
    'fri': 'Friday', 'sat': 'Saturday', 'sun': 'Sunday',
  };

  bool _loading = true;
  bool _saving = false;
  final Map<String, Map<String, dynamic>> _schedule = {
    for (final d in _days) d: {'on': d != 'sun', 'from': '09:00', 'to': '18:00'},
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await ProviderApiService.getProfile(widget.providerId);
      dynamic raw = profile?['schedule'];
      if (raw is String && raw.isNotEmpty) {
        try { raw = jsonDecode(raw); } catch (_) { raw = null; }
      }
      if (raw is Map) {
        for (final d in _days) {
          final v = raw[d];
          if (v is Map) {
            final on = v['on'];
            _schedule[d] = {
              'on': on == true || on == 1 || on == '1' || on == 'true',
              'from': _validTime(v['from']) ?? '09:00',
              'to': _validTime(v['to']) ?? '18:00',
            };
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String? _validTime(dynamic v) {
    final s = (v ?? '').toString();
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s);
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  TimeOfDay _parse(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.tryParse(p[0]) ?? 9, minute: int.tryParse(p.length > 1 ? p[1] : '0') ?? 0);
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime(String day, String key) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parse(_schedule[day]![key].toString()),
    );
    if (picked != null && mounted) {
      setState(() => _schedule[day]![key] = _fmt(picked));
    }
  }

  Future<void> _save() async {
    for (final d in _days) {
      final e = _schedule[d]!;
      if (e['on'] == true && e['from'].toString().compareTo(e['to'].toString()) >= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_labels[d]}: end time must be after start time'),
          backgroundColor: AppColors.red));
        return;
      }
    }
    setState(() => _saving = true);
    bool ok = false;
    try {
      ok = await ProviderApiService.saveSchedule({
        for (final d in _days) d: Map<String, dynamic>.from(_schedule[d]!),
      });
    } catch (_) {
      ProviderApiService.lastError = 'Network error. Please try again.';
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Availability schedule saved'), backgroundColor: AppColors.green));
      Navigator.pop(context, true);
    } else {
      final msg = ProviderApiService.lastError;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg.isNotEmpty ? msg : 'Could not save schedule. Please try again.'),
        backgroundColor: AppColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Availability Schedule'), backgroundColor: AppColors.teal),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(12)),
                  child: const Row(children: [
                    Icon(Icons.info_outline_rounded, color: AppColors.teal, size: 16),
                    SizedBox(width: 8),
                    Expanded(child: Text('Set the days and hours you usually work. '
                        'You still need to go Online to receive job alerts.',
                        style: TextStyle(fontSize: 12, color: AppColors.teal))),
                  ]),
                ),
                const SizedBox(height: 12),
                ..._days.map(_dayRow),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    child: _saving
                        ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
                        : const Text('Save Schedule', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _dayRow(String d) {
    final e = _schedule[d]!;
    final on = e['on'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
      child: Row(children: [
        SizedBox(
          width: 96,
          child: Text(_labels[d]!,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              color: on ? AppColors.ink : AppColors.muted)),
        ),
        Expanded(
          child: on
              ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _timeChip(d, 'from'),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('–', style: TextStyle(color: AppColors.muted))),
                  _timeChip(d, 'to'),
                ])
              : const Center(child: Text('Off', style: TextStyle(fontSize: 13, color: AppColors.muted))),
        ),
        Switch(
          value: on,
          activeColor: AppColors.green,
          onChanged: (v) => setState(() => e['on'] = v),
        ),
      ]),
    );
  }

  Widget _timeChip(String d, String key) {
    return InkWell(
      onTap: () => _pickTime(d, key),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.tealSoft,
          borderRadius: BorderRadius.circular(8)),
        child: Text(_schedule[d]![key].toString(),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.teal)),
      ),
    );
  }
}
