import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/theme.dart';
import '../services/hs_catalog.dart';

class ProviderServicesScreen extends StatefulWidget {
  final String providerId;
  const ProviderServicesScreen({super.key, required this.providerId});
  @override
  State<ProviderServicesScreen> createState() => _ProviderServicesState();
}

class _ProviderServicesState extends State<ProviderServicesScreen> {
  Set<String> _myServices = {};
  bool _loading = true;
  bool _saving = false;
  String _filterCat = 'All';

  final _cats = [
    'All', 'Home Cleaning', 'Home Services', 'Vehicle Care',
    'Cooking', 'Beauty & Wellness', 'Health Services',
    'Care Services', 'Outdoor', 'Security', 'Pest Control',
  ];

  @override
  void initState() {
    super.initState();
    _loadMyServices();
  }

  Future<void> _loadMyServices() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('providers/${widget.providerId}/services')
          .get();
      if (snap.exists) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        _myServices = data.entries
            .where((e) => e.value == true)
            .map((e) => e.key)
            .toSet();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle(String svcId) async {
    HapticFeedback.selectionClick();
    setState(() {
      if (_myServices.contains(svcId)) {
        _myServices.remove(svcId);
      } else {
        _myServices.add(svcId);
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> updates = {};
      for (final svc in HSCatalog.services) {
        updates[svc.id] = _myServices.contains(svc.id);
      }
      await FirebaseDatabase.instance
          .ref('providers/${widget.providerId}/services')
          .update(updates);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Services updated successfully!'),
          backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  List<HSService> get _filtered {
    if (_filterCat == 'All') return HSCatalog.services;
    return HSCatalog.services.where((s) => s.cat == _filterCat).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(
      body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('My Services'),
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('SAVE', style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
        ]),
      body: Column(children: [
        // Summary bar
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.tealSoft,
                borderRadius: BorderRadius.circular(20)),
              child: Text('${_myServices.length} selected',
                style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.teal))),
            const SizedBox(width: 10),
            const Text('Select all services you can provide',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ])),
        // Category filter
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: _cats.map((c) {
              final sel = _filterCat == c;
              return GestureDetector(
                onTap: () => setState(() => _filterCat = c),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.teal : AppColors.bg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? AppColors.teal : AppColors.line)),
                  child: Text(c, style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : AppColors.muted))));
            }).toList()))),
        // Service list
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _filtered.length,
          itemBuilder: (_, i) {
            final svc = _filtered[i];
            final selected = _myServices.contains(svc.id);
            return GestureDetector(
              onTap: () => _toggle(svc.id),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: selected ? AppColors.tealSoft : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? AppColors.teal : AppColors.line,
                    width: selected ? 2 : 1)),
                child: Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: selected
                        ? AppColors.teal.withOpacity(0.15)
                        : AppColors.bg,
                      borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Text(svc.icon,
                      style: const TextStyle(fontSize: 24)))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(svc.name, style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: selected ? AppColors.teal : AppColors.ink)),
                      Text(svc.cat, style: const TextStyle(
                        fontSize: 11, color: AppColors.muted)),
                    ])),
                  if (selected)
                    const Icon(Icons.check_circle_rounded,
                      color: AppColors.teal, size: 24)
                  else
                    const Icon(Icons.radio_button_unchecked_rounded,
                      color: AppColors.muted, size: 24),
                ])));
          })),
        // Save button at bottom
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          color: Colors.white,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              backgroundColor: AppColors.teal,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14))),
            child: _saving
              ? const CircularProgressIndicator(color: Colors.white)
              : Text(
                  'Save ${_myServices.length} Services',
                  style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)))),
      ]));
  }
}
