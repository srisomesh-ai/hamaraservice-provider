// ╔══════════════════════════════════════════════════════════════════╗
// ║  HamaraService — MASTER CATALOG                                  ║
// ║  Single source of truth for ALL services, subcategories & prices ║
// ║  Matches hs-prices.html exactly. DO NOT edit prices here —       ║
// ║  admin updates Firebase; apps read from Firebase.                ║
// ╚══════════════════════════════════════════════════════════════════╝

import 'package:firebase_database/firebase_database.dart';

// ── Option types ──────────────────────────────────────────────────────
// 'bhk'   = selectable size/type chip with price (single-select per group)
// 'task'  = selectable task chip with individual price (multi-select)
// 'info'  = text info note, no price chip

class HSOption {
  final String key;
  final String name;
  final String ico;  // emoji
  final int price;
  const HSOption({required this.key, required this.name, this.ico = '', this.price = 0});
}

class HSGroup {
  final String key;
  final String title;
  final String style;     // 'bhk' | 'task' | 'info'
  final String? showOn;   // show only when this task key is selected
  final String? info;     // for style:'info'
  final List<HSOption> items;
  const HSGroup({
    required this.key,
    required this.title,
    required this.style,
    this.showOn,
    this.info,
    this.items = const [],
  });
}

class HSService {
  final String id;
  final String name;
  final String icon;
  final String cat;
  final int basePrice;
  final List<HSGroup> groups;
  const HSService({
    required this.id,
    required this.name,
    required this.icon,
    required this.cat,
    required this.basePrice,
    required this.groups,
  });
}

// ── MASTER CATALOG ────────────────────────────────────────────────────
class HSCatalog {
  static const List<HSService> services = [

    // ── SVC001 House Maid ──────────────────────────────────────────
    HSService(id:'SVC001', name:'House Maid', icon:'🧹', cat:'Home Cleaning', basePrice:0, groups:[
      HSGroup(key:'task', title:'Select Tasks', style:'label', items:[
        HSOption(key:'sweep',   name:'Sweeping & Mopping',    ico:'🧹'),
        HSOption(key:'dust',    name:'Dusting',               ico:'🪣'),
        HSOption(key:'dishes',  name:'Dishwashing',           ico:'🍽️'),
        HSOption(key:'clothes', name:'Folding Clothes',       ico:'👗'),
        HSOption(key:'laundry', name:'Laundry (Washing)',     ico:'👚'),
      ]),
      HSGroup(key:'sweep', title:'Home Size (for Sweeping & Mopping)', style:'bhk', showOn:'sweep', items:[
        HSOption(key:'studio', name:'Studio / 1 Room',  price:0),
        HSOption(key:'1bhk',   name:'1 BHK',            price:0),
        HSOption(key:'2bhk',   name:'2 BHK',            price:0),
        HSOption(key:'3bhk',   name:'3 BHK',            price:0),
        HSOption(key:'4bhk',   name:'4 BHK',            price:0),
        HSOption(key:'villa',  name:'Villa / Bungalow', price:0),
      ]),
      HSGroup(key:'dust', title:'Home Size (for Dusting)', style:'bhk', showOn:'dust', items:[
        HSOption(key:'studio', name:'Studio / 1 Room',  price:0),
        HSOption(key:'1bhk',   name:'1 BHK',            price:0),
        HSOption(key:'2bhk',   name:'2 BHK',            price:0),
        HSOption(key:'3bhk',   name:'3 BHK',            price:0),
        HSOption(key:'4bhk',   name:'4 BHK',            price:0),
        HSOption(key:'villa',  name:'Villa / Bungalow', price:0),
      ]),
      HSGroup(key:'dishes', title:'Dishwashing — Occasion', style:'bhk', showOn:'dishes', items:[
        HSOption(key:'daily',    name:'Daily (home)',                     price:0),
        HSOption(key:'people',   name:'Small gathering (10–20 people)',   price:0),
        HSOption(key:'event',    name:'Party / Event (20–50 people)',     price:0),
        HSOption(key:'marriage', name:'Marriage / Big function (50+)',    price:0),
      ]),
      HSGroup(key:'clothes', title:'Folding Clothes — Pricing', style:'info',
        info:'Price is ₹2 per cloth, minimum ₹50. Provider will confirm total on arrival.'),
      HSGroup(key:'laundry', title:'Laundry (Washing) — Pricing', style:'info',
        info:'Base ₹400 for up to 20 pairs, +₹15 per extra pair. Provider will confirm on arrival.'),
    ]),

    // ── SVC002 Deep Cleaning ───────────────────────────────────────
    HSService(id:'SVC002', name:'Deep Cleaning', icon:'🧽', cat:'Home Cleaning', basePrice:0, groups:[
      HSGroup(key:'bhk', title:'With Material & Equipment — Price per Home Size', style:'bhk', items:[
        HSOption(key:'studio', name:'Studio / 1 Room',  price:0),
        HSOption(key:'1bhk',   name:'1 BHK',            price:0),
        HSOption(key:'2bhk',   name:'2 BHK',            price:0),
        HSOption(key:'3bhk',   name:'3 BHK',            price:0),
        HSOption(key:'4bhk',   name:'4 BHK+',           price:0),
        HSOption(key:'rooms',  name:'Individual Rooms',  price:0),
      ]),
      HSGroup(key:'extras', title:'Optional Add-ons', style:'task', items:[
        HSOption(key:'mattress',    ico:'🛏️', name:'Mattress Shampooing',   price:0),
        HSOption(key:'carpet',      ico:'🟫', name:'Carpet Cleaning',        price:0),
        HSOption(key:'sofashampoo', ico:'🛋️', name:'Sofa Shampoo',          price:0),
        HSOption(key:'balcony',     ico:'🏠', name:'Balcony Cleaning',       price:0),
        HSOption(key:'watertank',   ico:'💧', name:'Water Tank Cleaning',    price:0),
        HSOption(key:'pest',        ico:'🪲', name:'Pest Control Add-on',    price:0),
      ]),
      HSGroup(key:'condition', title:'Home Condition Surcharge', style:'bhk', items:[
        HSOption(key:'regular',    name:'Regularly Maintained',  price:0),
        HSOption(key:'moderate',   name:'Moderately Dirty',      price:0),
        HSOption(key:'dirty',      name:'Very Dirty',            price:0),
        HSOption(key:'renovation', name:'Post-Renovation',       price:0),
      ]),
    ]),

    // ── SVC003 Bathroom Cleaning ───────────────────────────────────
    HSService(id:'SVC003', name:'Bathroom Cleaning', icon:'🚿', cat:'Home Cleaning', basePrice:0, groups:[
      HSGroup(key:'with', title:'With Material & Equipment — Per Bathroom', style:'bhk', items:[
        HSOption(key:'perBath', name:'Per Bathroom', price:0),
      ]),
      HSGroup(key:'addon', title:'Add-ons', style:'task', items:[
        HSOption(key:'bathtub', ico:'🛁', name:'Bathtub Deep Clean',  price:0),
        HSOption(key:'shower',  ico:'🚿', name:'Glass Shower Cabin',  price:0),
      ]),
      HSGroup(key:'condition', title:'Condition Surcharge', style:'bhk', items:[
        HSOption(key:'normal',   name:'Normal',            price:0),
        HSOption(key:'moderate', name:'Moderately Dirty',  price:0),
        HSOption(key:'dirty',    name:'Very Dirty',        price:0),
        HSOption(key:'mold',     name:'Mold / Fungus',     price:0),
      ]),
    ]),

    // ── SVC004 Kitchen Cleaning ────────────────────────────────────
    HSService(id:'SVC004', name:'Kitchen Cleaning', icon:'🍳', cat:'Home Cleaning', basePrice:0, groups:[
      HSGroup(key:'with', title:'With Material & Equipment — Select What to Clean', style:'task', items:[
        HSOption(key:'tiles',    ico:'🧱', name:'Degreasing Tiles & Walls',      price:0),
        HSOption(key:'cabinets', ico:'🗄️', name:'Cabinets (inside & outside)',   price:0),
        HSOption(key:'chimney',  ico:'🏭', name:'Chimney Exterior',              price:0),
        HSOption(key:'sink',     ico:'🚰', name:'Sink & Tap Descaling',          price:0),
        HSOption(key:'stove',    ico:'🔥', name:'Stove & Countertop',            price:0),
        HSOption(key:'floor',    ico:'🧹', name:'Floor Scrubbing',               price:0),
      ]),
      HSGroup(key:'grease', title:'Grease Level Surcharge', style:'bhk', items:[
        HSOption(key:'light', name:'Light / Regular',                      price:0),
        HSOption(key:'heavy', name:'Heavy / Months without cleaning',      price:0),
      ]),
    ]),

    // ── SVC005 Sofa / Carpet Cleaning ─────────────────────────────
    HSService(id:'SVC005', name:'Sofa / Carpet Cleaning', icon:'🛋️', cat:'Home Cleaning', basePrice:0, groups:[
      HSGroup(key:'visit', title:'Visit / Call-out Price', style:'bhk', items:[
        HSOption(key:'visit', name:'Visit fee (provider will quote exact price on arrival)', price:0),
      ]),
    ]),

    // ── SVC006 Laundry / Ironing ───────────────────────────────────
    HSService(id:'SVC006', name:'Laundry / Ironing', icon:'👕', cat:'Home Cleaning', basePrice:0, groups:[
      HSGroup(key:'wash', title:'Washing — Base Price (per 15 items)', style:'bhk', items:[
        HSOption(key:'basePrice', name:'Per 15 clothes (base)',        price:0),
        HSOption(key:'extraPer',  name:'Per extra item (above 15)',    price:0),
      ]),
      HSGroup(key:'iron', title:'Ironing — Base Price (per 10 items)', style:'bhk', items:[
        HSOption(key:'basePrice', name:'Per 10 clothes (base)',        price:0),
        HSOption(key:'extraPer',  name:'Per extra item (above 10)',    price:0),
      ]),
      HSGroup(key:'dry',      title:'Dry Service — Per Visit',  style:'bhk', items:[HSOption(key:'perVisit', name:'Per visit', price:0)]),
      HSGroup(key:'fold',     title:'Fold Service — Per Visit', style:'bhk', items:[HSOption(key:'perVisit', name:'Per visit', price:0)]),
      HSGroup(key:'handwash', title:'Handwash — Per Visit',     style:'bhk', items:[HSOption(key:'perVisit', name:'Per visit', price:0)]),
    ]),

    // ── SVC007 AC Cleaning & Repair ────────────────────────────────
    HSService(id:'SVC007', name:'AC Cleaning & Repair', icon:'❄️', cat:'Home Services', basePrice:0, groups:[
      HSGroup(key:'visit', title:'Visit / Call-out Price', style:'bhk', items:[
        HSOption(key:'visit', name:'Visit fee (work quoted on-site)', price:0),
      ]),
    ]),

    // ── SVC009 Home Appliance Repair ──────────────────────────────
    HSService(id:'SVC009', name:'Home Appliance Repair', icon:'🔌', cat:'Home Services', basePrice:0, groups:[
      HSGroup(key:'appliance', title:'Visit / Call-out Price', style:'bhk', items:[
        HSOption(key:'visit', name:'Visit fee (work quoted on-site)', price:0),
      ]),
    ]),

    // ── SVC010 Water Purifier Service ─────────────────────────────
    HSService(id:'SVC010', name:'Water Purifier Service', icon:'💧', cat:'Home Services', basePrice:0, groups:[
      HSGroup(key:'visit', title:'Visit / Call-out Price', style:'bhk', items:[
        HSOption(key:'visit', name:'Visit fee (work quoted on-site)', price:0),
      ]),
    ]),

    // ── SVC011 Plumber ─────────────────────────────────────────────
    HSService(id:'SVC011', name:'Plumber', icon:'🪠', cat:'Home Services', basePrice:0, groups:[
      HSGroup(key:'visit', title:'Visit / Call-out Price', style:'bhk', items:[
        HSOption(key:'visit', name:'Visit fee (work quoted on-site)', price:0),
      ]),
    ]),

    // ── SVC012 Electrician ─────────────────────────────────────────
    HSService(id:'SVC012', name:'Electrician', icon:'⚡', cat:'Home Services', basePrice:0, groups:[
      HSGroup(key:'visit', title:'Visit / Call-out Price', style:'bhk', items:[
        HSOption(key:'visit', name:'Visit fee (work quoted on-site)', price:0),
      ]),
    ]),

    // ── SVC013 Carpenter ───────────────────────────────────────────
    HSService(id:'SVC013', name:'Carpenter', icon:'🪚', cat:'Home Services', basePrice:0, groups:[
      HSGroup(key:'visit', title:'Visit / Call-out Price', style:'bhk', items:[
        HSOption(key:'visit', name:'Visit fee (work quoted on-site)', price:0),
      ]),
    ]),

    // ── SVC014 Painter ─────────────────────────────────────────────
    HSService(id:'SVC014', name:'Painter', icon:'🎨', cat:'Home Services', basePrice:0, groups:[
      HSGroup(key:'rooms', title:'With Material — Price per Room', style:'bhk', items:[
        HSOption(key:'pricePerRoom', name:'Per room (base)', price:0),
      ]),
    ]),

    // ── SVC015 CCTV Installation ───────────────────────────────────
    HSService(id:'SVC015', name:'CCTV Installation', icon:'📹', cat:'Home Services', basePrice:0, groups:[
      HSGroup(key:'visit', title:'Visit / Call-out Price', style:'bhk', items:[
        HSOption(key:'visit', name:'Visit fee (work quoted on-site)', price:0),
      ]),
    ]),

    // ── SVC016 Solar Panel Cleaning ────────────────────────────────
    HSService(id:'SVC016', name:'Solar Panel Cleaning', icon:'☀️', cat:'Home Services', basePrice:0, groups:[
      HSGroup(key:'visit', title:'Visit / Call-out Price', style:'bhk', items:[
        HSOption(key:'visit', name:'Visit fee (work quoted on-site)', price:0),
      ]),
    ]),

    // ── SVC017 Car / Bike Wash ─────────────────────────────────────
    HSService(id:'SVC017', name:'Car / Bike Wash', icon:'🚗', cat:'Vehicle Care', basePrice:0, groups:[
      HSGroup(key:'car', title:'Car Wash Prices', style:'task', items:[
        HSOption(key:'exterior',  ico:'🚗', name:'Exterior Car Cleaning',   price:0),
        HSOption(key:'interior',  ico:'🪣', name:'Interior Cleaning',       price:0),
        HSOption(key:'premium',   ico:'✨', name:'Premium Cleaning',        price:0),
        HSOption(key:'finishing', ico:'💎', name:'Final Finishing',         price:0),
      ]),
      HSGroup(key:'cartype', title:'Car Type Surcharge', style:'bhk', items:[
        HSOption(key:'hatchback', name:'Hatchback (base)',     price:0),
        HSOption(key:'sedan',     name:'Sedan',               price:0),
        HSOption(key:'suv',       name:'SUV / MUV',           price:0),
        HSOption(key:'largsuv',   name:'Large SUV / XUV',     price:0),
        HSOption(key:'luxury',    name:'Luxury / Imported',   price:0),
      ]),
      HSGroup(key:'bike', title:'Bike Wash Prices', style:'task', items:[
        HSOption(key:'bike_exterior', ico:'🏍️', name:'Exterior Bike Cleaning',    price:0),
        HSOption(key:'bike_chain',    ico:'⚙️', name:'Chain & Engine Area',       price:0),
        HSOption(key:'bike_seat',     ico:'🪑', name:'Seat & Interior Area',      price:0),
        HSOption(key:'bike_premium',  ico:'✨', name:'Premium Bike Options',      price:0),
      ]),
    ]),

    // ── SVC019 Car & Bike Mechanic ─────────────────────────────────
    HSService(id:'SVC019', name:'Car & Bike Mechanic', icon:'🔧', cat:'Vehicle Care', basePrice:0, groups:[
      HSGroup(key:'visit', title:'Visit / Call-out Price', style:'bhk', items:[
        HSOption(key:'car',  name:'Car visit fee (work quoted on-site)',  price:0),
        HSOption(key:'bike', name:'Bike visit fee (work quoted on-site)', price:0),
      ]),
    ]),

    // ── SVC021 Pest Control ────────────────────────────────────────
    HSService(id:'SVC021', name:'Pest Control', icon:'🪲', cat:'Pest Control', basePrice:0, groups:[
      HSGroup(key:'visit', title:'Visit / Call-out Price', style:'bhk', items:[
        HSOption(key:'visit', name:'Visit fee (work quoted on-site)', price:0),
      ]),
    ]),

    // ── SVC022 Cook / Cooking Person ──────────────────────────────
    HSService(id:'SVC022', name:'Cook / Cooking Person', icon:'👨‍🍳', cat:'Cooking', basePrice:0, groups:[
      HSGroup(key:'svc', title:'Service Type', style:'task', items:[
        HSOption(key:'breakfast', ico:'🌅', name:'Breakfast Cooking',        price:0),
        HSOption(key:'lunch',     ico:'☀️', name:'Lunch Cooking',            price:0),
        HSOption(key:'dinner',    ico:'🌙', name:'Dinner Cooking',           price:0),
        HSOption(key:'twotime',   ico:'🍽️', name:'Two Meals (Lunch+Dinner)', price:0),
        HSOption(key:'fullday',   ico:'🏠', name:'Full Day Cook (3 Meals)',  price:0),
        HSOption(key:'party',     ico:'🎉', name:'Party / Function',         price:0),
        HSOption(key:'tiffin',    ico:'📦', name:'Tiffin (5 days)',          price:0),
        HSOption(key:'monthly',   ico:'📅', name:'Monthly Cook',             price:0),
      ]),
      HSGroup(key:'people', title:'People Surcharge', style:'bhk', items:[
        HSOption(key:'p2', name:'1–2 people', price:0),
        HSOption(key:'p4', name:'3–4 people', price:0),
        HSOption(key:'p6', name:'5–6 people', price:0),
        HSOption(key:'p7', name:'7+ people',  price:0),
      ]),
      HSGroup(key:'style', title:'Cooking Style Surcharge', style:'bhk', items:[
        HSOption(key:'regular',    name:'Regular Home Style', price:0),
        HSOption(key:'restaurant', name:'Restaurant Style',   price:0),
      ]),
    ]),

    // ── SVC023 Men's Haircut ───────────────────────────────────────
    HSService(id:'SVC023', name:"Men's Haircut at Home", icon:'✂️', cat:'Beauty & Wellness', basePrice:0, groups:[
      HSGroup(key:'svc', title:'Select Service', style:'task', items:[
        HSOption(key:'haircut',   ico:'✂️', name:'Haircut',            price:0),
        HSOption(key:'fade',      ico:'💈', name:'Fade / Taper Cut',   price:0),
        HSOption(key:'layer',     ico:'🎨', name:'Layer / Designer',   price:0),
        HSOption(key:'kids',      ico:'👦', name:'Kids Cut',           price:0),
        HSOption(key:'shave',     ico:'🪒', name:'Clean Shave',        price:0),
        HSOption(key:'beardtrim', ico:'🧔', name:'Beard Trim',         price:0),
        HSOption(key:'beardline', ico:'🧔', name:'Beard Shape & Line', price:0),
        HSOption(key:'bearddes',  ico:'👑', name:'Designer Beard',     price:0),
        HSOption(key:'colblack',  ico:'⚫', name:'Colour — Black',     price:0),
        HSOption(key:'colfash',   ico:'🎨', name:'Colour — Fashion',   price:0),
        HSOption(key:'highlights',ico:'✨', name:'Highlights',         price:0),
        HSOption(key:'massage',   ico:'💆', name:'Head Massage',       price:0),
        HSOption(key:'cleanup',   ico:'🧴', name:'Face Cleanup',       price:0),
        HSOption(key:'combo',     ico:'⭐', name:'Grooming Combo',     price:0),
      ]),
    ]),

    // ── SVC024 Women's Haircut & Beauty ───────────────────────────
    HSService(id:'SVC024', name:"Women's Haircut & Beauty", icon:'💇', cat:'Beauty & Wellness', basePrice:0, groups:[
      HSGroup(key:'cut', title:'Haircut', style:'task', items:[
        HSOption(key:'trim',     ico:'✂️', name:'Trim / Basic Cut', price:0),
        HSOption(key:'layer',    ico:'🌊', name:'Layer / Step Cut',  price:0),
        HSOption(key:'uvcut',    ico:'💇', name:'U-Cut / V-Cut',     price:0),
        HSOption(key:'designer', ico:'✨', name:'Designer Cut',      price:0),
      ]),
      HSGroup(key:'hair', title:'Hair Treatments', style:'task', items:[
        HSOption(key:'blowdry',     ico:'💨', name:'Hair Wash & Blow Dry', price:0),
        HSOption(key:'globalcol',   ico:'🎨', name:'Global Colour',        price:0),
        HSOption(key:'highlights',  ico:'✨', name:'Highlights',           price:0),
        HSOption(key:'balayage',    ico:'🌈', name:'Balayage',             price:0),
        HSOption(key:'roottouchup', ico:'🔄', name:'Root Touch-up',        price:0),
      ]),
      HSGroup(key:'thread', title:'Threading', style:'bhk', items:[
        HSOption(key:'eyebrow',  name:'Eyebrow',   price:0),
        HSOption(key:'upperlip', name:'Upper Lip', price:0),
        HSOption(key:'fullface', name:'Full Face', price:0),
      ]),
      HSGroup(key:'wax', title:'Waxing', style:'bhk', items:[
        HSOption(key:'armswax',     name:'Arms',       price:0),
        HSOption(key:'legswax',     name:'Legs',       price:0),
        HSOption(key:'fullbodywax', name:'Full Body',  price:0),
        HSOption(key:'underarms',   name:'Underarms',  price:0),
      ]),
      HSGroup(key:'facial', title:'Facial & Skin', style:'task', items:[
        HSOption(key:'basic',   ico:'🌿', name:'Basic Facial',  price:0),
        HSOption(key:'dtan',    ico:'🌞', name:'D-Tan Facial',  price:0),
        HSOption(key:'fruit',   ico:'🍑', name:'Fruit Facial',  price:0),
        HSOption(key:'gold',    ico:'✨', name:'Gold Facial',   price:0),
        HSOption(key:'antiage', ico:'💎', name:'Anti-Ageing',   price:0),
      ]),
      HSGroup(key:'nail', title:'Nail Care', style:'task', items:[
        HSOption(key:'mani',  ico:'💅', name:'Manicure',    price:0),
        HSOption(key:'pedi',  ico:'🦶', name:'Pedicure',    price:0),
        HSOption(key:'combo', ico:'💆', name:'Mani + Pedi', price:0),
      ]),
      HSGroup(key:'makeup', title:'Makeup', style:'task', items:[
        HSOption(key:'party',  ico:'💄', name:'Party Makeup',  price:0),
        HSOption(key:'bridal', ico:'👰', name:'Bridal Makeup', price:0),
        HSOption(key:'hd',     ico:'🌟', name:'HD / Airbrush', price:0),
      ]),
    ]),

    // ── SVC025 Full Body Massage ───────────────────────────────────
    HSService(id:'SVC025', name:'Full Body Massage', icon:'💆', cat:'Beauty & Wellness', basePrice:0, groups:[
      HSGroup(key:'types', title:'Select Massage Type', style:'task', items:[
        HSOption(key:'swedish',     ico:'💆', name:'Swedish / Relaxation', price:0),
        HSOption(key:'deeptissue',  ico:'💪', name:'Deep Tissue',          price:0),
        HSOption(key:'ayurvedic',   ico:'🌿', name:'Ayurvedic / Abhyanga', price:0),
        HSOption(key:'sports',      ico:'🏃', name:'Sports Massage',       price:0),
        HSOption(key:'reflexology', ico:'🦶', name:'Reflexology (Feet)',   price:0),
        HSOption(key:'aromatherapy',ico:'🌸', name:'Aromatherapy',         price:0),
        HSOption(key:'headneck',    ico:'🧠', name:'Head & Neck',          price:0),
        HSOption(key:'backpain',    ico:'🔙', name:'Back Pain Relief',     price:0),
      ]),
    ]),

    // ── SVC026 Gym / Fitness Trainer ──────────────────────────────
    HSService(id:'SVC026', name:'Gym / Fitness Trainer', icon:'💪', cat:'Beauty & Wellness', basePrice:0, groups:[
      HSGroup(key:'visit', title:'Visit / Call-out Price', style:'bhk', items:[
        HSOption(key:'visit', name:'Trainer visit fee (work quoted on-site)', price:0),
      ]),
    ]),

    // ── SVC027 Doctor Visit ────────────────────────────────────────
    HSService(id:'SVC027', name:'Doctor Visit at Home', icon:'👨‍⚕️', cat:'Health Services', basePrice:0, groups:[
      HSGroup(key:'visit', title:'Visit / Call-out Price', style:'bhk', items:[
        HSOption(key:'visit', name:'Doctor home visit fee', price:0),
      ]),
    ]),

    // ── SVC028 Nurse Visit ─────────────────────────────────────────
    HSService(id:'SVC028', name:'Nurse Visit at Home', icon:'💉', cat:'Health Services', basePrice:0, groups:[
      HSGroup(key:'visit', title:'Visit / Call-out Price', style:'bhk', items:[
        HSOption(key:'visit', name:'Nurse home visit fee', price:0),
      ]),
    ]),

    // ── SVC029 Lab Test Collection ─────────────────────────────────
    HSService(id:'SVC029', name:'Lab Test Collection', icon:'🧪', cat:'Health Services', basePrice:0, groups:[
      HSGroup(key:'visit', title:'Visit / Call-out Price', style:'bhk', items:[
        HSOption(key:'visit', name:'Home collection visit fee', price:0),
      ]),
    ]),

    // ── SVC030 Babysitter / Nanny ──────────────────────────────────
    HSService(id:'SVC030', name:'Babysitter / Nanny', icon:'👶', cat:'Care Services', basePrice:0, groups:[
      HSGroup(key:'care', title:'Care Type', style:'task', items:[
        HSOption(key:'half',      ico:'🌤️', name:'Half Day (4 hrs)',        price:0),
        HSOption(key:'fullday',   ico:'☀️',  name:'Full Day (8–10 hrs)',     price:0),
        HSOption(key:'overnight', ico:'🌙', name:'Overnight (10 PM–8 AM)',  price:0),
        HSOption(key:'event',     ico:'🎉', name:'Event / Party',           price:0),
        HSOption(key:'nanny',     ico:'👩‍🍼',name:'Experienced Nanny',      price:0),
        HSOption(key:'monthly',   ico:'📅', name:'Monthly Nanny',           price:0),
      ]),
      HSGroup(key:'extra', title:'Extra Charges', style:'bhk', items:[
        HSOption(key:'extrachild', name:'Per Extra Child / Day', price:0),
      ]),
    ]),

    // ── SVC031 Elderly Care ────────────────────────────────────────
    HSService(id:'SVC031', name:'Elderly Care', icon:'🧓', cat:'Care Services', basePrice:0, groups:[
      HSGroup(key:'care', title:'Care Package', style:'task', items:[
        HSOption(key:'companion', ico:'💬', name:'Companion Care (4 hrs)',  price:0),
        HSOption(key:'personal',  ico:'🛁', name:'Personal Care (4–6 hrs)', price:0),
        HSOption(key:'fullday',   ico:'☀️', name:'Full Day Care (8 hrs)',   price:0),
        HSOption(key:'nightcare', ico:'🌙', name:'Night Care (10 PM–8 AM)', price:0),
        HSOption(key:'hospital',  ico:'🏥', name:'Hospital Attendant',      price:0),
        HSOption(key:'monthly',   ico:'🗓️', name:'Monthly Plan',            price:0),
      ]),
      HSGroup(key:'needs', title:'Special Needs Add-ons', style:'task', items:[
        HSOption(key:'dementia',  ico:'🧠', name:'Dementia Care',           price:0),
        HSOption(key:'bedridden', ico:'🛏️', name:'Bedridden Patient Care',  price:0),
        HSOption(key:'physio',    ico:'🤸', name:'Physiotherapy Support',   price:0),
        HSOption(key:'diabetes',  ico:'💉', name:'Diabetes / Sugar Care',   price:0),
        HSOption(key:'catheter',  ico:'🩺', name:'Catheter / Medical Care', price:0),
      ]),
    ]),

    // ── SVC032 Gardener ────────────────────────────────────────────
    HSService(id:'SVC032', name:'Gardener', icon:'🌱', cat:'Outdoor', basePrice:0, groups:[
      HSGroup(key:'visit', title:'Visit / Call-out Price', style:'bhk', items:[
        HSOption(key:'visit', name:'Visit fee (work quoted on-site)', price:0),
      ]),
    ]),

    // ── SVC033 Driver ──────────────────────────────────────────────
    HSService(id:'SVC033', name:'Driver', icon:'🚕', cat:'Outdoor', basePrice:0, groups:[
      HSGroup(key:'car', title:'Car Driver', style:'task', items:[
        HSOption(key:'local',      ico:'🏙️', name:'Local / City Trips',       price:0),
        HSOption(key:'fullday',    ico:'☀️',  name:'Full Day Driver (8 hrs)',   price:0),
        HSOption(key:'outstation', ico:'🛣️', name:'Outstation / Long Trip',   price:0),
        HSOption(key:'monthly',    ico:'📅', name:'Monthly Regular Driver',    price:0),
        HSOption(key:'event',      ico:'🎉', name:'Event / Wedding Driver',    price:0),
      ]),
      HSGroup(key:'auto', title:'Auto Driver', style:'task', items:[
        HSOption(key:'local',   ico:'🛺', name:'Local Auto Driving',    price:0),
        HSOption(key:'fullday', ico:'☀️', name:'Full Day Auto Driver',  price:0),
        HSOption(key:'monthly', ico:'📅', name:'Monthly Auto Driver',   price:0),
      ]),
      HSGroup(key:'tempo', title:'Tempo Driver', style:'task', items:[
        HSOption(key:'shifting',   ico:'📦', name:'Goods Shifting / Moving',  price:0),
        HSOption(key:'local',      ico:'🏙️', name:'Local Tempo Driving',      price:0),
        HSOption(key:'outstation', ico:'🛣️', name:'Outstation Tempo Trip',    price:0),
        HSOption(key:'fullday',    ico:'☀️', name:'Full Day Tempo Driver',    price:0),
      ]),
      HSGroup(key:'truck', title:'Truck Driver', style:'task', items:[
        HSOption(key:'shifting',   ico:'🏠', name:'House / Office Shifting', price:0),
        HSOption(key:'goods',      ico:'📦', name:'Goods Transport',          price:0),
        HSOption(key:'outstation', ico:'🛣️', name:'Outstation Truck Trip',   price:0),
        HSOption(key:'fullday',    ico:'☀️', name:'Full Day Truck Driver',   price:0),
      ]),
      HSGroup(key:'bus', title:'Bus Driver', style:'task', items:[
        HSOption(key:'event',      ico:'🎉', name:'Event / Function Bus',  price:0),
        HSOption(key:'staff',      ico:'👔', name:'Staff Pickup & Drop',   price:0),
        HSOption(key:'outstation', ico:'🛣️', name:'Outstation Bus Trip',   price:0),
        HSOption(key:'fullday',    ico:'☀️', name:'Full Day Bus Driver',   price:0),
      ]),
      HSGroup(key:'tractor', title:'Tractor Driver', style:'task', items:[
        HSOption(key:'farm',    ico:'🌾', name:'Farm / Agricultural Work',    price:0),
        HSOption(key:'goods',   ico:'📦', name:'Goods / Material Transport',  price:0),
        HSOption(key:'fullday', ico:'☀️', name:'Full Day Tractor Driver',    price:0),
      ]),
    ]),

    // ── SVC034 Security Guard & Bouncers ──────────────────────────
    HSService(id:'SVC034', name:'Security Guard & Bouncers', icon:'🛡️', cat:'Security', basePrice:0, groups:[
      HSGroup(key:'type', title:'Guard / Bouncer Type', style:'task', items:[
        HSOption(key:'daytime',       ico:'🌤️', name:'Daytime Guard (8-hr shift)',   price:0),
        HSOption(key:'nighttime',     ico:'🌙', name:'Night Guard (8-hr shift)',     price:0),
        HSOption(key:'fullday',       ico:'☀️', name:'Full Day Guard (12-hr shift)', price:0),
        HSOption(key:'event',         ico:'🎉', name:'Event Security Guard',          price:0),
        HSOption(key:'office',        ico:'🏢', name:'Office / Shop Security',        price:0),
        HSOption(key:'bouncer_event', ico:'🥊', name:'Event Bouncer',                 price:0),
        HSOption(key:'bouncer_pub',   ico:'🍺', name:'Pub / Bar / Club Bouncer',      price:0),
        HSOption(key:'bouncer_vip',   ico:'👑', name:'VIP / Personal Bouncer',        price:0),
      ]),
    ]),

  ]; // end services

  // ── Helper Methods ─────────────────────────────────────────────────

  static HSService? getById(String id) {
    try {
      return services.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  static int basePrice(String id) => getById(id)?.basePrice ?? 0;

  // Seed all services to Firebase on first admin login
  static Future<void> seedToFirebase() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('hs_service_prices/SVC001/basePrice')
          .get();
      if (snap.exists) return; // Already seeded

      final Map<String, dynamic> updates = {};
      for (final svc in services) {
        updates['hs_service_prices/${svc.id}'] = _toFirebase(svc);
      }
      await FirebaseDatabase.instance.ref().update(updates);
    } catch (_) {}
  }

  static Map<String, dynamic> _toFirebase(HSService svc) {
    return {
      'id': svc.id,
      'name': svc.name,
      'icon': svc.icon,
      'cat': svc.cat,
      'basePrice': svc.basePrice,
      'status': 'active',
      'groups': svc.groups.map((g) => {
        'key': g.key,
        'title': g.title,
        'style': g.style,
        if (g.showOn != null) 'showOn': g.showOn,
        if (g.info != null) 'info': g.info,
        'items': g.items.map((o) => {
          'key': o.key,
          'name': o.name,
          'ico': o.ico,
          'p': o.price,
        }).toList(),
      }).toList(),
    };
  }

  // Load live prices from Firebase (overrides base prices if admin updated)
  static Future<Map<String, int>> loadLivePrices() async {
    final Map<String, int> prices = {};
    try {
      final snap = await FirebaseDatabase.instance.ref('hs_service_prices').get();
      if (!snap.exists) return prices;
      final data = Map<String, dynamic>.from(snap.value as Map);
      for (final entry in data.entries) {
        final svc = Map<String, dynamic>.from(entry.value as Map);
        final bp = svc['basePrice'];
        if (bp is int) prices[entry.key] = bp;
      }
    } catch (_) {}
    return prices;
  }
}
