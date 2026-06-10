import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/theme.dart';

class ServicesScreen extends StatefulWidget {
  final String providerId;
  const ServicesScreen({super.key, required this.providerId});
  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final _user = FirebaseAuth.instance.currentUser;
  bool _loading = true;
  bool _saving = false;

  // Selected services with their sub-tasks
  // Map<serviceName, Map<subTaskKey, bool>>
  final Map<String, Set<String>> _selected = {};

  final List<Map<String, dynamic>> _allServices = [
    {
      'name': 'House Maid',
      'cat': 'Cleaning',
      'subtasks': [
        'Sweeping & Mopping - 1 BHK', 'Sweeping & Mopping - 2 BHK',
        'Sweeping & Mopping - 3 BHK', 'Sweeping & Mopping - 4 BHK',
        'Sweeping & Mopping - Villa', 'Sweeping & Mopping - Studio',
        'Dusting - 1 BHK', 'Dusting - 2 BHK', 'Dusting - 3 BHK',
        'Dusting - 4 BHK', 'Dusting - Villa',
        'Dishwashing', 'Folding Clothes', 'Laundry / Washing',
      ],
    },
    {
      'name': 'Deep Cleaning',
      'cat': 'Cleaning',
      'subtasks': [
        'Deep Clean - 1 BHK', 'Deep Clean - 2 BHK', 'Deep Clean - 3 BHK',
        'Deep Clean - 4 BHK', 'Deep Clean - Villa',
      ],
    },
    {
      'name': 'Bathroom Cleaning',
      'cat': 'Cleaning',
      'subtasks': [
        '1 Bathroom', '2 Bathrooms', '3 Bathrooms', '4+ Bathrooms',
      ],
    },
    {
      'name': 'Kitchen Cleaning',
      'cat': 'Cleaning',
      'subtasks': ['Basic Kitchen Clean', 'Deep Kitchen Clean', 'Chimney Cleaning'],
    },
    {
      'name': 'Sofa / Carpet Cleaning',
      'cat': 'Cleaning',
      'subtasks': ['Sofa (2 Seater)', 'Sofa (3 Seater)', 'Sofa (5 Seater)',
        'Single Mattress', 'Double Mattress', 'Carpet (Small)', 'Carpet (Large)'],
    },
    {
      'name': 'Laundry / Ironing',
      'cat': 'Cleaning',
      'subtasks': ['Washing Only', 'Ironing Only', 'Wash + Iron', 'Dry Cleaning'],
    },
    {
      'name': 'Pest Control',
      'cat': 'Cleaning',
      'subtasks': ['Cockroaches', 'Bedbugs', 'Termites', 'Mosquitoes', 'Rats', 'Full Home'],
    },
    {
      'name': 'AC Service',
      'cat': 'Appliances',
      'subtasks': ['AC Service (1 Ton)', 'AC Service (1.5 Ton)', 'AC Service (2 Ton)',
        'AC Gas Refill', 'AC Installation', 'AC Repair'],
    },
    {
      'name': 'Appliance Repair',
      'cat': 'Appliances',
      'subtasks': ['Washing Machine', 'Refrigerator', 'TV / LED', 'Microwave',
        'Water Heater', 'Dishwasher'],
    },
    {
      'name': 'Electrician',
      'cat': 'Repairs',
      'subtasks': ['Wiring & Switches', 'Fan Installation', 'Light Fitting',
        'Short Circuit', 'MCB / Fuse', 'Inverter / Battery'],
    },
    {
      'name': 'Plumber',
      'cat': 'Repairs',
      'subtasks': ['Tap Repair', 'Pipe Fitting', 'Drainage Cleaning',
        'Motor Repair', 'Water Tank Cleaning', 'Toilet Repair'],
    },
    {
      'name': 'Carpenter',
      'cat': 'Repairs',
      'subtasks': ['Door / Window Repair', 'Furniture Assembly', 'Cupboard Fitting',
        'Bed Repair', 'Lock Repair'],
    },
    {
      'name': 'Painter',
      'cat': 'Repairs',
      'subtasks': [
        'Painting - 1 BHK', 'Painting - 2 BHK', 'Painting - 3 BHK',
        'Painting - 4 BHK', 'Painting - Villa', 'Single Room Painting',
      ],
    },
    {
      'name': 'Car / Bike Wash',
      'cat': 'Vehicle',
      'subtasks': ['Car Exterior Wash', 'Car Interior Clean', 'Full Car Wash',
        'Bike Wash', 'Car Polish', 'Car Steam Clean'],
    },
    {
      'name': 'Car Mechanic',
      'cat': 'Vehicle',
      'subtasks': ['Oil Change', 'Tyre Change', 'Battery Service',
        'General Service', 'AC Repair', 'Engine Check'],
    },
    {
      'name': 'Driver',
      'cat': 'Vehicle',
      'subtasks': ['Local Trip', 'Full Day', 'Outstation', 'Monthly'],
    },
    {
      'name': 'Doctor Visit',
      'cat': 'Health',
      'subtasks': ['General Physician', 'Child Specialist', 'Gynecologist', 'Orthopedic'],
    },
    {
      'name': 'Nurse Visit',
      'cat': 'Health',
      'subtasks': ['Injection / Dressing', 'IV Drip', 'Post Surgery Care',
        'Elderly Care', 'Full Day Nursing'],
    },
    {
      'name': 'Lab Test',
      'cat': 'Health',
      'subtasks': ['Blood Test', 'Sugar Test', 'Full Body Checkup', 'Urine Test', 'ECG'],
    },
    {
      'name': 'Fitness Trainer',
      'cat': 'Health',
      'subtasks': ['Weight Loss', 'Muscle Building', 'Yoga', 'Zumba', 'General Fitness'],
    },
    {
      'name': 'Massage',
      'cat': 'Wellness',
      'subtasks': ['Full Body Massage (Male)', 'Full Body Massage (Female)',
        'Head Massage', 'Back Massage', 'Foot Massage'],
    },
    {
      'name': 'Women Beauty',
      'cat': 'Wellness',
      'subtasks': ['Facial', 'Waxing', 'Threading', 'Manicure', 'Pedicure',
        'Bridal Makeup', 'Party Makeup'],
    },
    {
      'name': 'Men Haircut',
      'cat': 'Wellness',
      'subtasks': ['Haircut', 'Shave', 'Facial', 'Hair Color', 'Head Massage'],
    },
    {
      'name': 'Babysitter',
      'cat': 'Care',
      'subtasks': ['Half Day (4 hrs)', 'Full Day (8 hrs)', 'Night Care', 'Weekly'],
    },
    {
      'name': 'Elderly Care',
      'cat': 'Care',
      'subtasks': ['Companion Care', 'Personal Care', 'Full Day Care',
        'Night Care', 'Hospital Attendant'],
    },
    {
      'name': 'Security Guard',
      'cat': 'Security',
      'subtasks': ['Day Shift', 'Night Shift', 'Full Day', 'Armed Guard', 'Event Security'],
    },
    {
      'name': 'Solar Panel',
      'cat': 'Repairs',
      'subtasks': ['Installation', 'Cleaning', 'Repair', 'AMC'],
    },
    {
      'name': 'Water Purifier',
      'cat': 'Repairs',
      'subtasks': ['Installation', 'Service / Filter Change', 'Repair'],
    },
    {
      'name': 'CCTV',
      'cat': 'Repairs',
      'subtasks': ['Installation (2 Cam)', 'Installation (4 Cam)', 'Installation (8 Cam)',
        'Repair', 'AMC'],
    },
    {
      'name': 'Gardener',
      'cat': 'Cleaning',
      'subtasks': ['Garden Maintenance', 'Plant Care', 'Tree Trimming', 'Lawn Mowing'],
    },
    {
      'name': 'Civil / Mason',
      'cat': 'Construction',
      'subtasks': ['Wall Repair', 'Tiling', 'Waterproofing', 'False Ceiling', 'Renovation'],
    },
  ];

  Map<String, List<Map<String, dynamic>>> get _grouped {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final svc in _allServices) {
      final cat = svc['cat'] as String;
      map.putIfAbsent(cat, () => []).add(svc);
    }
    return map;
  }

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    if (_user == null) return;
    try {
      final snap = await FirebaseDatabase.instance.ref('providers/${_user!.uid}/services').get();
      if (snap.exists && snap.value is List) {
        for (final item in snap.value as List) {
          if (item is Map) {
            final name = item['name']?.toString() ?? '';
            final subtasks = item['subtasks'];
            if (name.isNotEmpty) {
              _selected[name] = {};
              if (subtasks is List) {
                for (final s in subtasks) {
                  _selected[name]!.add(s.toString());
                }
              }
            }
          }
        }
      }
    } catch (e) {}
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one service'),
          backgroundColor: AppColors.red));
      return;
    }
    setState(() => _saving = true);
    try {
      final services = _selected.entries.map((e) {
        final svc = _allServices.firstWhere((s) => s['name'] == e.key,
          orElse: () => {'name': e.key, 'cat': '', 'subtasks': []});
        return {
          'name':        e.key,
          'cat':         svc['cat'],
          'subcategory': svc['cat'],
          'icon':        '🔧',
          'price':       499,
          'subtasks':    e.value.toList(),
        };
      }).toList();

      await FirebaseDatabase.instance.ref('providers/${_user!.uid}').update({
        'services':  services,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Services saved!'), backgroundColor: AppColors.green));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save. Try again.'), backgroundColor: AppColors.red));
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final totalSelected = _selected.length;
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
                Container(
                  padding: const EdgeInsets.all(14),
                  color: AppColors.tealSoft,
                  child: Row(children: [
                    const Icon(Icons.info_outline_rounded, color: AppColors.teal, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      '$totalSelected service${totalSelected == 1 ? '' : 's'} selected. Select sub-tasks you can perform.',
                      style: const TextStyle(fontSize: 13, color: AppColors.teal, fontWeight: FontWeight.w600),
                    )),
                  ]),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: _grouped.entries.map((entry) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 8),
                            child: Text(entry.key.toUpperCase(),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                                color: AppColors.muted, letterSpacing: 0.8)),
                          ),
                          ...entry.value.map((svc) => _serviceItem(svc)).toList(),
                        ],
                      );
                    }).toList(),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  color: Colors.white,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _saving
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation(Colors.white)))
                        : Text('Save $totalSelected Service${totalSelected == 1 ? '' : 's'}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _serviceItem(Map<String, dynamic> svc) {
    final name = svc['name'] as String;
    final subtasks = svc['subtasks'] as List<String>;
    final isSelected = _selected.containsKey(name);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? AppColors.teal : AppColors.line,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Checkbox(
            value: isSelected,
            activeColor: AppColors.teal,
            onChanged: (val) => setState(() {
              if (val == true) {
                _selected[name] = Set.from(subtasks); // select all subtasks by default
              } else {
                _selected.remove(name);
              }
            }),
          ),
          title: Text(name,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              color: isSelected ? AppColors.teal : AppColors.ink)),
          subtitle: isSelected
              ? Text('${_selected[name]?.length ?? 0} of ${subtasks.length} sub-tasks',
                  style: const TextStyle(fontSize: 11, color: AppColors.teal))
              : null,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select sub-tasks you can perform:',
                    style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: subtasks.map((sub) {
                      final subSelected = _selected[name]?.contains(sub) ?? false;
                      return GestureDetector(
                        onTap: () => setState(() {
                          _selected.putIfAbsent(name, () => {});
                          if (subSelected) {
                            _selected[name]!.remove(sub);
                            if (_selected[name]!.isEmpty) _selected.remove(name);
                          } else {
                            _selected[name]!.add(sub);
                          }
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: subSelected ? AppColors.teal : AppColors.bg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: subSelected ? AppColors.teal : AppColors.line),
                          ),
                          child: Text(sub,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                              color: subSelected ? Colors.white : AppColors.ink2)),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
