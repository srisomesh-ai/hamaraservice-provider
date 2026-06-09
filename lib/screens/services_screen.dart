import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/theme.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});
  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final _user = FirebaseAuth.instance.currentUser;
  bool _loading = true;
  bool _saving = false;
  final Set<String> _selected = {};

  final List<Map<String, dynamic>> _allServices = [
    {'id':'SVC001','icon':'ðŸ§¹','name':'House Maid','cat':'Cleaning'},
    {'id':'SVC002','icon':'ðŸ§½','name':'Deep Cleaning','cat':'Cleaning'},
    {'id':'SVC003','icon':'ðŸ›€','name':'Bathroom Cleaning','cat':'Cleaning'},
    {'id':'SVC004','icon':'ðŸ³','name':'Kitchen Cleaning','cat':'Cleaning'},
    {'id':'SVC005','icon':'ðŸ›‹ï¸','name':'Sofa / Carpet Cleaning','cat':'Cleaning'},
    {'id':'SVC006','icon':'ðŸ§´','name':'Laundry / Ironing','cat':'Cleaning'},
    {'id':'SVC007','icon':'â„ï¸','name':'AC Service','cat':'Appliances'},
    {'id':'SVC008','icon':'ðŸ”§','name':'Appliance Repair','cat':'Appliances'},
    {'id':'SVC009','icon':'âš¡','name':'Electrician','cat':'Repairs'},
    {'id':'SVC010','icon':'ðŸ”§','name':'Plumber','cat':'Repairs'},
    {'id':'SVC011','icon':'ðŸ”¨','name':'Carpenter','cat':'Repairs'},
    {'id':'SVC012','icon':'ðŸŽ¨','name':'Painter','cat':'Repairs'},
    {'id':'SVC013','icon':'ðŸš—','name':'Car / Bike Wash','cat':'Vehicle'},
    {'id':'SVC014','icon':'ðŸ”©','name':'Car Mechanic','cat':'Vehicle'},
    {'id':'SVC015','icon':'ðŸš™','name':'Driver','cat':'Vehicle'},
    {'id':'SVC016','icon':'ðŸ‘¨â€âš•ï¸','name':'Doctor Visit','cat':'Health'},
    {'id':'SVC017','icon':'ðŸ’‰','name':'Nurse Visit','cat':'Health'},
    {'id':'SVC018','icon':'ðŸ§ª','name':'Lab Test','cat':'Health'},
    {'id':'SVC019','icon':'ðŸ’ª','name':'Fitness Trainer','cat':'Health'},
    {'id':'SVC020','icon':'ðŸ’†','name':'Massage','cat':'Wellness'},
    {'id':'SVC021','icon':'ðŸ’‡','name':'Women Beauty','cat':'Wellness'},
    {'id':'SVC022','icon':'ðŸ’ˆ','name':'Men Haircut','cat':'Wellness'},
    {'id':'SVC023','icon':'ðŸ‘¶','name':'Babysitter','cat':'Care'},
    {'id':'SVC024','icon':'ðŸ§“','name':'Elderly Care','cat':'Care'},
    {'id':'SVC025','icon':'ðŸ›','name':'Pest Control','cat':'Cleaning'},
    {'id':'SVC026','icon':'ðŸŒ¿','name':'Gardener','cat':'Cleaning'},
    {'id':'SVC027','icon':'â˜€ï¸','name':'Solar Panel','cat':'Repairs'},
    {'id':'SVC028','icon':'ðŸ’§','name':'Water Purifier','cat':'Repairs'},
    {'id':'SVC029','icon':'ðŸ“·','name':'CCTV','cat':'Repairs'},
    {'id':'SVC030','icon':'ðŸ’‚','name':'Security Guard','cat':'Security'},
    {'id':'SVC031','icon':'ðŸ—ï¸','name':'Civil / Mason','cat':'Construction'},
  ];

  // Group services by category
  Map<String, List<Map<String, dynamic>>> get _grouped {
    final Map<String, List<Map<String, dynamic>>> map = {};
    for (final svc in _allServices) {
      final cat = svc['cat'] as String;
      map.putIfAbsent(cat, () => []).add(svc);
    }
    return map;
  }

  @override
  void initState() {
    super.initState();
    _loadExistingServices();
  }

  Future<void> _loadExistingServices() async {
    if (_user == null) return;
    try {
      final snap = await FirebaseDatabase.instance.ref('providers/${_user!.uid}/services').get();
      if (snap.exists && snap.value is List) {
        final list = snap.value as List;
        for (final item in list) {
          if (item is Map && item['name'] != null) {
            _selected.add(item['name'] as String);
          }
        }
      }
    } catch (e) {}
    setState(() => _loading = false);
  }

  Future<void> _saveServices() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one service'),
          backgroundColor: AppColors.red));
      return;
    }
    setState(() => _saving = true);
    try {
      final services = _selected.map((name) {
        final svc = _allServices.firstWhere((s) => s['name'] == name);
        return {'id': svc['id'], 'name': name, 'icon': svc['icon']};
      }).toList();

      await FirebaseDatabase.instance.ref('providers/${_user!.uid}').update({
        'services': services,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Services saved successfully!'),
            backgroundColor: AppColors.green));
        Navigator.pop(context, true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save. Try again.'),
          backgroundColor: AppColors.red));
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('My Services'),
        backgroundColor: AppColors.teal,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.teal))
          : Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  color: AppColors.tealSoft,
                  child: Row(children: [
                    const Icon(Icons.info_outline_rounded, color: AppColors.teal, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      '${_selected.length} service${_selected.length == 1 ? '' : 's'} selected. You\'ll only receive bookings for selected services.',
                      style: const TextStyle(fontSize: 13, color: AppColors.teal, fontWeight: FontWeight.w600),
                    )),
                  ]),
                ),

                // Services list
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: _grouped.entries.map((entry) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8, top: 8),
                            child: Text(entry.key.toUpperCase(),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                                color: AppColors.muted, letterSpacing: 0.8)),
                          ),
                          ...entry.value.map((svc) {
                            final selected = _selected.contains(svc['name']);
                            return GestureDetector(
                              onTap: () => setState(() {
                                if (selected) _selected.remove(svc['name']);
                                else _selected.add(svc['name'] as String);
                              }),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: selected ? AppColors.tealSoft : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: selected ? AppColors.teal : AppColors.line,
                                    width: selected ? 2 : 1,
                                  ),
                                ),
                                child: Row(children: [
                                  Text(svc['icon'] as String, style: const TextStyle(fontSize: 24)),
                                  const SizedBox(width: 12),
                                  Expanded(child: Text(svc['name'] as String,
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                                      color: selected ? AppColors.teal : AppColors.ink))),
                                  Container(
                                    width: 24, height: 24,
                                    decoration: BoxDecoration(
                                      color: selected ? AppColors.teal : Colors.transparent,
                                      border: Border.all(color: selected ? AppColors.teal : AppColors.line, width: 2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: selected ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
                                  ),
                                ]),
                              ),
                            );
                          }).toList(),
                          const SizedBox(height: 8),
                        ],
                      );
                    }).toList(),
                  ),
                ),

                // Save button
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  color: Colors.white,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveServices,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _saving
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation(Colors.white)))
                        : Text('Save ${_selected.length} Service${_selected.length == 1 ? '' : 's'}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
    );
  }
}
