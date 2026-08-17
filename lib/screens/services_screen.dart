import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/provider_api_service.dart';
import '../utils/theme.dart';
import '../services/hs_catalog.dart';

class ServicesScreen extends StatefulWidget {
  final String providerId;
  const ServicesScreen({super.key, required this.providerId});
  @override
  State<ServicesScreen> createState() => _State();
}

class _State extends State<ServicesScreen> {
  Map<String, bool>           _enabled      = {};
  Map<String, Map<String,int>> _optionPrices = {};
  Map<String, Map<String,int>> _refPrices    = {};

  bool   _loading = true;
  bool   _saving  = false;
  String _cat     = 'All';

  static const _cats = [
    'All','Home Cleaning','Home Services','Vehicle Care',
    'Cooking','Beauty & Wellness','Health Services',
    'Care Services','Outdoor','Security','Pest Control',
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    // 1. Load enabled services
    try {
      final svcs = await ProviderApiService.getMyServices(widget.providerId);
      for (final s in svcs) {
        final id = s['svc_id']?.toString() ?? '';
        if (id.isEmpty) continue;
        _enabled[id] = s['enabled'] == 1 || s['enabled'] == true;
      }
    } catch (_) {}

    // 2. Load per-option prices — API returns {svcId: {key: price}}
    try {
      final prices = await ProviderApiService.getServiceOptionPrices();
      if (prices is Map) {
        prices.forEach((svcId, opts) {
          if (opts is Map) {
            _optionPrices[svcId.toString()] = {};
            opts.forEach((k, v) {
              final price = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
              if (price > 0) {
                _optionPrices[svcId.toString()]![k.toString()] = price;
              }
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Option prices load error: $e');
    }

    // 3. Load reference prices from admin (hs-prices.html)
    try {
      final ref = await ProviderApiService.getServicePrices('');
      if (ref is Map) {
        ref.forEach((svcId, grouped) {
          if (grouped is! Map) return;
          _refPrices[svcId.toString()] = {};
          grouped.forEach((groupKey, groupVal) {
            if (groupVal is Map) {
              groupVal.forEach((optKey, price) {
                final p = (price is num) ? price.toInt() : int.tryParse('$price') ?? 0;
                if (p > 0) {
                  _refPrices[svcId.toString()]!['${groupKey}_$optKey'] = p;
                }
              });
            } else if (groupKey == 'base' && groupVal is num) {
              _refPrices[svcId.toString()]!['base_base'] = groupVal.toInt();
            }
          });
        });
      }
    } catch (e) {
      debugPrint('Ref prices load error: $e');
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      // Save enabled/disabled + min/max
      final svcsList = HSCatalog.services.map((s) => <String,dynamic>{
        'svc_id':    s.id,
        'enabled':   (_enabled[s.id] == true) ? 1 : 0,
        'svc_name':  s.name,
        'svc_icon':  s.icon,
        'svc_cat':   s.cat,
        'min_price': _getMinPrice(s.id),
        'max_price': _getMaxPrice(s.id),
      }).toList();
      await ProviderApiService.saveMyServices(svcsList);

      // Save per-option prices
      for (final svcId in _optionPrices.keys) {
        final prices = _optionPrices[svcId];
        if (prices != null && prices.isNotEmpty) {
          await ProviderApiService.saveServiceOptionPrices(svcId, prices);
        }
      }

      final count = _enabled.values.where((v) => v).length;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Saved — $count services enabled'),
          backgroundColor: AppColors.green,
          duration: const Duration(seconds: 2),
        ));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: AppColors.red));
    }
    if (mounted) setState(() => _saving = false);
  }

  int _getMinPrice(String svcId) {
    final opts = _optionPrices[svcId];
    if (opts == null || opts.isEmpty) return 0;
    final vals = opts.values.where((v) => v > 0).toList();
    return vals.isEmpty ? 0 : vals.reduce((a, b) => a < b ? a : b);
  }

  int _getMaxPrice(String svcId) {
    final opts = _optionPrices[svcId];
    if (opts == null || opts.isEmpty) return 0;
    final vals = opts.values.where((v) => v > 0).toList();
    return vals.isEmpty ? 0 : vals.reduce((a, b) => a > b ? a : b);
  }

  void _openPriceEditor(HSService svc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PriceEditorSheet(
        svc: svc,
        optionPrices: Map<String,int>.from(_optionPrices[svc.id] ?? {}),
        refPrices: Map<String,int>.from(_refPrices[svc.id] ?? {}),
        onSave: (prices) {
          setState(() {
            _optionPrices[svc.id] = Map<String,int>.from(prices);
          });
        },
      ),
    );
  }

  void _openSimplePrice(HSService svc) {
    final cur = _optionPrices[svc.id];
    final minCtrl = TextEditingController(
      text: (cur?['base_min'] ?? 0) > 0 ? '${cur!['base_min']}' : '');
    final maxCtrl = TextEditingController(
      text: (cur?['base_max'] ?? 0) > 0 ? '${cur!['base_max']}' : '');
    final ref = _refPrices[svc.id];
    final refMin = ref?.values.where((v)=>v>0).fold<int>(0, (a,b)=>a==0?b:(b<a?b:a)) ?? 0;
    final refMax = ref?.values.where((v)=>v>0).fold<int>(0, (a,b)=>b>a?b:a) ?? 0;

    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Text(svc.icon, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 8),
        Expanded(child: Text(svc.name,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (refMin > 0)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.teal.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 14, color: AppColors.teal),
              const SizedBox(width: 6),
              Text('Admin ref: ₹$refMin – ₹$refMax',
                style: const TextStyle(fontSize: 12, color: AppColors.teal, fontWeight: FontWeight.w600)),
            ]),
          ),
        TextField(
          controller: minCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Min Price (₹)',
            prefixText: '₹',
            hintText: refMin > 0 ? '$refMin' : 'e.g. 300',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.teal, width: 2)),
          )),
        const SizedBox(height: 12),
        TextField(
          controller: maxCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Max Price (₹)',
            prefixText: '₹',
            hintText: refMax > 0 ? '$refMax' : 'e.g. 500',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.teal, width: 2)),
          )),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.teal,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () {
            final min = int.tryParse(minCtrl.text) ?? 0;
            final max = int.tryParse(maxCtrl.text) ?? 0;
            setState(() {
              _optionPrices[svc.id] = {'base_min': min, 'base_max': max};
            });
            Navigator.pop(context);
          },
          child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _cat == 'All'
        ? HSCatalog.services
        : HSCatalog.services.where((s) => s.cat == _cat).toList();
    final enabledCount = _enabled.values.where((v) => v).length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('My Services', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          Text('$enabledCount selected',
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
              ? const SizedBox(width:18,height:18,
                  child:CircularProgressIndicator(color:Colors.white,strokeWidth:2))
              : const Text('SAVE',
                  style: TextStyle(color:Colors.white,fontWeight:FontWeight.w800,fontSize:15)),
          ),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.teal))
        : Column(children: [
            // Category filter chips
            Container(
              color: Colors.white,
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                itemCount: _cats.length,
                separatorBuilder: (_,__) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final c = _cats[i];
                  final sel = c == _cat;
                  return GestureDetector(
                    onTap: () => setState(() => _cat = c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.teal : AppColors.bg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: sel ? AppColors.teal : AppColors.line),
                      ),
                      child: Text(c, style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: sel ? Colors.white : AppColors.ink2)),
                    ),
                  );
                },
              ),
            ),
            // Header row
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                GestureDetector(
                  onTap: () => setState(() {
                    for (final s in filtered) _enabled[s.id] = true;
                  }),
                  child: const Text('Select All',
                    style: TextStyle(fontSize: 12, color: AppColors.teal, fontWeight: FontWeight.w700))),
                const Text(' · ', style: TextStyle(color: AppColors.muted)),
                GestureDetector(
                  onTap: () => setState(() {
                    for (final s in filtered) _enabled[s.id] = false;
                  }),
                  child: const Text('Clear All',
                    style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600))),
                const Spacer(),
                const Text('Tap ₹ to set prices',
                  style: TextStyle(fontSize: 11, color: AppColors.muted)),
              ]),
            ),
            const Divider(height: 1),
            // Services list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filtered.length,
                itemBuilder: (_, i) => _card(filtered[i]),
              ),
            ),
          ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.teal,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text('Save $enabledCount Services',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
      ),
    );
  }

  Widget _card(HSService svc) {
    final isEnabled  = _enabled[svc.id] == true;
    final min        = _getMinPrice(svc.id);
    final max        = _getMaxPrice(svc.id);
    final hasPrices  = min > 0 || max > 0;
    final hasSubGrps = svc.groups.any((g) =>
        g.style != 'info' && g.items.isNotEmpty);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isEnabled ? AppColors.teal : AppColors.line,
          width: isEnabled ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          // Icon
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: isEnabled ? AppColors.teal.withOpacity(0.1) : AppColors.bg,
              borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(svc.icon,
              style: const TextStyle(fontSize: 22)))),
          const SizedBox(width: 12),
          // Name + category + price range
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(svc.name, style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700,
                color: isEnabled ? AppColors.teal : AppColors.ink)),
              Text(svc.cat,
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              if (isEnabled && hasPrices) ...[
                const SizedBox(height: 3),
                Text('₹$min – ₹$max',
                  style: const TextStyle(
                    fontSize: 12, color: AppColors.brand,
                    fontWeight: FontWeight.w700)),
              ] else if (isEnabled) ...[
                const SizedBox(height: 3),
                const Text('Tap ₹ Set to add prices',
                  style: TextStyle(fontSize: 11, color: AppColors.muted)),
              ],
            ])),
          // Price button
          if (isEnabled) ...[
            GestureDetector(
              onTap: () => hasSubGrps
                  ? _openPriceEditor(svc)
                  : _openSimplePrice(svc),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: hasPrices ? AppColors.teal : AppColors.brand,
                  borderRadius: BorderRadius.circular(8)),
                child: Text(
                  hasPrices ? '₹ Edit' : '₹ Set',
                  style: const TextStyle(
                    color: Colors.white, fontSize: 12,
                    fontWeight: FontWeight.w800)),
              ),
            ),
          ],
          // Toggle
          Switch(
            value: isEnabled,
            activeColor: AppColors.teal,
            onChanged: (v) => setState(() => _enabled[svc.id] = v),
          ),
        ]),
      ),
    );
  }
}

// ── Price Editor Bottom Sheet ──────────────────────────────────────────
class _PriceEditorSheet extends StatefulWidget {
  final HSService svc;
  final Map<String,int> optionPrices;
  final Map<String,int> refPrices;
  final void Function(Map<String,int>) onSave;
  const _PriceEditorSheet({
    required this.svc,
    required this.optionPrices,
    required this.refPrices,
    required this.onSave,
  });
  @override
  State<_PriceEditorSheet> createState() => _PriceEditorSheetState();
}

class _PriceEditorSheetState extends State<_PriceEditorSheet> {
  late Map<String,int> _prices;
  final Map<String, TextEditingController> _ctrls = {};

  @override
  void initState() {
    super.initState();
    _prices = Map<String,int>.from(widget.optionPrices);
    for (final grp in widget.svc.groups) {
      if (grp.style == 'info') continue;
      for (final opt in grp.items) {
        final key      = '${grp.key}_${opt.key}';
        final existing = _prices[key] ?? 0;
        _ctrls[key] = TextEditingController(
          text: existing > 0 ? existing.toString() : '');
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) c.dispose();
    super.dispose();
  }

  void _save() {
    final saved = <String,int>{};
    for (final entry in _ctrls.entries) {
      final val = int.tryParse(entry.value.text.trim()) ?? 0;
      if (val > 0) saved[entry.key] = val;
    }
    widget.onSave(saved);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final priceable = widget.svc.groups
        .where((g) => g.style != 'info' && g.items.isNotEmpty)
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, ctrl) => SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2)))),
              // Header
              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(widget.svc.icon,
                      style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.svc.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800,
                            color: Color(0xFF1a1a2e))),
                        const Text('Set your price per option',
                          style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
                      ])),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                      child: const Text('Save',
                        style: TextStyle(fontWeight: FontWeight.w800))),
                  ])),
              const Divider(height: 1),
              // Options list
              Expanded(
                child: ListView(
                  controller: ctrl,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    for (final grp in priceable) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 8),
                        child: Text(grp.title,
                          style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800,
                            color: AppColors.teal))),
                      for (final opt in grp.items) _optionRow(grp.key, opt),
                    ],
                    const SizedBox(height: 20),
                  ],
                )),
            ]),
        ),
      ),
    );
  }

  Widget _optionRow(String groupKey, HSOption opt) {
    final key  = '${groupKey}_${opt.key}';
    final ctrl = _ctrls[key];
    if (ctrl == null) return const SizedBox.shrink();
    final ref = widget.refPrices[key] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(children: [
        // Option label + ref price
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(opt.name,
              style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700,
                color: Color(0xFF1a1a2e))),
            if (ref > 0)
              Text('Suggested: ₹$ref',
                style: const TextStyle(
                  fontSize: 11, color: AppColors.teal,
                  fontWeight: FontWeight.w600)),
          ])),
        // Price input field
        SizedBox(
          width: 110,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800,
              color: Color(0xFF1a1a2e)),
            onChanged: (_) => setState((){}),
            decoration: InputDecoration(
              prefixText: '₹',
              prefixStyle: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700,
                color: AppColors.brand),
              hintText: ref > 0 ? '$ref' : 'e.g. 300',
              hintStyle: TextStyle(
                color: Colors.grey.shade400, fontSize: 14),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: ctrl.text.isNotEmpty
                      ? AppColors.teal
                      : const Color(0xFFE2E8F0),
                  width: ctrl.text.isNotEmpty ? 2 : 1)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: AppColors.teal, width: 2)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ),
      ]),
    );
  }
}
