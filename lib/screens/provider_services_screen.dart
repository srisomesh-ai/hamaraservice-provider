import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/theme.dart';
import '../services/service_price_service.dart';

class ProviderServicesScreen extends StatefulWidget {
  final String providerId;
  const ProviderServicesScreen({super.key, required this.providerId});
  @override State<ProviderServicesScreen> createState() => _ProviderServicesState();
}

class _ProviderServicesState extends State<ProviderServicesScreen> {
  List<Map<String, dynamic>> _allServices = [];
  Set<String> _myServices = {};
  bool _loading = true;
  String _filterCat = 'All';

  // All 25 services — reads prices from Firebase (admin-controlled)
  static const _cats = ['All','Home Cleaning','Appliance Care','Vehicle Care',
    'Medical','Beauty & Grooming','Care Services','Cooking','Repairs','Pest Control','Painting'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // Load all services from Firebase service_catalog
    final catalogSnap = await FirebaseDatabase.instance.ref('service_catalog').get();
    List<Map<String, dynamic>> services = [];

    if (catalogSnap.exists) {
      final data = Map<String, dynamic>.from(catalogSnap.value as Map);
      for (final entry in data.entries) {
        final svc = Map<String, dynamic>.from(entry.value as Map);
        services.add({...svc, 'id': entry.key});
      }
    } else {
      // Fallback — use hardcoded list if Firebase not seeded yet
      services = _fallbackServices;
    }

    // Sort by SVC ID
    services.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));

    // Load provider's current services
    final provSnap = await FirebaseDatabase.instance
        .ref('providers/\${widget.providerId}/services').get();
    Set<String> myServices = {};
    if (provSnap.exists) {
      final list = provSnap.value;
      if (list is List) {
        for (final item in list) {
          if (item is Map && item['id'] != null) myServices.add(item['id'].toString());
          else if (item is String) myServices.add(item);
        }
      }
    }

    setState(() {
      _allServices = services;
      _myServices = myServices;
      _loading = false;
    });
  }

  Future<void> _toggleService(Map<String, dynamic> svc) async {
    HapticFeedback.mediumImpact();
    final id = svc['id'] as String;
    setState(() {
      if (_myServices.contains(id)) {
        _myServices.remove(id);
      } else {
        _myServices.add(id);
      }
    });

    // Save to Firebase
    final servicesList = _myServices.map((svcId) {
      final s = _allServices.firstWhere((s) => s['id'] == svcId, orElse: () => {'id': svcId, 'name': svcId});
      return {
        'id': svcId,
        'name': s['name'] ?? svcId,
        'icon': s['icon'] ?? '🔧',
        'cat': s['cat'] ?? '',
      };
    }).toList();

    await FirebaseDatabase.instance
        .ref('providers/\${widget.providerId}/services')
        .set(servicesList);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_myServices.contains(id)
          ? '✅ \${svc['name']} added to your services'
          : '❌ \${svc['name']} removed'),
        backgroundColor: _myServices.contains(id) ? AppColors.green : AppColors.muted,
        duration: const Duration(seconds: 2)));
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filterCat == 'All') return _allServices;
    return _allServices.where((s) => s['cat'] == _filterCat).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('My Services'),
        backgroundColor: AppColors.teal,
        actions: [
          Center(child: Padding(padding: const EdgeInsets.only(right: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
              child: Text('\${_myServices.length} selected',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))))),
        ]),
      body: Column(children: [
        // Category filter tabs
        Container(color: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10),
          child: SingleChildScrollView(scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: _cats.map((cat) {
              final sel = _filterCat == cat;
              return GestureDetector(
                onTap: () { HapticFeedback.selectionClick(); setState(() => _filterCat = cat); },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.teal : AppColors.bg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: sel ? AppColors.teal : AppColors.line)),
                  child: Text(cat, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : AppColors.muted))));
            }).toList()))),

        // Info banner
        Container(color: AppColors.tealSoft, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, color: AppColors.teal, size: 16),
            const SizedBox(width: 8),
            const Expanded(child: Text('Tap a service to add/remove it. Only selected services will show to customers.',
              style: TextStyle(fontSize: 11, color: AppColors.teal, fontWeight: FontWeight.w500))),
          ])),

        // Service list
        Expanded(child: RefreshIndicator(
          onRefresh: _loadData,
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _filtered.length,
            itemBuilder: (_, i) {
              final svc = _filtered[i];
              final id = svc['id'] as String;
              final selected = _myServices.contains(id);
              final basePrice = ServicePriceService().getBasePrice(id);
              final commission = svc['commission'] ?? 12;
              final commAmt = (basePrice * commission / 100).round();
              final providerEarns = basePrice - commAmt;

              return GestureDetector(
                onTap: () => _toggleService(svc),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.tealSoft : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? AppColors.teal : AppColors.line,
                      width: selected ? 2 : 1)),
                  child: Row(children: [
                    Container(width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.teal.withOpacity(0.15) : AppColors.bg,
                        borderRadius: BorderRadius.circular(12)),
                      child: Center(child: Text(svc['icon'] ?? '🔧',
                        style: const TextStyle(fontSize: 24)))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(svc['name'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                        color: selected ? AppColors.teal : AppColors.ink)),
                      Text(svc['cat'] ?? '', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                      const SizedBox(height: 4),
                      Row(children: [
                        _pill('₹$basePrice', AppColors.teal),
                        const SizedBox(width: 6),
                        _pill('You earn: ₹$providerEarns', AppColors.green),
                        const SizedBox(width: 6),
                        _pill('$commission% comm', AppColors.purple),
                      ]),
                    ])),
                    Container(width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.teal : Colors.transparent,
                        border: Border.all(color: selected ? AppColors.teal : AppColors.line, width: 2),
                        borderRadius: BorderRadius.circular(8)),
                      child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 16) : null),
                  ])));
            }))),
      ]));
  }

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(5)),
    child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)));

  // Fallback if Firebase not seeded
  static const _fallbackServices = [
    {'id':'SVC001','icon':'🧹','name':'House Maid (Hourly)','cat':'Home Cleaning','commission':10},
    {'id':'SVC002','icon':'🫧','name':'Deep House Cleaning','cat':'Home Cleaning','commission':12},
    {'id':'SVC003','icon':'🚿','name':'Bathroom Cleaning','cat':'Home Cleaning','commission':10},
    {'id':'SVC004','icon':'🍳','name':'Kitchen Cleaning','cat':'Home Cleaning','commission':12},
    {'id':'SVC005','icon':'❄️','name':'AC Cleaning','cat':'Appliance Care','commission':12},
    {'id':'SVC006','icon':'🔩','name':'AC Repair','cat':'Appliance Care','commission':18},
    {'id':'SVC007','icon':'🫙','name':'Washing Machine Repair','cat':'Appliance Care','commission':19},
    {'id':'SVC008','icon':'🚗','name':'Car Wash','cat':'Vehicle Care','commission':10},
    {'id':'SVC009','icon':'🏍️','name':'Bike Wash','cat':'Vehicle Care','commission':10},
    {'id':'SVC010','icon':'👨‍⚕️','name':'Doctor Visit','cat':'Medical','commission':15},
    {'id':'SVC011','icon':'🧪','name':'Lab Test Collection','cat':'Medical','commission':15},
    {'id':'SVC012','icon':'💉','name':'Nurse Visit','cat':'Medical','commission':15},
    {'id':'SVC013','icon':'✂️','name':'Haircut (Men)','cat':'Beauty & Grooming','commission':10},
    {'id':'SVC014','icon':'💇','name':'Haircut (Women)','cat':'Beauty & Grooming','commission':12},
    {'id':'SVC015','icon':'💆','name':'Full Body Massage','cat':'Beauty & Grooming','commission':12},
    {'id':'SVC016','icon':'🧒','name':'Day Care Helper','cat':'Care Services','commission':10},
    {'id':'SVC017','icon':'👴','name':'Elder Care Attendant','cat':'Care Services','commission':15},
    {'id':'SVC018','icon':'🍱','name':'Cooking Person (Per Meal)','cat':'Cooking','commission':10},
    {'id':'SVC019','icon':'👨‍🍳','name':'Full-Day Cook','cat':'Cooking','commission':12},
    {'id':'SVC020','icon':'⚡','name':'Electrician Visit','cat':'Repairs','commission':23},
    {'id':'SVC021','icon':'🔧','name':'Plumber Visit','cat':'Repairs','commission':23},
    {'id':'SVC022','icon':'🪚','name':'Carpenter Visit','cat':'Repairs','commission':12},
    {'id':'SVC023','icon':'🐛','name':'Cockroach Control','cat':'Pest Control','commission':12},
    {'id':'SVC024','icon':'🔍','name':'Termite Inspection','cat':'Pest Control','commission':12},
    {'id':'SVC025','icon':'🎨','name':'Room Painting','cat':'Painting','commission':12},
  ];
}
