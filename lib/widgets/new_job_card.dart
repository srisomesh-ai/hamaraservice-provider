import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/hs_catalog.dart';
import '../utils/parse.dart';
import '../utils/theme.dart';
import 'ui.dart';

/// Emoji icon for a booking (row value, else the catalogue icon).
String jobIcon(Map<String, dynamic> b) {
  final i = str(b['svc_icon']);
  if (i.isNotEmpty) return i;
  return HSCatalog.getById(str(b['svc_id']))?.icon ?? '🔧';
}

/// "Gajuwaka, Visakhapatnam · 2.4 km"
String jobPlace(Map<String, dynamic> b) {
  final place = str(b['address'], str(b['city']));
  final d = toDoubleOrNull(b['distance_km']);
  final km = d == null ? '' : '${d % 1 == 0 ? d.toInt() : d.toStringAsFixed(1)} km';
  if (place.isEmpty) return km.isEmpty ? '' : '$km away';
  return km.isEmpty ? place : '$place · $km';
}

/// New-job alert, shown as a bottom sheet over the app (same content as the
/// website popup): countdown, service, the customer's job answers as chips,
/// notes, area + distance, slot day/time, "Your Price (₹)" prefilled with the
/// provider's saved price, Accept and Skip.
class NewJobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final int secondsLeft;
  final int totalSeconds;
  final int savedPrice;
  final TextEditingController priceController;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onSkip;

  const NewJobCard({
    super.key,
    required this.job,
    required this.secondsLeft,
    this.totalSeconds = 30,
    required this.savedPrice,
    required this.priceController,
    required this.busy,
    required this.onAccept,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final summary = parseSummary(job['summary']);
    final notes = str(job['notes']);
    final place = jobPlace(job);
    final slot = str(job['slot_time']).isNotEmpty
        ? '${slotDayLabel(job['slot_date'])}${str(job['slot_time'])}'
        : '';
    final urgent = secondsLeft <= 10;
    return Material(
      color: Colors.white,
      elevation: 12,
      shadowColor: Colors.black,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: const Color(0xFFC5D3D7), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(99)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.notifications_active_rounded, size: 16, color: Colors.white),
                  SizedBox(width: 6),
                  Text('NEW JOB',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                ]),
              ),
              const Spacer(),
              SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(
                  value: totalSeconds == 0 ? 0 : secondsLeft / totalSeconds,
                  strokeWidth: 3,
                  backgroundColor: const Color(0xFFE3EAEC),
                  color: urgent ? AppColors.red : AppColors.teal,
                ),
              ),
              const SizedBox(width: 8),
              Text('Respond in ${secondsLeft}s',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: urgent ? AppColors.red : AppColors.ink2)),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                width: 56, height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(16)),
                child: Text(jobIcon(job), style: const TextStyle(fontSize: 28)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(str(job['svc_name'], 'Service'),
                      style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  if (slot.isNotEmpty)
                    Text(slot, style: t.bodyMedium?.copyWith(color: AppColors.muted)),
                ]),
              ),
            ]),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 12),
              SummaryChips(summary),
            ],
            const SizedBox(height: 10),
            if (notes.isNotEmpty) DetailLine(Icons.sticky_note_2_outlined, notes),
            if (place.isNotEmpty) DetailLine(Icons.place_outlined, place),
            const SizedBox(height: 14),
            TextField(
              controller: priceController,
              enabled: !busy,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                labelText: 'Your Price (₹)',
                prefixText: '₹ ',
                helperText: savedPrice > 0
                    ? 'Your saved price — edit if needed'
                    : 'Set your price for this job',
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onSkip,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.red,
                    side: BorderSide(color: AppColors.red.withOpacity(0.5)),
                  ),
                  child: const Text('Skip'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: priceController,
                  builder: (_, v, __) {
                    final p = int.tryParse(v.text.trim()) ?? 0;
                    return BigButton(
                      p > 0 ? 'Accept at ₹$p' : 'Accept & Quote',
                      icon: Icons.check_rounded,
                      color: AppColors.green,
                      busy: busy,
                      onPressed: onAccept,
                    );
                  },
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
