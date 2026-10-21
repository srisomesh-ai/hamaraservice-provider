import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/provider_api_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../utils/theme.dart';
import '../services/hs_catalog.dart';
import '../utils/support_contact.dart';
import 'email_otp_screen.dart';
import 'login_screen.dart';
import 'map_picker_screen.dart';
import 'pending_approval_screen.dart';
import '../widgets/ui.dart';

class RegisterScreen extends StatefulWidget {
  final String prefillEmail;
  const RegisterScreen({
    super.key,
    this.prefillEmail = '',
  });
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
  String _idType     = 'Aadhaar';
  File? _photo;      // optional, uploaded after the automatic login
  bool _showPwd      = false;

  // Step 2 - Services
  final Set<String> _selectedServices = {}; // stores svcId e.g. 'SVC001'
  Map<String, int> _refPrices = {};          // svcId → lowest reference price
  bool _loadingPrices = true;

  // Step 3 - Location
  double? _lat;
  double? _lng;
  String _address = '';
  String _city = '';
  bool _detectingLocation = false;
  int _radius = 5; // default 5km radius
  bool _pinned = false; // set on the map → sent as base_lat/base_lng
  int _locSeq = 0;      // bumps on every location source; stale GPS fixes are dropped

  bool _submitting = false;
  String _error = '';
  String _generatedId = '';

  // Areas you serve (required, like the website)
  final List<String> _areas = [];
  final _areaCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-fill email from the login screen (never the password)
    if (widget.prefillEmail.isNotEmpty) {
      _emailCtrl.text = widget.prefillEmail;
    }
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
          grouped.forEach((_, gv) {
            if (gv is Map) {
              gv.forEach((_, v) {
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
    _areaCtrl.dispose(); _addrCtrl.dispose();
    super.dispose();
  }

  void _addArea() {
    final a = _areaCtrl.text.trim();
    if (a.isEmpty) return;
    setState(() {
      if (!_areas.any((x) => x.toLowerCase() == a.toLowerCase())) _areas.add(a);
      _areaCtrl.clear();
    });
  }

  Future<void> _pickPhoto() async {
    final img = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 600, maxHeight: 600);
    if (img != null && mounted) setState(() => _photo = File(img.path));
  }

  bool _validateStep1() {
    if (_nameCtrl.text.trim().isEmpty) { setState(() => _error = 'Enter your full name'); return false; }
    final phone = _normPhone(_phoneCtrl.text);
    if (!_phoneRe.hasMatch(phone)) { setState(() => _error = 'Enter a valid 10-digit mobile number (starts with 6-9)'); return false; }
    final wa = _normPhone(_whatsappCtrl.text);
    if (_whatsappCtrl.text.trim().isNotEmpty && !_phoneRe.hasMatch(wa)) { setState(() => _error = 'Enter a valid 10-digit WhatsApp number'); return false; }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_emailCtrl.text.trim())) { setState(() => _error = 'Enter a valid email address'); return false; }
    if (_pwdCtrl.text.length < 8) { setState(() => _error = 'Password must be at least 8 characters'); return false; }
    if (_pwdCtrl.text != _confirmPwdCtrl.text) { setState(() => _error = 'Passwords do not match'); return false; }
    setState(() => _error = '');
    return true;
  }

  static final RegExp _phoneRe = RegExp(r'^[6-9]\d{9}$');

  /// Keeps the last 10 digits (strips +91 / spaces / dashes).
  String _normPhone(String v) {
    final d = v.replaceAll(RegExp(r'\D'), '');
    return d.length > 10 ? d.substring(d.length - 10) : d;
  }

  bool _validateStep3() {
    if (_addrCtrl.text.trim().isEmpty && _address.isEmpty) { setState(() => _error = 'Enter your address'); return false; }
    if (_lat == null || _lng == null) { setState(() => _error = 'Location not captured yet — tap the location card'); return false; }
    if (_areaCtrl.text.trim().isNotEmpty) _addArea();
    if (_areas.isEmpty) { setState(() => _error = 'Add at least one area you serve'); return false; }
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
      if (!_validateStep3()) return;
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
    final seq = ++_locSeq;
    setState(() { _detectingLocation = true; _error = ''; });

    // 1. Location services + permission
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (!mounted || seq != _locSeq) return;
      setState(() { _detectingLocation = false; _error = 'Turn on Location (GPS) and tap Detect again'; });
      await Geolocator.openLocationSettings();
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (!mounted || seq != _locSeq) return;
      setState(() { _detectingLocation = false; _error = 'Location permission is needed to find jobs near you. Allow it in Settings.'; });
      if (permission == LocationPermission.deniedForever) await Geolocator.openAppSettings();
      return;
    }

    // 2. Position — with a timeout, falling back to the last known fix
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium, timeLimit: const Duration(seconds: 20));
    } catch (_) {
      try { pos = await Geolocator.getLastKnownPosition(); } catch (_) {}
    }
    if (pos == null) {
      if (!mounted || seq != _locSeq) return;
      setState(() { _detectingLocation = false; _error = 'Could not get your location. Move near a window and tap Detect again.'; });
      return;
    }

    // 3. Address lookup is best effort — never lose the GPS fix because of it
    String addr = '';
    String city = '';
    try {
      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        addr = [p.subLocality, p.locality, p.subAdministrativeArea, p.administrativeArea]
            .where((s) => s != null && s.isNotEmpty).join(', ');
        // City = locality (fallback: district). Never the state.
        city = (p.locality?.isNotEmpty == true)
            ? p.locality!
            : (p.subAdministrativeArea ?? '');
      }
    } catch (_) {}
    // A map pin chosen while GPS was still searching wins over this late fix.
    if (!mounted || seq != _locSeq) return;
    setState(() {
      _pinned = false;
      _lat = pos!.latitude;
      _lng = pos.longitude;
      _address = addr.isNotEmpty
          ? addr
          : '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      _city = city;
      _detectingLocation = false;
      if (_addrCtrl.text.trim().isEmpty && addr.isNotEmpty) _addrCtrl.text = addr;
    });
  }

  Future<void> _pinOnMap() async {
    final r = await MapPickerScreen.open(context,
        lat: _lat, lng: _lng, radiusKm: _radius,
        title: 'Where do you work from?',
        confirmText: 'Use this location & range');
    if (r == null || !mounted) return;
    _locSeq++; // drop any GPS fix still in flight
    setState(() {
      _pinned = true;
      _detectingLocation = false;
      _lat = r.lat;
      _lng = r.lng;
      _radius = r.radiusKm;
      if (r.city.isNotEmpty) _city = r.city;
      _address = r.address.isNotEmpty
          ? r.address
          : '${r.lat.toStringAsFixed(4)}, ${r.lng.toStringAsFixed(4)}';
      if (_addrCtrl.text.trim().isEmpty && r.address.isNotEmpty) _addrCtrl.text = r.address;
      _error = '';
    });
  }

  // otp_token from EmailOtpScreen — reused while valid, so a retry after an
  // error doesn't need a new code.
  String _otpToken = '';
  String _otpEmail = '';
  DateTime _otpUntil = DateTime(2000);

  /// Verifies the e-mail with a 6-digit code (otp.php). Returns the
  /// otp_token, or null (error shown / user went back to change the email).
  Future<String?> _verifyEmail(String email) async {
    if (_otpToken.isNotEmpty && _otpEmail == email && DateTime.now().isBefore(_otpUntil)) {
      return _otpToken;
    }
    int wait;
    try {
      wait = await ProviderApiService.sendEmailOtp(email);
    } on ApiException catch (e) {
      if (mounted) setState(() { _submitting = false; _error = e.message; });
      return null;
    }
    if (!mounted) return null;
    setState(() => _submitting = false);
    final token = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => EmailOtpScreen(email: email, resendAfter: wait)));
    if (!mounted) return null;
    if (token == null || token.isEmpty) {
      // "Change email" → back to step 1 with everything still filled in
      if (_currentStep != 0) {
        setState(() { _currentStep = 0; _error = 'Update your email, then continue'; });
        _pageCtrl.jumpToPage(0);
      }
      return null;
    }
    _otpToken = token;
    _otpEmail = email;
    _otpUntil = DateTime.now().add(const Duration(minutes: 28));
    return token;
  }

  Future<void> _submitRegistration() async {
    setState(() { _submitting = true; _error = ''; });

    final email = _emailCtrl.text.trim().toLowerCase();
    final otpToken = await _verifyEmail(email);
    if (otpToken == null || !mounted) return;
    setState(() { _submitting = true; _error = ''; });

    final services = _selectedServices.map((svcId) {
      final matches = HSCatalog.services.where((sv) => sv.id == svcId).toList();
      return {
        'id':   svcId,
        'name': matches.isNotEmpty ? matches.first.name : svcId,
        'icon': matches.isNotEmpty ? matches.first.icon : '🔧',
        'cat':  matches.isNotEmpty ? matches.first.cat  : 'Service',
        // min/max prices are set by the provider after approval (My Services)
      };
    }).toList();

    final phone = _normPhone(_phoneCtrl.text);
    final wa = _normPhone(_whatsappCtrl.text);
    final res = await ProviderApiService.register({
      'name':       _nameCtrl.text.trim(),
      'phone':      phone,
      'email':      _emailCtrl.text.trim().toLowerCase(),
      'whatsapp':   wa.isNotEmpty ? wa : phone,
      'password':   _pwdCtrl.text,
      'gender':     _gender,
      'experience': _experience,
      'bio':        _bioCtrl.text.trim(),
      'id_type':    _idType,
      'id_number':  _idNumCtrl.text.trim(),
      'address':    _addrCtrl.text.trim().isNotEmpty ? _addrCtrl.text.trim() : _address,
      'city':       _city,
      'lat':        _lat ?? 0.0,
      'lng':        _lng ?? 0.0,
      'radius_km':  _radius,
      if (_pinned) 'base_lat': _lat,
      if (_pinned) 'base_lng': _lng,
      'areas':      _areas,
      'services':   services,
      'otp_token':  otpToken,
    });
    if (!mounted) return;
    if (!res.ok) {
      if (res.error.contains('verif')) _otpToken = ''; // expired → verify again
      setState(() { _submitting = false; _error = res.error; });
      return;
    }
    final id = '${res.map?['id'] ?? ''}';
    // Website: log in automatically (pending providers get a token), upload
    // the photo, then show the "Application Under Review" screen.
    final lr = await ProviderApiService.login(_emailCtrl.text.trim().toLowerCase(), _pwdCtrl.text);
    if (lr.ok && _photo != null) {
      try { await ProviderApiService.uploadPhoto(_photo!); } catch (_) {}
    }
    if (!mounted) return;
    if (lr.ok) {
      showSnack(context, '✅ Registered! Waiting for approval', tone: Tone.success);
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(
          builder: (_) => PendingApprovalScreen(
              name: _nameCtrl.text.trim(), email: _emailCtrl.text.trim().toLowerCase(), submitted: true)),
          (_) => false);
      return;
    }
    setState(() { _submitting = false; _generatedId = id.isNotEmpty ? id : 'Submitted'; });
  }

  @override
  Widget build(BuildContext context) {
    if (_generatedId.isNotEmpty) return _buildSuccessScreen();

    return PopScope(
      canPop: _currentStep == 0,
      onPopInvoked: (didPop) { if (!didPop) _prevStep(); },
      child: _buildForm());
  }

  Widget _buildForm() {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(const ['Your Details', 'Your Services', 'Location & Area'][_currentStep]),
          Text('Step ${_currentStep + 1} of 3',
              style: const TextStyle(fontSize: 12.5, color: Colors.white70, fontWeight: FontWeight.w400)),
        ]),
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
                      : Text(_currentStep < 2 ? 'Continue →' : 'Submit Application ✓',
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
        Center(
          child: InkWell(
            onTap: _pickPhoto,
            customBorder: const CircleBorder(),
            child: CircleAvatar(
              radius: 44,
              backgroundColor: AppColors.tealSoft,
              backgroundImage: _photo != null ? FileImage(_photo!) : null,
              child: _photo == null
                  ? const Icon(Icons.add_a_photo_outlined, color: AppColors.teal, size: 30)
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text('Add your photo (recommended)', style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ),
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
        _dropdownField('GENDER', _gender, ['Male', 'Female'],
          (v) => setState(() => _gender = v!)),
        const SizedBox(height: 14),

        // Experience
        _dropdownField('EXPERIENCE *', _experience,
          ['0-1 years', '1-2 years', '3-5 years', '5+ years'],
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
        _dropdownField('ID TYPE', _idType,
          ['Aadhaar', 'PAN', 'Voter ID', 'Driving License'],
          (v) => setState(() => _idType = v!)),
        const SizedBox(height: 14),
        _field('ID NUMBER', _idNumCtrl, 'Enter ID number', Icons.badge_rounded),
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
                Text(_lat != null ? (_pinned ? '📌 Location pinned · $_radius km range' : 'Location Detected!') : 'Detect My Location',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: _lat != null ? AppColors.green : AppColors.teal)),
                Text(_lat != null ? _address : 'Tap to detect using GPS',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ])),
            ]),
          ),
        ),

        const SizedBox(height: 12),

        // Map pin + range
        OutlinedButton.icon(
          onPressed: _pinOnMap,
          icon: const Icon(Icons.map_rounded, color: AppColors.teal, size: 20),
          label: Text(_pinned ? 'Change location & range on map' : 'Adjust location & range on map',
              style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            side: const BorderSide(color: AppColors.teal),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),

        const SizedBox(height: 20),
        TextField(
          controller: _addrCtrl,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Full Address *', alignLabelWithHint: true),
        ),
        const SizedBox(height: 20),
        const Text('Areas You Serve *', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 4),
        const Text('Add the localities where you want jobs — customers in these areas will find you',
            style: TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 10),
        TextField(
          controller: _areaCtrl,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => _addArea(),
          decoration: InputDecoration(
            labelText: 'Area name',
            hintText: 'e.g. Gajuwaka, Sheelanagar…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(icon: const Icon(Icons.add_circle_rounded), onPressed: _addArea),
          ),
        ),
        const SizedBox(height: 10),
        if (_areas.isEmpty)
          const Text('No areas added yet', style: TextStyle(fontSize: 12, color: AppColors.muted))
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < _areas.length; i++)
              InputChip(label: Text(_areas[i]), onDeleted: () => setState(() => _areas.removeAt(i))),
          ]),
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
            _summaryRow('City', _city.isNotEmpty ? _city : '—'),
            _summaryRow('Range', '$_radius km${_pinned ? ' · pinned on map' : ''}'),
            _summaryRow('Areas', _areas.isEmpty ? '—' : _areas.join(', ')),
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
                  const Text('Log in with your email and password once approved',
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
                  const Text('For faster approval, contact support', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () => openSupport(context,
                        providerId: _generatedId == 'Submitted' ? '' : _generatedId,
                        extra: 'I just registered (${_emailCtrl.text.trim()}) and am waiting for approval.'),
                    icon: const Icon(Icons.support_agent_rounded, size: 18, color: Colors.white),
                    label: const Text('Contact support',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      minimumSize: const Size(200, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ]),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pushAndRemoveUntil(context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false),
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
