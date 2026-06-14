import 'package:firebase_database/firebase_database.dart';

/// ServicePriceService — Single source of truth for all prices
/// 
/// HOW IT WORKS:
/// 1. App starts → reads prices from Firebase service_catalog/
/// 2. If Firebase has price → use it (admin can update via admin app)
/// 3. If Firebase is empty → use hardcoded HS official prices as fallback
/// 4. Admin changes price → Firebase updates → all apps reflect immediately
///
/// PRICE SOURCE: HS Official Price List (hamaraservice.com/admin)
class ServicePriceService {
  static final ServicePriceService _instance = ServicePriceService._internal();
  factory ServicePriceService() => _instance;
  ServicePriceService._internal();

  // Cache loaded from Firebase
  final Map<String, Map<String, int>> _cachedPrices = {};
  bool _loaded = false;

  // ── OFFICIAL HS PRICES — DO NOT CHANGE ───────────────────────
  // These match exactly what is set in the HS Price admin tool
  // Firebase prices override these when admin updates them
  static const Map<String, Map<String, int>> _defaultPrices = {
    'SVC001': {
      'sweep_1bhk': 149,
      'sweep_2bhk': 249,
      'sweep_3bhk': 349,
      'sweep_4bhk': 449,
      'sweep_villa': 599,
      'sweep_studio': 99,
      'dust_1bhk': 199,
      'dust_2bhk': 329,
      'dust_3bhk': 449,
      'dust_4bhk': 579,
      'dust_villa': 749,
      'dust_studio': 149,
      'dishes_daily': 149,
      'dishes_people': 249,
      'dishes_event': 499,
      'dishes_marriage': 999,
      'clothes': 99,
      'laundry_base': 400,
      'laundry_per_extra_pair': 30,
    },
    'SVC002': {
      'studio': 899,
      '1bhk': 1499,
      '2bhk': 2199,
      '3bhk': 2999,
      '4bhk': 3999,
      'villa': 5499,
      'addon_kitchen': 499,
      'addon_bathroom': 299,
      'addon_windows': 399,
      'addon_sofa': 599,
    },
    'SVC003': {
      'count_1': 399,
      'count_2': 699,
      'count_3': 999,
      'count_4': 1299,
      'addon_deep': 200,
      'addon_exhaust': 150,
      'addon_tank': 299,
    },
    'SVC004': {
      'small': 499,
      'medium': 699,
      'large': 999,
      'commercial': 1499,
      'addon_chimney': 349,
      'addon_fridge': 199,
      'addon_microwave': 149,
      'addon_cabinets': 299,
    },
    'SVC005': {
      'split': 599,
      'window': 499,
      'cassette': 799,
      'central': 999,
      'addon_deepcoil': 200,
      'addon_drain': 150,
    },
    'SVC006': {
      'notcooling_split': 599,
      'notcooling_window': 499,
      'notcooling_cassette': 799,
      'notcooling_central': 999,
      'gasleak_split': 1499,
      'gasleak_window': 1399,
      'gasleak_cassette': 1699,
      'gasleak_central': 1899,
      'noise_split': 699,
      'notstart_split': 799,
      'remote_split': 299,
      'pcb_split': 1299,
    },
    'SVC007': {
      'front_base': 549,
      'top_base': 449,
      'semi_base': 349,
      'addon_noise': 100,
      'addon_leak': 150,
      'addon_notdrain': 100,
      'addon_drum': 200,
      'addon_motor': 300,
      'addon_panel': 400,
    },
    'SVC008': {
      'basic': 299,
      'standard': 499,
      'premium': 799,
      'suv': 999,
      'addon_engine': 499,
      'addon_polish': 399,
      'addon_interior': 299,
    },
    'SVC009': {
      'bike': 199,
      'scooter': 199,
      'sport': 299,
      'electric': 249,
      'addon_chain': 99,
      'addon_polish': 149,
    },
    'SVC010': {
      'gp': 699,
      'pediatric': 799,
      'senior': 799,
      'specialist': 999,
      'addon_report': 199,
    },
    'SVC011': {
      'blood': 199,
      'urine': 99,
      'stool': 99,
      'swab': 99,
      'bp': 99,
    },
    'SVC012': {
      'injection': 399,
      'dressing': 499,
      'iv': 799,
      'catheter': 699,
      'vitals': 299,
      'icu': 1499,
    },
    'SVC013': {
      'regular': 199,
      'fade': 299,
      'design': 349,
      'kids': 149,
      'addon_beard': 149,
      'addon_massage': 99,
    },
    'SVC014': {
      'cut': 349,
      'blowdry': 249,
      'wash': 199,
      'trim': 199,
      'treatment': 599,
      'coloring': 799,
      'addon_conditioning': 199,
      'addon_oilmassage': 149,
    },
    'SVC015': {
      'relaxation_60': 999,
      'relaxation_45': 849,
      'relaxation_90': 1399,
      'relaxation_120': 1799,
      'deep_60': 1299,
      'deep_90': 1799,
      'swedish_60': 1499,
      'ayurvedic_60': 1199,
      'foot_45': 499,
      'head_30': 399,
    },
    'SVC016': {
      'general_per_hr': 200,
      'homework_per_hr': 250,
      'activity_per_hr': 280,
      'overnight': 1500,
    },
    'SVC017': {
      'half_companion': 499,
      'half_medical': 699,
      'half_physio': 799,
      'half_alzheimer': 899,
      'full_companion': 899,
      'full_medical': 1099,
      'full_physio': 1199,
      'full_alzheimer': 1299,
      'night_companion': 799,
      'night_medical': 999,
      'hr24_companion': 1499,
      'hr24_medical': 1699,
    },
    'SVC018': {
      'breakfast': 199,
      'lunch': 299,
      'dinner': 299,
      'tiffin': 149,
      'extra_person': 50,
      'addon_dishes': 99,
    },
    'SVC019': {
      'base_4persons': 799,
      'extra_person': 100,
      'addon_special': 300,
    },
    'SVC020': {
      'switch': 399,
      'light': 299,
      'fan': 399,
      'exhaust': 349,
      'mcb': 499,
      'short': 699,
      'wiring': 599,
      'socket': 399,
    },
    'SVC021': {
      'tap': 399,
      'pipe': 499,
      'flush': 449,
      'block': 549,
      'heater': 599,
      'drain': 499,
      'tank': 699,
      'motor': 799,
    },
    'SVC022': {
      'furniture': 349,
      'bed': 499,
      'door': 449,
      'window': 399,
      'hinge': 299,
      'lock': 349,
      'shelf': 399,
      'cabinet': 549,
    },
    'SVC023': {
      'studio': 599,
      '1bhk': 799,
      '2bhk': 999,
      '3bhk': 1299,
      '4bhk': 1599,
      'villa': 2499,
      'addon_ants': 200,
      'addon_lizard': 150,
      'addon_mosquito': 250,
      'addon_bedbugs': 499,
    },
    'SVC024': {
      'inspection': 499,
      'prevention': 1499,
      'treatment': 2999,
      'complete': 4999,
      'addon_villa': 500,
      'addon_office': 800,
      'addon_warehouse': 1500,
    },
    'SVC025': {
      'room': 1499,
      '2bhk': 3999,
      '3bhk': 5499,
      'full': 7999,
      'exterior': 4999,
      'finish_premium': 800,
      'finish_texture': 1500,
      'finish_weather': 1200,
      'addon_ceiling': 500,
      'addon_putty': 800,
      'addon_primer': 400,
    },
  };

  // ── Load prices from Firebase (call once at app start) ────────
  Future<void> loadPrices() async {
    if (_loaded) return;
    try {
      final snap = await FirebaseDatabase.instance
          .ref('service_catalog').get();
      if (snap.exists) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        for (final entry in data.entries) {
          final svcId = entry.key;
          final svcData = Map<String, dynamic>.from(entry.value as Map);
          if (svcData['subcategories'] != null) {
            final subs = Map<String, dynamic>.from(svcData['subcategories'] as Map);
            _cachedPrices[svcId] = subs.map((k, v) => MapEntry(k, (v as num).toInt()));
          }
        }
      }
    } catch (_) {}
    _loaded = true;
  }

  // ── Get price for a specific subcategory ──────────────────────
  int getPrice(String svcId, String subKey) {
    // Try Firebase cached price first
    final fbPrice = _cachedPrices[svcId]?[subKey];
    if (fbPrice != null && fbPrice > 0) return fbPrice;
    // Fallback to official HS price
    return _defaultPrices[svcId]?[subKey] ?? 0;
  }

  // ── Get base price for a service ─────────────────────────────
  int getBasePrice(String svcId) {
    final defaults = {
      'SVC001': 150, 'SVC002': 1499, 'SVC003': 399, 'SVC004': 699,
      'SVC005': 599, 'SVC006': 599, 'SVC007': 549, 'SVC008': 499,
      'SVC009': 199, 'SVC010': 699, 'SVC011': 199, 'SVC012': 399,
      'SVC013': 199, 'SVC014': 349, 'SVC015': 999, 'SVC016': 200,
      'SVC017': 499, 'SVC018': 299, 'SVC019': 799, 'SVC020': 399,
      'SVC021': 399, 'SVC022': 349, 'SVC023': 799, 'SVC024': 499,
      'SVC025': 1499,
    };
    // Check Firebase for admin-updated base price
    final fbBase = _cachedPrices[svcId]?['basePrice'];
    if (fbBase != null && fbBase > 0) return fbBase;
    return defaults[svcId] ?? 0;
  }

  // ── Seed Firebase with HS official prices (one-time) ─────────
  // Called by admin app on first launch to populate Firebase
  static Future<void> seedToFirebase() async {
    final updates = <String, dynamic>{};
    final catalog = {
      'SVC001': {'name':'House Maid (Hourly)','icon':'🧹','cat':'Home Cleaning','basePrice':150,'commission':10,'providerEarns':135,'status':'active'},
      'SVC002': {'name':'Deep House Cleaning','icon':'🫧','cat':'Home Cleaning','basePrice':1499,'commission':12,'providerEarns':1319,'status':'active'},
      'SVC003': {'name':'Bathroom Cleaning','icon':'🚿','cat':'Home Cleaning','basePrice':399,'commission':10,'providerEarns':359,'status':'active'},
      'SVC004': {'name':'Kitchen Cleaning','icon':'🍳','cat':'Home Cleaning','basePrice':699,'commission':12,'providerEarns':615,'status':'active'},
      'SVC005': {'name':'AC Cleaning','icon':'❄️','cat':'Appliance Care','basePrice':599,'commission':12,'providerEarns':527,'status':'active'},
      'SVC006': {'name':'AC Repair','icon':'🔩','cat':'Appliance Care','basePrice':599,'commission':18,'providerEarns':489,'status':'active'},
      'SVC007': {'name':'Washing Machine Repair','icon':'🫙','cat':'Appliance Care','basePrice':549,'commission':19,'providerEarns':444,'status':'active'},
      'SVC008': {'name':'Car Wash','icon':'🚗','cat':'Vehicle Care','basePrice':499,'commission':10,'providerEarns':449,'status':'active'},
      'SVC009': {'name':'Bike Wash','icon':'🏍️','cat':'Vehicle Care','basePrice':199,'commission':10,'providerEarns':179,'status':'active'},
      'SVC010': {'name':'Doctor Visit','icon':'👨‍⚕️','cat':'Medical','basePrice':699,'commission':15,'providerEarns':594,'status':'active'},
      'SVC011': {'name':'Lab Test Collection','icon':'🧪','cat':'Medical','basePrice':199,'commission':15,'providerEarns':169,'status':'active'},
      'SVC012': {'name':'Nurse Visit','icon':'💉','cat':'Medical','basePrice':399,'commission':15,'providerEarns':339,'status':'active'},
      'SVC013': {'name':'Haircut (Men)','icon':'✂️','cat':'Beauty & Grooming','basePrice':199,'commission':10,'providerEarns':179,'status':'active'},
      'SVC014': {'name':'Haircut (Women)','icon':'💇','cat':'Beauty & Grooming','basePrice':349,'commission':12,'providerEarns':307,'status':'active'},
      'SVC015': {'name':'Full Body Massage','icon':'💆','cat':'Beauty & Grooming','basePrice':999,'commission':12,'providerEarns':879,'status':'active'},
      'SVC016': {'name':'Day Care Helper','icon':'🧒','cat':'Care Services','basePrice':200,'commission':10,'providerEarns':180,'status':'active'},
      'SVC017': {'name':'Elder Care Attendant','icon':'👴','cat':'Care Services','basePrice':499,'commission':15,'providerEarns':424,'status':'active'},
      'SVC018': {'name':'Cooking Person (Per Meal)','icon':'🍱','cat':'Cooking','basePrice':299,'commission':10,'providerEarns':269,'status':'active'},
      'SVC019': {'name':'Full-Day Cook','icon':'👨‍🍳','cat':'Cooking','basePrice':799,'commission':12,'providerEarns':703,'status':'active'},
      'SVC020': {'name':'Electrician Visit','icon':'⚡','cat':'Repairs','basePrice':399,'commission':23,'providerEarns':309,'status':'active'},
      'SVC021': {'name':'Plumber Visit','icon':'🔧','cat':'Repairs','basePrice':399,'commission':23,'providerEarns':309,'status':'active'},
      'SVC022': {'name':'Carpenter Visit','icon':'🪚','cat':'Repairs','basePrice':349,'commission':12,'providerEarns':307,'status':'active'},
      'SVC023': {'name':'Cockroach Control','icon':'🐛','cat':'Pest Control','basePrice':799,'commission':12,'providerEarns':703,'status':'active'},
      'SVC024': {'name':'Termite Inspection','icon':'🔍','cat':'Pest Control','basePrice':499,'commission':12,'providerEarns':439,'status':'active'},
      'SVC025': {'name':'Room Painting','icon':'🎨','cat':'Painting','basePrice':1499,'commission':12,'providerEarns':1319,'status':'active'},
    };
    
    for (final entry in catalog.entries) {
      updates['service_catalog/${entry.key}'] = entry.value;
    }

    // Subcategory prices
    final subcats = _defaultPrices;
    for (final entry in subcats.entries) {
      for (final sub in entry.value.entries) {
        updates['service_catalog/${entry.key}/subcategories/${sub.key}'] = sub.value;
      }
    }

    await FirebaseDatabase.instance.ref().update(updates);
  }
}
