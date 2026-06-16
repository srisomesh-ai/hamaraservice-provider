import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/theme.dart';
import '../services/hs_catalog.dart';

// ═══════════════════════════════════════════════════════════════
// Provider Services Screen
// Part 1: List — provider toggles which services they offer
// Part 2: Detail — tapping a service shows full detail (read-only)
//         Same design as customer screen — tasks + BHK cards
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
        content: Text('Error: $e'),
        backgroundColor: AppColors.red));
    }
    if (mounted) setState(() => _saving = false);
  }

  List<HSService> get _list => _cat == 'All'
      ? HSCatalog.services
      : HSCatalog.services.where((s) => s.cat == _cat).toList();

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(
      body: Center(child: CircularProgressIndicator(
        color: AppColors.teal)));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(children: [
        // ── Hero ────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF071e25), Color(0xFF0d3541), AppColors.teal],
              begin: Alignment.topLeft, end: Alignment.bottomRight)),
          padding: EdgeInsets.fromLTRB(
            16, MediaQuery.of(context).padding.top + 12, 16, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                    horizontal: 18, vertical: 8),
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
            Row(children: [
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
                    fontWeight: FontWeight.w700,
                    color: Colors.white))),
              const SizedBox(width: 10),
              const Expanded(child: Text(
                'Toggle to offer · Tap to view details',
                style: TextStyle(fontSize: 11,
                  color: Colors.white60))),
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
                        ? 'Deselect All' : 'Select All',
                    style: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)))),
            ]),
          ])),

        // ── Category filter ──────────────────────────────────
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

        // ── Service list ─────────────────────────────────────
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
          itemCount: _list.length,
          itemBuilder: (_, i) => _buildCard(_list[i]))),
      ]),
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
            : Text('Save ${_selected.length} Services',
                style: const TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)))));
  }

  Widget _buildCard(HSService svc) {
    final sel = _selected.contains(svc.id);
    return GestureDetector(
      // Short tap = view details
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => _ServiceDetailScreen(svcId: svc.id))),
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
            // Icon
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
            // Name + cat + hint
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text(svc.name, style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800,
                color: sel ? AppColors.teal : AppColors.ink)),
              const SizedBox(height: 2),
              Text(svc.cat, style: const TextStyle(
                fontSize: 11, color: AppColors.muted)),
              const SizedBox(height: 4),
              const Text('Tap to view full details →',
                style: TextStyle(fontSize: 10,
                  color: AppColors.teal,
                  fontWeight: FontWeight.w500)),
            ])),
            // Toggle button (offer/not offer)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  if (sel) _selected.remove(svc.id);
                  else _selected.add(svc.id);
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? AppColors.teal : AppColors.bg,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: sel ? AppColors.teal : AppColors.line)),
                child: Text(sel ? '✓ Offering' : '+ Offer',
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : AppColors.muted)))),
          ]))));
  }
}

// ═══════════════════════════════════════════════════════════════
// Service Detail Screen — same as customer but READ-ONLY
// Shows tasks + BHK cards + prices from Firebase
// No booking button — provider just sees what customer sees
// ═══════════════════════════════════════════════════════════════

class _ServiceDetailScreen extends StatefulWidget {
  final String svcId;
  const _ServiceDetailScreen({required this.svcId});
  @override
  State<_ServiceDetailScreen> createState() => _ServiceDetailState();
}

class _ServiceDetailState extends State<_ServiceDetailScreen> {
  HSService? _svc;
  Map<String, int> _prices = {};
  Set<String> _selectedTasks = {};
  Map<String, String> _selectedBhk = {};
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    _svc = HSCatalog.getById(widget.svcId);
    if (_svc == null) { setState(() => _loading = false); return; }
    try {
      final snap = await FirebaseDatabase.instance
          .ref('hs_service_prices/${widget.svcId}/prices').get();
      if (snap.exists) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        _prices = data.map((k, v) =>
          MapEntry(k, (v is int) ? v : (v is double) ? v.toInt() : 0));
      }
    } catch (_) {}
    // Auto-select first bhk for visit-only
    if (_isVisitOnly) {
      final g = _svc!.groups.first;
      if (g.items.isNotEmpty) _selectedBhk[g.key] = g.items.first.key;
    }
    if (mounted) setState(() => _loading = false);
  }

  int _p(String gk, String ok) => _prices['${gk}_$ok'] ?? 0;

  bool get _isVisitOnly =>
      _svc != null &&
      _svc!.groups.length == 1 &&
      _svc!.groups.first.style == 'bhk' &&
      _svc!.groups.first.showOn == null;

  int get _total {
    if (_svc == null) return 0;
    int t = 0;
    for (final g in _svc!.groups) {
      if (g.style == 'task' || g.style == 'info') continue;
      final show = g.showOn == null ||
          _selectedTasks.contains('task_${g.showOn}');
      if (!show) continue;
      final sel = _selectedBhk[g.key] ?? '';
      if (sel.isNotEmpty) t += _p(g.key, sel);
    }
    return t;
  }

  void _toggleTask(String taskKey) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedTasks.contains(taskKey)) {
        _selectedTasks.remove(taskKey);
        for (final g in _svc!.groups) {
          if ('task_${g.showOn}' == taskKey) _selectedBhk.remove(g.key);
        }
      } else {
        _selectedTasks.add(taskKey);
        for (final g in _svc!.groups) {
          if ('task_${g.showOn}' == taskKey && g.items.isNotEmpty) {
            _selectedBhk[g.key] = g.items.first.key;
          }
        }
      }
    });
  }

  void _selectBhk(String gk, String ok) {
    HapticFeedback.selectionClick();
    setState(() => _selectedBhk[gk] = ok);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(child: CircularProgressIndicator(
        color: AppColors.teal)));
    if (_svc == null) return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.teal,
        foregroundColor: Colors.white, title: const Text('Service')),
      body: const Center(child: Text('Not found')));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(slivers: [
          SliverToBoxAdapter(child: _buildHero()),
          SliverToBoxAdapter(child: _buildTrustBar()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
            sliver: SliverList(delegate: SliverChildListDelegate([
              if (_isVisitOnly)
                _buildVisitCard()
              else
                _buildTasksBody(),
            ]))),
        ]),
        Positioned(bottom: 0, left: 0, right: 0,
          child: _buildBottomBar()),
      ]));
  }

  Widget _buildHero() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF071e25), Color(0xFF0d3541), AppColors.teal],
        begin: Alignment.topLeft, end: Alignment.bottomRight)),
    padding: EdgeInsets.fromLTRB(
      20, MediaQuery.of(context).padding.top + 16, 20, 28),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            border: Border.all(
              color: Colors.white.withOpacity(0.15)),
            borderRadius: BorderRadius.circular(100)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 5, height: 5,
              decoration: const BoxDecoration(
                color: AppColors.green, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(_svc!.cat, style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: Colors.white)),
          ])),
        const Spacer(),
        // Provider view badge
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.brand.withOpacity(0.9),
            borderRadius: BorderRadius.circular(100)),
          child: const Text('Provider View',
            style: TextStyle(fontSize: 10,
              fontWeight: FontWeight.w700, color: Colors.white))),
      ]),
      const SizedBox(height: 16),
      Text(_svc!.icon, style: const TextStyle(fontSize: 48)),
      const SizedBox(height: 10),
      Text(_svc!.name, style: const TextStyle(
        fontFamily: 'Sora', fontSize: 26,
        fontWeight: FontWeight.w800, color: Colors.white)),
      const SizedBox(height: 6),
      Text('Customer-facing service details & pricing',
        style: TextStyle(fontSize: 13,
          color: Colors.white.withOpacity(0.6))),
      const SizedBox(height: 14),
      Wrap(spacing: 6, runSpacing: 6, children: [
        _heroTag('⭐ 4.8 Rated'),
        _heroTag('✅ Verified'),
        _heroTag('🛡️ Insured'),
        _heroTag('💳 Pay after service'),
      ]),
    ]));

  Widget _heroTag(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.08),
      border: Border.all(color: Colors.white.withOpacity(0.12)),
      borderRadius: BorderRadius.circular(100)),
    child: Text(t, style: TextStyle(
      fontSize: 11,
      color: Colors.white.withOpacity(0.8),
      fontWeight: FontWeight.w500)));

  Widget _buildTrustBar() => Container(
    color: Colors.white,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _trustItem('👥', 'Verified Pros'),
        _trustItem('⚡', 'Book in 60s'),
        _trustItem('🔒', 'Background checked'),
        _trustItem('💳', 'Pay after service'),
      ])));

  Widget _trustItem(String ico, String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
    decoration: const BoxDecoration(
      border: Border(right: BorderSide(color: AppColors.line))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(ico, style: const TextStyle(fontSize: 14)),
      const SizedBox(width: 6),
      Text(t, style: const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink2)),
    ]));

  Widget _buildVisitCard() {
    final g = _svc!.groups.first;
    final selKey = _selectedBhk[g.key] ??
        (g.items.isNotEmpty ? g.items.first.key : '');
    final price = selKey.isNotEmpty ? _p(g.key, selKey) : 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.teal, width: 2),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
          color: AppColors.teal.withOpacity(0.15),
          blurRadius: 20, offset: const Offset(0,4))]),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.teal, AppColors.teal2]),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(18))),
          child: Row(children: [
            Container(width: 52, height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14)),
              child: Center(child: Text(_svc!.icon,
                style: const TextStyle(fontSize: 28)))),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text(_svc!.name, style: const TextStyle(
                fontFamily: 'Sora', fontSize: 16,
                fontWeight: FontWeight.w800, color: Colors.white)),
              Text('Visit / Call-out fee', style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.7))),
            ]),
          ])),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              const Text('VISIT FEE', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: AppColors.muted, letterSpacing: 0.5)),
              Text(price > 0 ? '₹$price' : '₹0',
                style: const TextStyle(
                  fontFamily: 'Sora', fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: AppColors.teal)),
              const Text('Customer pays this visit fee',
                style: TextStyle(fontSize: 11,
                  color: AppColors.muted)),
            ]),
          ])),
      ]));
  }

  Widget _buildTasksBody() {
    final taskGroup = _svc!.groups
        .where((g) => g.style == 'task').firstOrNull;
    if (taskGroup == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: _svc!.groups.map((g) {
          if (g.style == 'bhk') return _bhkSection(g);
          if (g.style == 'info') return _infoBox(g.info ?? g.title);
          return const SizedBox.shrink();
        }).toList());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Tasks', style: TextStyle(
          fontFamily: 'Sora', fontSize: 15,
          fontWeight: FontWeight.w800, color: AppColors.ink)),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFdbeafe),
            borderRadius: BorderRadius.circular(100)),
          child: const Text('Multi-select preview',
            style: TextStyle(fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1d4ed8)))),
      ]),
      const SizedBox(height: 12),
      ...taskGroup.items.map((opt) {
        final taskKey = 'task_${opt.key}';
        final isSel = _selectedTasks.contains(taskKey);
        final subGroup = _svc!.groups
            .where((g) => g.showOn == opt.key).firstOrNull;
        return Column(children: [
          _taskCard(opt, taskKey, isSel),
          if (isSel && subGroup != null) _subSection(subGroup),
        ]);
      }),
    ]);
  }

  Widget _taskCard(HSOption opt, String taskKey, bool isSel) =>
    GestureDetector(
      onTap: () => _toggleTask(taskKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSel ? AppColors.tealSoft : Colors.white,
          border: Border.all(
            color: isSel ? AppColors.teal : AppColors.line, width: 2),
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSel
            ? [BoxShadow(color: AppColors.teal.withOpacity(0.15),
                blurRadius: 12, offset: const Offset(0,4))]
            : []),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: isSel
                  ? AppColors.teal.withOpacity(0.15)
                  : AppColors.bg,
              borderRadius: BorderRadius.circular(14)),
            child: Center(child: Text(
              opt.ico.isNotEmpty ? opt.ico : '✓',
              style: const TextStyle(fontSize: 24)))),
          const SizedBox(width: 12),
          Expanded(child: Text(opt.name, style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700,
            color: isSel ? AppColors.teal : AppColors.ink))),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: isSel ? AppColors.teal : Colors.transparent,
              border: Border.all(
                color: isSel ? AppColors.teal : AppColors.line,
                width: 2),
              shape: BoxShape.circle),
            child: isSel ? const Icon(Icons.check_rounded,
              color: Colors.white, size: 14) : null),
        ])));

  Widget _subSection(HSGroup g) {
    if (g.style == 'info') {
      return Container(
        margin: const EdgeInsets.only(bottom: 6, left: 2, right: 2),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.teal, width: 2),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14,12,14,14),
          child: Row(children: [
            const Text('💡', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(child: Text(g.info ?? g.title,
              style: const TextStyle(fontSize: 12,
                color: Color(0xFF92400e), height: 1.5))),
          ])));
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 6, left: 2, right: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.teal, width: 2),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16))),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: AppColors.tealSoft,
          child: Row(children: [
            const Text('🏠', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(child: Text(g.title, style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700,
              color: AppColors.teal2))),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFdcfce7),
                borderRadius: BorderRadius.circular(100)),
              child: const Text('Select one', style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700,
                color: Color(0xFF15803d)))),
          ])),
        Padding(
          padding: const EdgeInsets.all(10),
          child: GridView.count(
            crossAxisCount: 2, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8, mainAxisSpacing: 8,
            childAspectRatio: 1.9,
            children: g.items.map((o) =>
              _bhkCard(g.key, o)).toList())),
      ]));
  }

  Widget _bhkSection(HSGroup g) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Expanded(child: Text(g.title, style: const TextStyle(
        fontFamily: 'Sora', fontSize: 14,
        fontWeight: FontWeight.w800, color: AppColors.ink))),
      Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFdcfce7),
          borderRadius: BorderRadius.circular(100)),
        child: const Text('Select one', style: TextStyle(
          fontSize: 9, fontWeight: FontWeight.w700,
          color: Color(0xFF15803d)))),
    ]),
    const SizedBox(height: 10),
    GridView.count(
      crossAxisCount: 2, shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8, mainAxisSpacing: 8,
      childAspectRatio: 1.9,
      children: g.items.map((o) => _bhkCard(g.key, o)).toList()),
    const SizedBox(height: 16),
  ]);

  Widget _bhkCard(String gk, HSOption o) {
    final isSel = _selectedBhk[gk] == o.key;
    final price = _p(gk, o.key);
    return GestureDetector(
      onTap: () => _selectBhk(gk, o.key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: isSel ? AppColors.tealSoft : AppColors.bg,
          border: Border.all(
            color: isSel ? AppColors.teal : AppColors.line,
            width: isSel ? 2 : 1.5),
          borderRadius: BorderRadius.circular(14),
          boxShadow: isSel
            ? [BoxShadow(color: AppColors.teal.withOpacity(0.18),
                blurRadius: 8)]
            : []),
        child: Column(mainAxisAlignment: MainAxisAlignment.center,
          children: [
          Text(o.name, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: isSel ? AppColors.teal2 : AppColors.ink2)),
          const SizedBox(height: 3),
          Text(price > 0 ? '₹$price' : '₹0',
            style: TextStyle(fontFamily: 'Sora', fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isSel ? AppColors.teal2 : AppColors.teal)),
          const SizedBox(height: 3),
          Container(width: 16, height: 16,
            decoration: BoxDecoration(
              color: isSel ? AppColors.teal : Colors.transparent,
              border: Border.all(
                color: isSel ? AppColors.teal : AppColors.line,
                width: 1.5),
              shape: BoxShape.circle),
            child: isSel ? const Icon(Icons.circle,
              color: Colors.white, size: 8) : null),
        ])));
  }

  Widget _infoBox(String text) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFfffbeb),
      border: Border.all(
        color: const Color(0xFFF59E0B).withOpacity(0.3)),
      borderRadius: BorderRadius.circular(14)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start,
      children: [
      const Text('ℹ️', style: TextStyle(fontSize: 16)),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(
        fontSize: 12, color: Color(0xFF92400e), height: 1.5))),
    ]));

  Widget _buildBottomBar() {
    final total = _total;
    final hasAny = _selectedTasks.isNotEmpty || _isVisitOnly;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(
          color: AppColors.line, width: 1.5)),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 16, offset: const Offset(0,-4))]),
      child: Row(children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, children: [
          const Text('CUSTOMER PAYS', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: AppColors.muted, letterSpacing: 0.5)),
          Text(total > 0 ? '₹$total' : '₹0',
            style: const TextStyle(fontFamily: 'Sora', fontSize: 28,
              fontWeight: FontWeight.w800, color: AppColors.ink)),
          if (!hasAny)
            const Text('Select options to preview price',
              style: TextStyle(fontSize: 10, color: AppColors.muted))
          else if (_isVisitOnly)
            const Text('+ work charges quoted on-site',
              style: TextStyle(fontSize: 10, color: AppColors.muted)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.brand.withOpacity(0.1),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: AppColors.brand)),
          child: const Text('Provider View Only',
            style: TextStyle(fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.brand))),
      ]));
  }
}
