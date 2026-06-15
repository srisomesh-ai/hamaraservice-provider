import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/theme.dart';
import '../services/hs_catalog.dart';

// ═══════════════════════════════════════════════════════════════
// Provider Services Screen
// Provider selects which services they can offer
// Same HTML card style as customer and admin
// ═══════════════════════════════════════════════════════════════

class ServicesScreen extends StatefulWidget {
  final String providerId;
  const ServicesScreen({super.key, required this.providerId});
  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  Set<String> _selected = {};
  bool _loading = true;
  bool _saving = false;
  String _cat = 'All';

  final _cats = [
    'All', 'Home Cleaning', 'Home Services', 'Vehicle Care',
    'Cooking', 'Beauty & Wellness', 'Health Services',
    'Care Services', 'Outdoor', 'Security', 'Pest Control',
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('providers/${widget.providerId}/services').get();
      if (snap.exists) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        _selected = data.entries
            .where((e) => e.value == true)
            .map((e) => e.key)
            .toSet();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      final Map<String, dynamic> updates = {};
      for (final svc in HSCatalog.services) {
        updates[svc.id] = _selected.contains(svc.id);
      }
      await FirebaseDatabase.instance
          .ref('providers/${widget.providerId}/services')
          .update(updates);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_selected.length} services saved ✅'),
          backgroundColor: AppColors.green));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: AppColors.red));
    }
    if (mounted) setState(() => _saving = false);
  }

  List<HSService> get _list {
    if (_cat == 'All') return HSCatalog.services;
    return HSCatalog.services.where((s) => s.cat == _cat).toList();
  }

  void _toggle(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.contains(id)) _selected.remove(id);
      else _selected.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: AppColors.teal)));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(children: [
        // ── Hero — same dark teal gradient as HTML ─────────────
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF071e25), Color(0xFF0d3541), AppColors.teal],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight)),
          padding: EdgeInsets.fromLTRB(
            16, MediaQuery.of(context).padding.top + 12, 16, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Back + Save
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.arrow_back_rounded,
                    color: Colors.white, size: 20))),
              const SizedBox(width: 12),
              const Expanded(child: Text('My Services',
                style: TextStyle(fontFamily: 'Sora', fontSize: 18,
                  fontWeight: FontWeight.w800, color: Colors.white))),
              GestureDetector(
                onTap: _saving ? null : _save,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    borderRadius: BorderRadius.circular(100)),
                  child: _saving
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                    : const Text('SAVE', style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13)))),
            ]),
            const SizedBox(height: 14),
            // Counter row
            Row(children: [
              // Selected count pill
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2))),
                child: Text('${_selected.length} selected',
                  style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700, color: Colors.white))),
              const SizedBox(width: 10),
              const Expanded(child: Text(
                'Tap cards to offer those services',
                style: TextStyle(fontSize: 11, color: Colors.white60))),
              // Select all toggle
              GestureDetector(
                onTap: () => setState(() {
                  if (_selected.length == HSCatalog.services.length) {
                    _selected.clear();
                  } else {
                    _selected = HSCatalog.services
                        .map((s) => s.id).toSet();
                  }
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2))),
                  child: Text(
                    _selected.length == HSCatalog.services.length
                      ? 'Deselect All'
                      : 'Select All',
                    style: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)))),
            ]),
          ])),

        // ── Category filter pills ──────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: _cats.map((c) {
              final sel = _cat == c;
              return GestureDetector(
                onTap: () => setState(() => _cat = c),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.teal : AppColors.bg,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: sel ? AppColors.teal : AppColors.line)),
                  child: Text(c, style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : AppColors.muted))));
            }).toList()))),

        // ── Service cards list ─────────────────────────────────
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
          itemCount: _list.length,
          itemBuilder: (_, i) => _buildCard(_list[i]))),
      ]),

      // ── Bottom Save button ─────────────────────────────────────
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        color: Colors.white,
        child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.teal,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14))),
          child: _saving
            ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2))
            : Text(
                'Save ${_selected.length} Services',
                style: const TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w700, color: Colors.white)))));
  }

  // ── Service card — same HTML style ───────────────────────────
  Widget _buildCard(HSService svc) {
    final sel = _selected.contains(svc.id);
    return GestureDetector(
      onTap: () => _toggle(svc.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: sel ? AppColors.tealSoft : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: sel ? AppColors.teal : AppColors.line,
            width: sel ? 2 : 1.5),
          boxShadow: sel
            ? [BoxShadow(color: AppColors.teal.withOpacity(0.15),
                blurRadius: 10, offset: const Offset(0,3))]
            : [BoxShadow(color: Colors.black.withOpacity(0.04),
                blurRadius: 6)]),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            // Icon box
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 54, height: 54,
              decoration: BoxDecoration(
                color: sel
                  ? AppColors.teal.withOpacity(0.15)
                  : AppColors.bg,
                borderRadius: BorderRadius.circular(16)),
              child: Center(child: Text(svc.icon,
                style: const TextStyle(fontSize: 28)))),
            const SizedBox(width: 14),
            // Name + category
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text(svc.name, style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800,
                color: sel ? AppColors.teal : AppColors.ink)),
              const SizedBox(height: 3),
              Text(svc.cat, style: const TextStyle(
                fontSize: 11, color: AppColors.muted)),
            ])),
            // Check circle
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 26, height: 26,
              decoration: BoxDecoration(
                color: sel ? AppColors.teal : Colors.transparent,
                border: Border.all(
                  color: sel ? AppColors.teal : AppColors.line,
                  width: 2),
                shape: BoxShape.circle),
              child: sel
                ? const Icon(Icons.check_rounded,
                    color: Colors.white, size: 15)
                : null),
          ]))));
  }
}
