import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/theme.dart';
import '../services/hs_catalog.dart';

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
  String _filterCat = 'All';

  final _cats = ['All','Home Cleaning','Home Services','Vehicle Care',
    'Cooking','Beauty & Wellness','Health Services',
    'Care Services','Outdoor','Security','Pest Control'];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('providers/${widget.providerId}/services').get();
      if (snap.exists) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        _selected = data.entries.where((e) => e.value == true)
            .map((e) => e.key).toSet();
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
        content: Text('Error: $e'), backgroundColor: AppColors.red));
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
      body: Center(child: CircularProgressIndicator(color: AppColors.teal)));
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
        // Counter bar
        Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(16,10,16,0),
          child: Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(100)),
              child: Text('${_selected.length} selected',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.teal))),
            const SizedBox(width: 10),
            const Expanded(child: Text('Tap to toggle services you can provide',
              style: TextStyle(fontSize: 12, color: AppColors.muted))),
            TextButton(
              onPressed: () => setState(() {
                if (_selected.length == HSCatalog.services.length) {
                  _selected.clear();
                } else {
                  _selected = HSCatalog.services.map((s) => s.id).toSet();
                }
              }),
              child: Text(
                _selected.length == HSCatalog.services.length ? 'Deselect All' : 'Select All',
                style: const TextStyle(fontSize: 12, color: AppColors.teal, fontWeight: FontWeight.w700))),
          ])),
        // Category filter
        Container(color: Colors.white, padding: const EdgeInsets.symmetric(vertical: 8),
          child: SingleChildScrollView(scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: _cats.map((c) {
              final sel = _filterCat == c;
              return GestureDetector(
                onTap: () => setState(() => _filterCat = c),
                child: Container(margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.teal : AppColors.bg,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: sel ? AppColors.teal : AppColors.line)),
                  child: Text(c, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : AppColors.muted))));
            }).toList()))),
        // Service list
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12,12,12,100),
          itemCount: _filtered.length,
          itemBuilder: (_, i) => _buildCard(_filtered[i]))),
      ]),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16,12,16,28),
        color: Colors.white,
        child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.teal,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: _saving
            ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text('Save ${_selected.length} Services',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)))));
  }

  Widget _buildCard(HSService svc) {
    final isSelected = _selected.contains(svc.id);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          if (isSelected) _selected.remove(svc.id);
          else _selected.add(svc.id);
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.tealSoft : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.teal : AppColors.line,
            width: isSelected ? 2 : 1.5),
          boxShadow: isSelected
            ? [BoxShadow(color: AppColors.teal.withOpacity(0.15), blurRadius: 10)]
            : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: isSelected ? AppColors.teal.withOpacity(0.15) : AppColors.bg,
              borderRadius: BorderRadius.circular(14)),
            child: Center(child: Text(svc.icon, style: const TextStyle(fontSize: 26)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(svc.name, style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700,
              color: isSelected ? AppColors.teal : AppColors.ink)),
            Text(svc.cat, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ])),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 26, height: 26,
            decoration: BoxDecoration(
              color: isSelected ? AppColors.teal : Colors.transparent,
              border: Border.all(
                color: isSelected ? AppColors.teal : AppColors.line, width: 2),
              shape: BoxShape.circle),
            child: isSelected
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 15)
              : null),
        ])));
  }
}
