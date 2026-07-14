import 'package:flutter/material.dart';
import '../services/provider_api_service.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../utils/theme.dart';
import '../services/hs_catalog.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _pageCtrl = PageController();
  int _currentStep = 0;

  // Step 1 - Personal Info
  final _nameCtrl      = TextEditingController();
  final _phoneCtrl     = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _whatsappCtrl  = TextEditingController();
  final _pwdCtrl       = TextEditingController();
  final _confirmPwdCtrl= TextEditingController();
  final _bioCtrl       = TextEditingController();
  final _idNumCtrl     = TextEditingController();
  String _gender     = 'Male';
  String _experience = '1-2 years';
  String _idType     = 'Aadhaar Card';
  bool _showPwd      = false;

  // Step 2 - Services
  final Set<String> _selectedServices = {}; // stores svcId e.g. 'SVC001'
  Map<String, int> _refPrices = {};          // svcId → lowest reference price
  bool _loadingPrices = true;

  // Step 3 - Location
  double? _lat;
  double? _lng;
  String _address = '';
  bool _detectingLocation = false;
  int _radius = 5; // default 5km radius

  bool _submitting = false;
  String _error = '';
  String _generatedId = '';

  @override
  void initState() {
    super.initState();
    _loadRefPrices();
  }

  Future<void> _loadRefPrices() async {
    try {
      // Load price ranges from MySQL API
      final res = await ProviderApiService.getServicePrices('');
      final Map<String,int> prices = {};
      if (res.isNotEmpty) {
        res.forEach((svcId, grouped) {
          if (grouped is! Map) return;
          final List<int> vals = [];
          (grouped as Map).forEach((_, gv) {
            if (gv is Map) {
              (gv as Map).forEach((_, v) {
                if (v is num && v.toInt() > 0) vals.add(v.toInt());
              });
            }
          });
          if (vals.isNotEmpty) { vals.sort(); prices[svcId] = vals.first; }
        });
      }
      if (mounted) setState(() { _refPrices = prices; _loadingPrices = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingPrices = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose(); _emailCtrl.dispose();
    _whatsappCtrl.dispose(); _pwdCtrl.dispose(); _confirmPwdCtrl.dispose();
    _bioCtrl.dispose(); _idNumCtrl.dispose();
    super.dispose();
  }

  String _generateId() {
    final name = _nameCtrl.text.trim().replaceAll(RegExp(r'[^a-zA-Z]'), '').toUpperCase().padRight(4, 'X').substring(0, 4);
    final phone = _phoneCtrl.text.trim();
    final phonePart = phone.length >= 4 ? phone.substring(phone.length - 4) : phone.padLeft(4, '0');
    return 'HS-PRO-$name$phonePart';
  }

  bool _validateStep1() {
    if (_nameCtrl.text.trim().isEmpty) { setState(() => _error = 'Enter your full name'); return false; }
    if (_phoneCtrl.text.trim().length < 10) { setState(() => _error = 'Enter valid 10-digit phone'); return false; }
    if (!_emailCtrl.text.contains('@')) { setState(() => _error = 'Enter valid email address'); return false; }
    if (_pwdCtrl.text.length < 8) { setState(() => _error = 'Password must be at least 8 characters'); return false; }
    if (_pwdCtrl.text != _confirmPwdCtrl.text) { setState(() => _error = 'Passwords do not match'); return false; }
    if (_idNumCtrl.text.trim().isEmpty) { setState(() => _error = 'Enter your ID proof number'); return false; }
    setState(() => _error = '');
    return true;
  }

  bool _validateStep2() {
    if (_selectedServices.isEmpty) { setState(() => _error = 'Select at least one service'); return false; }
    setState(() => _error = '');
    return true;
  }

  void _nextStep() {
    if (_currentStep == 0 && !_validateStep1()) return;
    if (_currentStep == 1 && !_validateStep2()) return;
    if (_currentStep < 2) {
      setState(() { _currentStep++; _error = ''; });
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _submitRegistration();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() { _currentStep--; _error = ''; });
      _pageCtrl.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  Future<void> _detectLocation() async {
    setState(() => _detectingLocation = true);
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() { _detectingLocation = false; _error = 'Location permission denied'; });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      String addr = '';
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        addr = [p.locality, p.subAdministrativeArea, p.administrativeArea]
            .where((s) => s != null && s.isNotEmpty).join(', ');
      }
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _address = addr;
        _detectingLocation = false;
      });
    } catch (e) {
      setState(() { _detectingLocation = false; _error = 'Could not detect location'; });
    }
  }

  Future<void> _submitRegistration() async {
    setState(() { _submitting = true; _error = ''; });
    try {
      final id = _generateId();

      // Check if already registered
      // Duplicate check handled by MySQL API (unique email constraint)

      // Map selected IDs to full service data — NO hardcoded price
      final services = _selectedServices.map((svcId) {
        final matches = HSCatalog.services.where((sv) => sv.id == svcId).toList();
        final sName = matches.isNotEmpty ? matches.first.name : svcId;
        final sIcon = matches.isNotEmpty ? matches.first.icon : '🔧';
        final sCat  = matches.isNotEmpty ? matches.first.cat  : 'Service';
        return {
          'id':   svcId,
          'name': sName,
          'icon': sIcon,
          'cat':  sCat,
          // price is set by provider AFTER approval in My Services screen
          // min/max stored separately in services/{svcId}
        };
      }).toList();

      // Also save services as a Map for the services_screen to read
      final servicesMap = <String, dynamic>{};
      for (final svcId in _selectedServices) {
        servicesMap[svcId] = {'enabled': true, 'min': 0, 'max': 0};
      }

      final provider = {
        'id':           id,
        'name':         _nameCtrl.text.trim(),
        'phone':        _phoneCtrl.text.trim(),
        'email':        _emailCtrl.text.trim().toLowerCase(),
        'whatsapp':     _whatsappCtrl.text.trim().isNotEmpty ? _whatsappCtrl.text.trim() : _phoneCtrl.text.trim(),
        'password':     _pwdCtrl.text.trim(),
        'gender':       _gender,
        'experience':   _experience,
        'bio':          _bioCtrl.text.trim(),
        'idType':       _idType,
        'idNum':        _idNumCtrl.text.trim(),
        'services':     services,
        'lat':          _lat ?? 0.0,
        'lng':          _lng ?? 0.0,
        'address':      _address,
        'city':         _address.contains(',') ? _address.split(',').last.trim() : _address,
        'radius':       _radius,
        'status':       'pending',
        'available':    false,
        'rating':       0,
        'reviews':      0,
        'totalBookings':0,
        'completedBookings': 0,
        'totalEarned':  0,
        'pendingEarned':0,
        'registeredAt': DateTime.now().toIso8601String(),
        'appliedAt':    DateTime.now().toIso8601String(),
      };

      // Register via MySQL API
      provider['servicesMap'] = servicesMap;
      final success = await ProviderApiService.register(provider);
      if (!success) {
        setState(() { _submitting = false; _error = 'Registration failed. Please try again.'; });
        return;
      }

      setState(() { _submitting = false; _generatedId = id; });
    } catch (e) {
      setState(() { _submitting = false; _error = 'Registration failed. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_generatedId.isNotEmpty) return _buildSuccessScreen();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Register — Step ${_currentStep + 1} of 3'),
        backgroundColor: AppColors.teal,
      ),
      body: Column(
        children: [
          // Progress
          Container(
            color: AppColors.teal,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Row(children: List.generate(3, (i) => Expanded(
              child: Row(children: [
                Expanded(child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= _currentStep ? AppColors.brand : Colors.white30,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
                if (i < 2) const SizedBox(width: 4),
              ]),
            ))),
          ),

          // Steps
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              children: [_buildStep1(), _buildStep2(), _buildStep3()],
            ),
          ),

          // Error
          if (_error.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              color: const Color(0xFFFFF5F5),
              child: Row(children: [
                const Icon(Icons.error_outline, color: Color(0xFFE53E3E), size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(_error, style: const TextStyle(fontSize: 12, color: Color(0xFFE53E3E)))),
              ]),
            ),

          // Buttons
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            color: Colors.white,
            child: Row(children: [
              if (_currentStep > 0) ...[
                OutlinedButton(
                  onPressed: _prevStep,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(80, 52),
                    side: const BorderSide(color: AppColors.teal),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Back', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: ElevatedButton(
                  onPressed: _submitting ? null : _nextStep,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _submitting
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white)))
                      : Text(_currentStep < 2 ? 'Next →' : 'Submit Registration',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Personal Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const Text('Tell us about yourself', style: TextStyle(fontSize: 13, color: AppColors.muted)),
        const SizedBox(height: 20),

        _field('FULL NAME *', _nameCtrl, 'Your full name', Icons.person_rounded),
        const SizedBox(height: 14),
        _field('MOBILE NUMBER *', _phoneCtrl, '10-digit mobile', Icons.phone_rounded, keyboard: TextInputType.phone),
        const SizedBox(height: 14),
        _field('EMAIL ADDRESS *', _emailCtrl, 'your@email.com', Icons.email_rounded, keyboard: TextInputType.emailAddress),
        const SizedBox(height: 14),
        _field('WHATSAPP NUMBER', _whatsappCtrl, 'Same as mobile if same', Icons.chat_rounded, keyboard: TextInputType.phone),
        const SizedBox(height: 14),

        // Gender
        _dropdownField('GENDER', _gender, ['Male', 'Female', 'Other'],
          (v) => setState(() => _gender = v!)),
        const SizedBox(height: 14),

        // Experience
        _dropdownField('EXPERIENCE *', _experience,
          ['Less than 1 year', '1-2 years', '3-5 years', '5-10 years', '10+ years'],
          (v) => setState(() => _experience = v!)),
        const SizedBox(height: 14),

        // Password
        _label('CREATE PASSWORD *'),
        const SizedBox(height: 6),
        TextField(
          controller: _pwdCtrl,
          obscureText: !_showPwd,
          decoration: InputDecoration(
            hintText: 'Min 8 characters',
            prefixIcon: const Icon(Icons.lock_rounded, color: AppColors.muted, size: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixIcon: IconButton(
              icon: Icon(_showPwd ? Icons.visibility_off : Icons.visibility, color: AppColors.muted),
              onPressed: () => setState(() => _showPwd = !_showPwd)),
          ),
        ),
        const SizedBox(height: 14),

        _label('CONFIRM PASSWORD *'),
        const SizedBox(height: 6),
        TextField(
          controller: _confirmPwdCtrl,
          obscureText: true,
          decoration: InputDecoration(
            hintText: 'Re-enter password',
            prefixIcon: const Icon(Icons.lock_rounded, color: AppColors.muted, size: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 14),

        _label('SHORT BIO (optional)'),
        const SizedBox(height: 6),
        TextField(
          controller: _bioCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'e.g. Professional house maid with 5 years experience...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 14),

        // ID Proof
        _dropdownField('ID PROOF TYPE *', _idType,
          ['Aadhaar Card', 'PAN Card', 'Voter ID', 'Driving License', 'Passport'],
          (v) => setState(() => _idType = v!)),
        const SizedBox(height: 14),
        _field('ID NUMBER *', _idNumCtrl, 'Enter ID number', Icons.badge_rounded),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Select Your Services', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const Text('Choose services you can provide', style: TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(10)),
              child: Text('${_selectedServices.length} of ${HSCatalog.services.length} services selected',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.teal)),
            ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: HSCatalog.services.length,
            itemBuilder: (_, i) {
              // Group by category — show category header
              final svcs = HSCatalog.services;
              final svc = svcs[i];
              final sel = _selectedServices.contains(svc.id);
              final showHeader = i == 0 || svcs[i-1].cat != svc.cat;
              final ref = _refPrices[svc.id];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category header
                  if (showHeader) ...[
                    if (i > 0) const SizedBox(height: 8),
                    Container(
                      margin: const EdgeInsets.only(bottom: 8, top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.teal.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8)),
                      child: Text(svc.cat,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                          color: AppColors.teal, letterSpacing: 0.5))),
                  ],
                  // Service card
                  GestureDetector(
                    onTap: () => setState(() {
                      if (sel) _selectedServices.remove(svc.id);
                      else _selectedServices.add(svc.id);
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.tealSoft : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sel ? AppColors.teal : AppColors.line,
                          width: sel ? 2 : 1),
                      ),
                      child: Row(children: [
                        // Icon
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: sel ? AppColors.teal.withOpacity(0.12) : AppColors.bg,
                            borderRadius: BorderRadius.circular(10)),
                          child: Center(child: Text(svc.icon,
                            style: const TextStyle(fontSize: 20)))),
                        const SizedBox(width: 12),
                        // Name + price
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(svc.name,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                                color: sel ? AppColors.teal : AppColors.ink)),
                            if (ref != null && ref > 0) ...[
                              const SizedBox(height: 2),
                              Text('Reference: from ₹$ref',
                                style: const TextStyle(fontSize: 11,
                                  color: AppColors.brand, fontWeight: FontWeight.w600)),
                            ] else if (_loadingPrices) ...[
                              const SizedBox(height: 2),
                              const Text('Loading price...',
                                style: TextStyle(fontSize: 11, color: AppColors.muted)),
                            ],
                          ])),
                        // Checkbox
                        Container(
                          width: 24, height: 24,
                          decoration: BoxDecoration(
                            color: sel ? AppColors.teal : Colors.transparent,
                            border: Border.all(
                              color: sel ? AppColors.teal : AppColors.line,
                              width: 2),
                            borderRadius: BorderRadius.circular(6)),
                          child: sel ? const Icon(Icons.check,
                            color: Colors.white, size: 14) : null),
                      ]),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Your Location', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const Text('Help customers find you nearby', style: TextStyle(fontSize: 13, color: AppColors.muted)),
        const SizedBox(height: 24),

        // Radius picker
        const Text('Service Radius', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line)),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('How far will you travel?',
                style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              Text('$_radius km',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.teal)),
            ]),
            Slider(
              value: _radius.toDouble(),
              min: 1, max: 30,
              divisions: 29,
              activeColor: AppColors.teal,
              onChanged: (v) => setState(() => _radius = v.toInt()),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('1 km', style: TextStyle(fontSize: 11, color: AppColors.muted)),
              const Text('30 km', style: TextStyle(fontSize: 11, color: AppColors.muted)),
            ]),
          ])),
        const SizedBox(height: 20),

        // Detect GPS
        GestureDetector(
          onTap: _detectingLocation ? null : _detectLocation,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _lat != null ? AppColors.greenSoft : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _lat != null ? AppColors.green : AppColors.teal),
            ),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _lat != null ? AppColors.green.withOpacity(0.15) : AppColors.tealSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _detectingLocation
                    ? const Center(child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal)))
                    : Icon(_lat != null ? Icons.check_circle_rounded : Icons.my_location_rounded,
                        color: _lat != null ? AppColors.green : AppColors.teal, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_lat != null ? 'Location Detected!' : 'Detect My Location',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: _lat != null ? AppColors.green : AppColors.teal)),
                Text(_lat != null ? _address : 'Tap to detect using GPS',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ])),
            ]),
          ),
        ),

        const SizedBox(height: 24),

        // Summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.tealSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.teal.withOpacity(0.3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('REGISTRATION SUMMARY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.teal, letterSpacing: 0.5)),
            const SizedBox(height: 12),
            _summaryRow('Name', _nameCtrl.text),
            _summaryRow('Phone', _phoneCtrl.text),
            _summaryRow('Email', _emailCtrl.text),
            _summaryRow('Services', '${_selectedServices.length} of ${HSCatalog.services.length} selected'),
            _summaryRow('Your ID will be', _generateId()),
          ]),
        ),

        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.yellow.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.yellow.withOpacity(0.3)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline_rounded, color: AppColors.yellow, size: 18),
            SizedBox(width: 10),
            Expanded(child: Text(
              'After registration, admin will review your profile. You will be notified once approved.',
              style: TextStyle(fontSize: 13, color: AppColors.ink2, height: 1.4),
            )),
          ]),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildSuccessScreen() {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              const Text('⏳', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 20),
              const Text('Registration Submitted!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 8),
              const Text('Your application has been received.\nWaiting for Admin Approval.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.muted, height: 1.5)),
              const SizedBox(height: 24),

              // Provider ID
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
                ),
                child: Column(children: [
                  const Text('YOUR PROVIDER ID', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 0.8)),
                  const SizedBox(height: 8),
                  Text(_generatedId, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.teal)),
                  const SizedBox(height: 6),
                  const Text('Save this — you\'ll need it to login after approval',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ]),
              ),

              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.brand.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.brand.withOpacity(0.3)),
                ),
                child: Column(children: [
                  const Text('For faster approval, contact Admin', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 6),
                  const Text('📞 8985849710', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.brand)),
                  const Text('Call or WhatsApp', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ]),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Go to Login', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint, IconData icon,
      {TextInputType keyboard = TextInputType.text}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(label),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        keyboardType: keyboard,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: AppColors.muted, size: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ]);
  }

  Widget _dropdownField(String label, String value, List<String> options, ValueChanged<String?> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(label),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
        onChanged: onChanged,
      ),
    ]);
  }

  Widget _label(String text) => Text(text,
    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.5));

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink))),
      ]),
    );
  }
}
