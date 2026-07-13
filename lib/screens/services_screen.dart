import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/theme.dart';
import '../services/hs_catalog.dart';

class ServicesScreen extends StatefulWidget {
  final String providerId;
  const ServicesScreen({super.key, required this.providerId});
  @override
  State<ServicesScreen> createState() => _State();
}

class _State extends State<ServicesScreen> {
  // svcId → {enabled, min, max}
  Map<String, Map<String,dynamic>> _serviceData = {};
  Map<String, String> _refPrices = {}; // hs_service_prices reference labels
  bool _loading = true;
  bool _saving  = false;
  String _cat   = 'All';

  static const _cats = [
    'All','Home Cleaning','Home Services','Vehicle Care',
    'Cooking','Beauty & Wellness','Health Services',
    'Care Services','Outdoor','Security','Pest Control',
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    // Load existing provider service data
    try {
      final snap = await FirebaseDatabase.instance
          .ref('providers/\${widget.providerId}/services').get();
      if (snap.exists && snap.value is Map) {
        final d = Map<String,dynamic>.from(snap.value as Map);
        d.forEach((svcId, val) {
          if (val is bool) {
            // Old format — just enabled/disabled
            _serviceData[svcId] = {'enabled': val, 'min': 0, 'max': 0};
          } else if (val is Map) {
            // New format — {enabled, min, max}
            final m = Map<String,dynamic>.from(val);
            _serviceData[svcId] = {
              'enabled': m['enabled'] == true,
              'min':     (m['min'] as num?)?.toInt() ?? 0,
              'max':     (m['max'] as num?)?.toInt() ?? 0,
            };
          }
        });
      }
    } catch (_) {}

    // Load reference prices from hs_service_prices
    try {
      final priceSnap = await FirebaseDatabase.instance
          .ref('hs_service_prices').get();
      if (priceSnap.exists && priceSnap.value is Map) {
        final allPrices = Map<String,dynamic>.from(priceSnap.value as Map);
        allPrices.forEach((svcId, svcData) {
          if (svcData is! Map) return;
          final data = Map<String,dynamic>.from(svcData);
          final List<int> vals = [];
          if (data['base'] is num) vals.add((data['base'] as num).toInt());
          data.forEach((_, gv) {
            if (gv is Map) {
              Map<String,dynamic>.from(gv).forEach((_, v) {
                if (v is num && v.toInt() > 0) vals.add(v.toInt());
              });
            }
          });
          if (vals.isNotEmpty) {
            vals.sort();
            _refPrices[svcId] = 'Ref: ₹\${vals.first}–₹\${vals.last}';
          }
        });
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      final Map<String,dynamic> u = {};
      for (final s in HSCatalog.services) {
        final d = _serviceData[s.id];
        u[s.id] = {
          'enabled': d?['enabled'] == true,
          'min':     (d?['min'] as num?)?.toInt() ?? 0,
          'max':     (d?['max'] as num?)?.toInt() ?? 0,
        };
      }
      await FirebaseDatabase.instance
          .ref('providers/\${widget.providerId}/services').set(u);
      final enabledCount = _serviceData.values.where((d) => d['enabled'] == true).length;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Saved — \$enabledCount services enabled'),
          backgroundColor: AppColors.green));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: \$e'), backgroundColor: AppColors.red));
    }
    if (mounted) setState(() => _saving = false);
  }

  List<HSService> get _list => _cat == 'All'
      ? HSCatalog.services
      : HSCatalog.services.where((s) => s.cat == _cat).toList();

  bool _isEnabled(String id) => _serviceData[id]?['enabled'] == true;

  void _toggle(String id) {
    setState(() {
      final current = _serviceData[id] ?? {'enabled': false, 'min': 0, 'max': 0};
      _serviceData[id] = {
        ...current,
        'enabled': !(current['enabled'] == true),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: AppColors.teal)));

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('My Services',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          Text('\${_serviceData.values.where((d) => d['enabled']==true).length} selected',
            style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
        actions: [
          if (_saving)
            const Padding(padding: EdgeInsets.all(16),
              child: SizedBox(width:20, height:20,
                child: CircularProgressIndicator(color:Colors.white, strokeWidth:2)))
          else
            TextButton(
              onPressed: _save,
              child: const Text('SAVE',
                style: TextStyle(color:Colors.white, fontWeight:FontWeight.w800, fontSize:14))),
        ]),
      body: Column(children: [
        // Category filter
        Container(color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical:8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal:12),
            child: Row(children: _cats.map((c) {
              final sel = _cat == c;
              return GestureDetector(
                onTap: () => setState(() => _cat = c),
                child: Container(
                  margin: const EdgeInsets.only(right:8),
                  padding: const EdgeInsets.symmetric(horizontal:12, vertical:6),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.teal : AppColors.bg,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: sel ? AppColors.teal : AppColors.line)),
                  child: Text(c, style: TextStyle(fontSize:11,
                    fontWeight:FontWeight.w700,
                    color: sel ? Colors.white : AppColors.muted))));
            }).toList()))),
        // Quick actions
        Container(color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12,0,12,8),
          child: Row(children: [
            TextButton(
              onPressed: () => setState(() {
                for (final s in HSCatalog.services) {
                  _serviceData[s.id] = {
                    ..._serviceData[s.id] ?? {},
                    'enabled': true,
                    'min': _serviceData[s.id]?['min'] ?? 0,
                    'max': _serviceData[s.id]?['max'] ?? 0,
                  };
                }
              }),
              child: const Text('Select All',
                style: TextStyle(fontSize:12, color:AppColors.teal, fontWeight:FontWeight.w700))),
            const Text('·', style: TextStyle(color:AppColors.muted)),
            TextButton(
              onPressed: () => setState(() {
                for (final id in _serviceData.keys) {
                  _serviceData[id] = {..._serviceData[id]!, 'enabled': false};
                }
              }),
              child: const Text('Clear All',
                style: TextStyle(fontSize:12, color:AppColors.red, fontWeight:FontWeight.w700))),
            const Spacer(),
            const Text('Set your price range per service',
              style: TextStyle(fontSize:10, color:AppColors.muted)),
          ])),
        // List
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12,8,12,100),
          itemCount: _list.length,
          itemBuilder: (_, i) => _card(_list[i]))),
      ]),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16,10,16,28),
        color: Colors.white,
        child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.teal,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: Text(
            'Save \${_serviceData.values.where((d) => d['enabled']==true).length} Services',
            style: const TextStyle(fontSize:14, fontWeight:FontWeight.w700, color:Colors.white)))));
  }

  Widget _card(HSService svc) {
    final on = _isEnabled(svc.id);
    final data = _serviceData[svc.id] ?? {'enabled': false, 'min': 0, 'max': 0};
    final minCtrl = TextEditingController(
      text: (data['min'] as int? ?? 0) > 0 ? '${data['min']}' : '');
    final maxCtrl = TextEditingController(
      text: (data['max'] as int? ?? 0) > 0 ? '${data['max']}' : '');
    final ref = _refPrices[svc.id] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom:10),
      decoration: BoxDecoration(
        color: on ? AppColors.tealSoft : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: on ? AppColors.teal : AppColors.line, width: on ? 2 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius:6)]),
      child: Column(children: [
        // Top row — icon, name, toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(14,12,14,8),
          child: Row(children: [
            Container(width:46, height:46,
              decoration: BoxDecoration(
                color: on ? AppColors.teal.withOpacity(0.12) : AppColors.bg,
                borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text(svc.icon, style: const TextStyle(fontSize:24)))),
            const SizedBox(width:12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(svc.name,
                style: TextStyle(fontSize:14, fontWeight:FontWeight.w700,
                  color: on ? AppColors.teal : AppColors.ink)),
              const SizedBox(height:2),
              Row(children: [
                Text(svc.cat, style: const TextStyle(fontSize:11, color:AppColors.muted)),
                if (ref.isNotEmpty) ...[
                  const Text('  ·  ', style: TextStyle(fontSize:11, color:AppColors.muted)),
                  Text(ref, style: const TextStyle(fontSize:11,
                    fontWeight:FontWeight.w600, color:AppColors.brand)),
                ],
              ]),
            ])),
            Switch(
              value: on,
              onChanged: (_) { HapticFeedback.selectionClick(); _toggle(svc.id); },
              activeColor: AppColors.teal,
              activeTrackColor: AppColors.tealSoft),
          ])),

        // Price range inputs — only show when enabled
        if (on) ...[
          Divider(height:1, color: AppColors.teal.withOpacity(0.2)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14,10,14,14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.currency_rupee_rounded, size:14, color:AppColors.teal),
                const SizedBox(width:4),
                const Text('Your Price Range for this Service',
                  style: TextStyle(fontSize:12, fontWeight:FontWeight.w700, color:AppColors.teal)),
              ]),
              const SizedBox(height:4),
              if (ref.isNotEmpty)
                Text('Market guide: $ref',
                  style: const TextStyle(fontSize:11, color:AppColors.muted)),
              const SizedBox(height:8),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('MIN PRICE (₹)',
                    style: TextStyle(fontSize:10, fontWeight:FontWeight.w800,
                      color:AppColors.muted, letterSpacing:.5)),
                  const SizedBox(height:4),
                  TextField(
                    controller: minCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) {
                      final val = int.tryParse(v) ?? 0;
                      setState(() {
                        _serviceData[svc.id] = {
                          ..._serviceData[svc.id] ?? {},
                          'enabled': true,
                          'min': val,
                          'max': _serviceData[svc.id]?['max'] ?? 0,
                        };
                      });
                    },
                    decoration: InputDecoration(
                      hintText: '0',
                      prefixText: '₹ ',
                      contentPadding: const EdgeInsets.symmetric(horizontal:12, vertical:10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color:AppColors.teal, width:2))),
                  ),
                ])),
                const SizedBox(width:12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('MAX PRICE (₹)',
                    style: TextStyle(fontSize:10, fontWeight:FontWeight.w800,
                      color:AppColors.muted, letterSpacing:.5)),
                  const SizedBox(height:4),
                  TextField(
                    controller: maxCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) {
                      final val = int.tryParse(v) ?? 0;
                      setState(() {
                        _serviceData[svc.id] = {
                          ..._serviceData[svc.id] ?? {},
                          'enabled': true,
                          'min': _serviceData[svc.id]?['min'] ?? 0,
                          'max': val,
                        };
                      });
                    },
                    decoration: InputDecoration(
                      hintText: '0',
                      prefixText: '₹ ',
                      contentPadding: const EdgeInsets.symmetric(horizontal:12, vertical:10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color:AppColors.teal, width:2))),
                  ),
                ])),
              ]),
              const SizedBox(height:6),
              Text('You will enter your exact quote when accepting a job',
                style: TextStyle(fontSize:11, color:AppColors.muted.withOpacity(.8),
                  fontStyle: FontStyle.italic)),
            ])),
        ],
      ]));
  }
}
