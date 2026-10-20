import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/hs_catalog.dart';
import '../services/provider_api_service.dart';
import '../utils/parse.dart';
import '../utils/theme.dart';
import '../widgets/ui.dart';

/// My Services — two groups: "✅ Active services" on top and
/// "➕ Available to add" below. Tapping a row switches the service on/off and
/// saves instantly (providers.php?action=services with that one service).
/// Active services show whether a price range is set; the price sheet saves
/// the range + optional option prices (providers.php?action=save_option_prices).
/// Test-only sample data for screenshots (no network when set).
class ServicesDemo {
  final Map<String, bool> enabled;
  final Map<String, List<int>> ranges; // svcId → [min, max]
  const ServicesDemo({required this.enabled, this.ranges = const {}});
}

class ServicesScreen extends StatefulWidget {
  final String providerId;
  /// Shown as a bottom-navigation tab (no back arrow).
  final bool embedded;
  /// Bumped by the shell each time the tab is selected → reload.
  final int refreshTick;
  final ServicesDemo? demo;
  const ServicesScreen(
      {super.key, required this.providerId, this.embedded = false, this.refreshTick = 0, this.demo});
  @override
  State<ServicesScreen> createState() => _State();
}

class _Range {
  final int min;
  final int max;
  const _Range(this.min, this.max);
}

const _activeBg = Color(0xFFD1F2DD), _activeFg = Color(0xFF0F6D33);
const _inactiveBg = Color(0xFFECEFF0), _inactiveFg = Color(0xFF7B8A8E);
const _pricedBg = Color(0xFF1B7A3A);
const _warnBg = Color(0xFFFFF1DC), _warnFg = Color(0xFF9A4C00);

class _State extends State<ServicesScreen> {
  final Map<String, bool> _enabled = {};
  final Map<String, _Range> _ranges = {};
  final Map<String, Map<String, int>> _optionPrices = {};
  final Map<String, Map<String, int>> _refPrices = {};
  final Set<String> _busy = {};

  bool _loading = true;
  bool _loadFailed = false;
  String _cat = 'All';

  static const _cats = [
    'All', 'Home Cleaning', 'Home Services', 'Vehicle Care',
    'Cooking', 'Beauty & Wellness', 'Health Services',
    'Care Services', 'Outdoor', 'Security', 'Pest Control',
  ];

  @override
  void initState() {
    super.initState();
    final d = widget.demo;
    if (d != null) {
      _enabled.addAll(d.enabled);
      d.ranges.forEach((k, v) => _ranges[k] = _Range(v[0], v[1]));
      _loading = false;
      return;
    }
    _load();
  }

  @override
  void didUpdateWidget(ServicesScreen old) {
    super.didUpdateWidget(old);
    if (widget.demo == null && old.refreshTick != widget.refreshTick && !_loading) _load(quiet: true);
  }

  Future<void> _load({bool quiet = false}) async {
    if (mounted && !quiet) setState(() => _loading = true);

    // 1. My services: enabled flag + price range
    try {
      final svcs = await ProviderApiService.getMyServices(widget.providerId);
      _enabled.clear();
      _ranges.clear();
      for (final s in svcs) {
        final id = str(s['svc_id']);
        if (id.isEmpty) continue;
        _enabled[id] = toBool(s['enabled']);
        _ranges[id] = _Range(toInt(s['min_price']), toInt(s['max_price']));
      }
      _loadFailed = false;
    } catch (e) {
      _loadFailed = true;
      if (mounted) showSnack(context, 'Could not load your services: $e', tone: Tone.error);
    }

    // 2. Per-option prices — {svcId: {key: price}}
    try {
      final prices = await ProviderApiService.getServiceOptionPrices();
      prices.forEach((svcId, opts) {
        if (opts is! Map) return;
        final m = <String, int>{};
        opts.forEach((k, v) {
          final p = toInt(v);
          if (p > 0) m['$k'] = p;
        });
        _optionPrices['$svcId'] = m;
      });
    } catch (e) {
      debugPrint('Option prices load error: $e');
    }

    // 3. Admin reference prices: {svcId: {admin_prices: {group: {opt, opt_min, opt_max}}}}
    try {
      final ref = await ProviderApiService.getServicePrices('');
      ref.forEach((svcId, svcData) {
        if (svcData is! Map) return;
        final m = <String, int>{};
        final adminPrices = svcData['admin_prices'];
        if (adminPrices is Map) {
          adminPrices.forEach((groupKey, groupVal) {
            if (groupKey == 'name') return;
            if (groupVal is Map) {
              groupVal.forEach((optKey, price) {
                final p = toInt(price);
                if (p > 0) m['${groupKey}_$optKey'] = p;
              });
            }
          });
        }
        _refPrices['$svcId'] = m;
      });
    } catch (e) {
      debugPrint('Ref prices load error: $e');
    }

    if (mounted) setState(() => _loading = false);
  }

  void _snack(String msg, {Tone tone = Tone.neutral}) {
    if (!mounted) return;
    showSnack(context, msg, tone: tone);
  }

  bool _priced(String id) => (_ranges[id]?.min ?? 0) > 0;

  String _priceText(String id) {
    final r = _ranges[id];
    if (r == null || r.min <= 0) return '';
    return r.max > r.min ? '₹${r.min}–${r.max}' : '₹${r.min}';
  }

  /// Switch on/off and save instantly; revert on failure.
  Future<void> _toggle(HSService svc) async {
    if (widget.demo != null) return;
    if (_loadFailed) {
      _snack('Your services did not load. Retrying…', tone: Tone.error);
      _load();
      return;
    }
    if (_busy.contains(svc.id)) return;
    final on = !(_enabled[svc.id] ?? false);
    HapticFeedback.selectionClick();
    setState(() {
      _enabled[svc.id] = on;
      _busy.add(svc.id);
    });
    final res = await ProviderApiService.setServiceEnabled(
        svcId: svc.id, name: svc.name, icon: svc.icon, cat: svc.cat, enabled: on);
    if (!mounted) return;
    setState(() => _busy.remove(svc.id));
    if (!res.ok) {
      setState(() => _enabled[svc.id] = !on);
      if (!res.unauthorized) {
        _snack(res.error.isNotEmpty ? res.error : 'Could not save', tone: Tone.error);
      }
      return;
    }
    _snack(
        '${on ? '● ' : '○ '}${svc.name} is now ${on ? 'Active' : 'Inactive'}'
        '${on && !_priced(svc.id) ? ' — set your price' : ''}',
        tone: on ? Tone.success : Tone.neutral);
  }

  void _openPrices(HSService svc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PriceEditorSheet(
        svc: svc,
        range: _ranges[svc.id] ?? const _Range(0, 0),
        optionPrices: Map<String, int>.from(_optionPrices[svc.id] ?? {}),
        refPrices: Map<String, int>.from(_refPrices[svc.id] ?? {}),
        onSave: (prices, min, max) => _savePrices(svc, prices, min, max),
      ),
    );
  }

  /// Returns an error message, or null on success.
  Future<String?> _savePrices(
      HSService svc, Map<String, int> prices, int min, int max) async {
    final res = await ProviderApiService.saveServicePrices(svc.id,
        prices: prices, minPrice: min, maxPrice: max);
    if (!res.ok) return res.unauthorized ? '' : res.error;
    final d = res.map ?? {};
    if (!mounted) return null;
    setState(() {
      _optionPrices[svc.id] = prices;
      _ranges[svc.id] = _Range(toInt(d['min_price'], min), toInt(d['max_price'], max));
      _enabled[svc.id] = true; // saving prices also activates the service
    });
    _snack('✅ Prices saved', tone: Tone.success);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _cat == 'All'
        ? HSCatalog.services
        : HSCatalog.services.where((s) => s.cat == _cat).toList();
    final active = filtered.where((s) => _enabled[s.id] == true).toList();
    final avail = filtered.where((s) => _enabled[s.id] != true).toList();
    final totalActive = HSCatalog.services.where((s) => _enabled[s.id] == true).length;
    final unpriced = HSCatalog.services.where((s) => _enabled[s.id] == true && !_priced(s.id)).length;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: const Text('My Services'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('$totalActive active',
                  style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            color: Colors.white,
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              itemCount: _cats.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final c = _cats[i];
                return FilterChip(
                  label: Text(c),
                  selected: c == _cat,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _cat = c),
                );
              },
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Text(
                      'Tap a service to switch it on/off — changes save instantly. '
                      'Customers only see your active services with a price.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted)),
                  if (unpriced > 0) ...[
                    const SizedBox(height: 12),
                    Notice('$unpriced active service${unpriced == 1 ? '' : 's'} without a price — tap "Set price".',
                        tone: Tone.warning, icon: Icons.sell_outlined),
                  ],
                  SectionTitle('Active services (${active.length})'),
                  if (active.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No active services yet — add from the list below.',
                            style: TextStyle(fontSize: 14, color: AppColors.muted)),
                      ),
                    )
                  else
                    _group(active),
                  SectionTitle('Available to add (${avail.length})'),
                  _group(avail),
                ],
              ),
            ),
    );
  }

  Widget _group(List<HSService> list) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0) const Divider(indent: 72),
            _row(list[i]),
          ],
        ]),
      );

  Widget _pill(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
      );

  Widget _row(HSService svc) {
    final on = _enabled[svc.id] == true;
    final priced = on && _priced(svc.id);
    final busy = _busy.contains(svc.id);
    return InkWell(
      onTap: busy ? null : () => _toggle(svc),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: on ? AppColors.tealSoft : const Color(0xFFF1F4F5),
                borderRadius: BorderRadius.circular(12)),
            child: Text(svc.icon, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(svc.name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: on ? AppColors.ink : AppColors.ink2)),
              const SizedBox(height: 5),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                on
                    ? _pill('● Active', _activeBg, _activeFg)
                    : _pill('○ Inactive', _inactiveBg, _inactiveFg),
                if (on)
                  priced
                      ? _pill('✓ Price set ${_priceText(svc.id)}', _pricedBg, Colors.white)
                      : _pill('⚠ Set your price', _warnBg, _warnFg),
              ]),
              if (on)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: TextButton.icon(
                    onPressed: () => _openPrices(svc),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: priced ? AppColors.teal : AppColors.brand,
                      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 13.5),
                    ),
                    icon: Icon(priced ? Icons.edit_outlined : Icons.sell_outlined, size: 17),
                    label: Text(priced ? 'Edit price' : 'Set price'),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 4),
          busy
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                )
              : Switch(value: on, onChanged: (_) => _toggle(svc)),
        ]),
      ),
    );
  }
}

// ── Price Editor Bottom Sheet ──────────────────────────────────────────
class _PriceEditorSheet extends StatefulWidget {
  final HSService svc;
  final _Range range;
  final Map<String, int> optionPrices;
  final Map<String, int> refPrices;
  final Future<String?> Function(Map<String, int> prices, int min, int max) onSave;
  const _PriceEditorSheet({
    required this.svc,
    required this.range,
    required this.optionPrices,
    required this.refPrices,
    required this.onSave,
  });
  @override
  State<_PriceEditorSheet> createState() => _PriceEditorSheetState();
}

class _PriceEditorSheetState extends State<_PriceEditorSheet> {
  final Map<String, TextEditingController> _ctrls = {};
  late final TextEditingController _minCtrl;
  late final TextEditingController _maxCtrl;
  bool _saving = false;
  String _error = '';

  List<HSGroup> get _groups =>
      widget.svc.groups.where((g) => g.style == 'bhk' && g.items.isNotEmpty).toList();

  @override
  void initState() {
    super.initState();
    _minCtrl = TextEditingController(text: widget.range.min > 0 ? '${widget.range.min}' : '');
    _maxCtrl = TextEditingController(text: widget.range.max > 0 ? '${widget.range.max}' : '');
    for (final g in _groups) {
      for (final opt in g.items) {
        final key = '${g.key}_${opt.key}';
        final v = widget.optionPrices[key] ?? 0;
        _ctrls[key] = TextEditingController(text: v > 0 ? '$v' : '');
      }
    }
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  int _adminMin(String key) => widget.refPrices['${key}_min'] ?? 0;
  int _adminMax(String key) => widget.refPrices['${key}_max'] ?? 0;

  Future<void> _save() async {
    if (_saving) return;
    final prices = <String, int>{};
    for (final g in _groups) {
      for (final opt in g.items) {
        final key = '${g.key}_${opt.key}';
        final v = int.tryParse(_ctrls[key]?.text.trim() ?? '') ?? 0;
        if (v <= 0) continue;
        final mn = _adminMin(key), mx = _adminMax(key);
        if (mn > 0 && v < mn) { setState(() => _error = '${opt.name}: min ₹$mn'); return; }
        if (mx > 0 && v > mx) { setState(() => _error = '${opt.name}: max ₹$mx'); return; }
        prices[key] = v;
      }
    }
    final mn = int.tryParse(_minCtrl.text.trim()) ?? 0;
    final mx = int.tryParse(_maxCtrl.text.trim()) ?? 0;
    if (mn > 0 && mx > 0 && mx < mn) {
      setState(() => _error = 'Maximum must be more than minimum');
      return;
    }
    if (prices.isEmpty && mn <= 0 && mx <= 0) {
      setState(() => _error = 'Enter your price range');
      return;
    }
    setState(() { _saving = true; _error = ''; });
    final err = await widget.onSave(prices, mn, mx);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context);
    } else {
      setState(() { _saving = false; _error = err; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: groups.isEmpty ? 0.6 : 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, ctrl) => SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  Text(widget.svc.icon, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${widget.svc.name} — Prices',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
                  ),
                  IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.muted),
                      onPressed: () => Navigator.pop(context)),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: ctrl,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    const Text('Your price range',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.teal)),
                    const SizedBox(height: 4),
                    const Text(
                        'Customers see this range before booking. You still send the exact quote for each job.',
                        style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _rangeField(_minCtrl, 'Minimum ₹', 'e.g. 300')),
                      const SizedBox(width: 10),
                      Expanded(child: _rangeField(_maxCtrl, 'Maximum ₹', 'e.g. 800')),
                    ]),
                    if (groups.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Text('Option prices (optional)',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.teal)),
                      for (final g in groups) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 8),
                          child: Text(g.title,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink2)),
                        ),
                        for (final opt in g.items) _optionRow(g.key, opt),
                      ],
                    ],
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('⚠️ $_error',
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.red, fontWeight: FontWeight.w700)),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle_rounded, size: 20, color: Colors.white),
                      label: const Text('Save Prices',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.teal,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _rangeField(TextEditingController c, String label, String hint) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) { if (_error.isNotEmpty) setState(() => _error = ''); },
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.teal, width: 2)),
        ),
      );

  Widget _optionRow(String groupKey, HSOption opt) {
    final key = '${groupKey}_${opt.key}';
    final ctrl = _ctrls[key]!;
    final ref = widget.refPrices[key] ?? opt.price;
    final mn = _adminMin(key), mx = _adminMax(key);
    final cur = int.tryParse(ctrl.text) ?? 0;
    final bad = cur > 0 && ((mn > 0 && cur < mn) || (mx > 0 && cur > mx));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bad ? const Color(0xFFFFF5F5) : const Color(0xFFF4F6F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: bad ? AppColors.red : const Color(0xFFE2E8F0)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(opt.name,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
            if (mn > 0)
              Text('Allowed: ₹$mn – ₹$mx',
                  style: const TextStyle(fontSize: 11, color: AppColors.teal, fontWeight: FontWeight.w600)),
          ]),
        ),
        SizedBox(
          width: 104,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            onChanged: (_) => setState(() => _error = ''),
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: bad ? AppColors.red : AppColors.ink),
            decoration: InputDecoration(
              prefixText: '₹',
              hintText: ref > 0 ? '$ref' : '₹',
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ]),
    );
  }
}
