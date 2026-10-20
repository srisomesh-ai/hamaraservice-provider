import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/provider_api_service.dart';
import '../utils/parse.dart';
import '../utils/support_contact.dart';
import '../utils/theme.dart';
import '../widgets/ui.dart';
import 'job_history_screen.dart';
import 'map_picker_screen.dart';
import 'profile_edit_screen.dart';
import 'support_screen.dart';

/// Profile tab — same sections as the website "Profile & Payment" page:
/// photo, payment setup (UPI), service location & range (map), areas you
/// serve, account (phone/email, logout) plus ratings, job history and support.
class ProfileTab extends StatefulWidget {
  final String providerId;
  final Map<String, dynamic> profile;
  final bool demo;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onOpenReviews;
  final VoidCallback onLogout;
  const ProfileTab({
    super.key,
    required this.providerId,
    required this.profile,
    this.demo = false,
    required this.onChanged,
    required this.onOpenReviews,
    required this.onLogout,
  });
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

/// `areas` arrives as a JSON string ('["Gajuwaka"]') or a list.
List<String> parseAreas(dynamic v) {
  dynamic d = v;
  if (d is String) {
    final s = d.trim();
    if (s.isEmpty) return [];
    try {
      d = jsonDecode(s);
    } catch (_) {
      return s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
  }
  if (d is List) return d.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList();
  return [];
}

class _ProfileTabState extends State<ProfileTab> {
  final _upiCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  List<String> _areas = [];
  bool _savingUpi = false;
  bool _savingAreas = false;
  bool _savingLoc = false;
  bool _uploading = false;
  File? _newPhoto;

  Map<String, dynamic> get _p => widget.profile;

  @override
  void initState() {
    super.initState();
    _upiCtrl.text = str(_p['upi_id']);
    _areas = parseAreas(_p['areas']);
  }

  @override
  void didUpdateWidget(ProfileTab old) {
    super.didUpdateWidget(old);
    if (str(old.profile['upi_id']) != str(_p['upi_id']) && !_savingUpi) {
      _upiCtrl.text = str(_p['upi_id']);
    }
    if (jsonEncode(parseAreas(old.profile['areas'])) != jsonEncode(parseAreas(_p['areas'])) && !_savingAreas) {
      _areas = parseAreas(_p['areas']);
    }
  }

  @override
  void dispose() {
    _upiCtrl.dispose();
    _areaCtrl.dispose();
    super.dispose();
  }

  void _changed(Map<String, dynamic> patch) {
    final updated = {..._p, ...patch};
    ProviderApiService.cacheProvider(updated);
    widget.onChanged(updated);
  }

  Future<void> _changePhoto() async {
    if (widget.demo || _uploading) return;
    final img = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 600, maxHeight: 600);
    if (img == null || !mounted) return;
    setState(() { _uploading = true; _newPhoto = File(img.path); });
    final res = await ProviderApiService.uploadPhoto(File(img.path));
    if (!mounted) return;
    setState(() => _uploading = false);
    if (res.ok) {
      showSnack(context, '📷 Photo saved', tone: Tone.success);
      final ph = str(res.map?['photo']);
      if (ph.isNotEmpty) _changed({'photo': ph});
    } else if (!res.unauthorized) {
      setState(() => _newPhoto = null);
      showSnack(context, res.error.isNotEmpty ? res.error : 'Upload failed', tone: Tone.error);
    }
  }

  Future<void> _saveUpi() async {
    final u = _upiCtrl.text.trim();
    if (u.isNotEmpty && !u.contains('@')) {
      showSnack(context, 'UPI ID must contain @ (e.g. name@ybl)', tone: Tone.error);
      return;
    }
    if (widget.demo) return;
    FocusScope.of(context).unfocus();
    setState(() => _savingUpi = true);
    final res = await ProviderApiService.updateProfile({'upi_id': u});
    if (!mounted) return;
    setState(() => _savingUpi = false);
    if (res.ok) {
      showSnack(context, '💳 UPI saved — customers can now pay you', tone: Tone.success);
      _changed({'upi_id': u});
    } else if (!res.unauthorized) {
      showSnack(context, res.error.isNotEmpty ? res.error : 'Failed', tone: Tone.error);
    }
  }

  void _addArea() {
    final a = _areaCtrl.text.trim();
    if (a.isEmpty) return;
    setState(() {
      if (!_areas.any((x) => x.toLowerCase() == a.toLowerCase())) _areas.add(a);
      _areaCtrl.clear();
    });
  }

  Future<void> _saveAreas() async {
    if (_areaCtrl.text.trim().isNotEmpty) _addArea();
    if (_areas.isEmpty) {
      showSnack(context, 'Add at least one area', tone: Tone.error);
      return;
    }
    if (widget.demo) return;
    FocusScope.of(context).unfocus();
    setState(() => _savingAreas = true);
    final value = jsonEncode(_areas);
    final res = await ProviderApiService.updateProfile({'areas': value});
    if (!mounted) return;
    setState(() => _savingAreas = false);
    if (res.ok) {
      showSnack(context, '📍 Areas updated', tone: Tone.success);
      _changed({'areas': value});
    } else if (!res.unauthorized) {
      showSnack(context, res.error.isNotEmpty ? res.error : 'Failed', tone: Tone.error);
    }
  }

  bool get _pinned => toDouble(_p['base_lat']) != 0 && toDouble(_p['base_lng']) != 0;

  Future<void> _pinServiceArea() async {
    if (_savingLoc || widget.demo) return;
    double? pick(String a, String b) {
      final v = toDouble(_p[a]);
      return v != 0 ? v : (toDouble(_p[b]) != 0 ? toDouble(_p[b]) : null);
    }
    final r = await MapPickerScreen.open(context,
        lat: pick('base_lat', 'lat'),
        lng: pick('base_lng', 'lng'),
        radiusKm: toInt(_p['radius_km'], 5),
        title: 'Your service location & range',
        confirmText: 'Save location & range');
    if (r == null || !mounted) return;
    final body = <String, dynamic>{
      'base_lat': r.lat,
      'base_lng': r.lng,
      'radius_km': r.radiusKm,
      if (r.address.isNotEmpty) 'address': r.address,
      if (r.city.isNotEmpty) 'city': r.city,
    };
    setState(() => _savingLoc = true);
    final res = await ProviderApiService.updateProfile(body);
    if (!mounted) return;
    setState(() => _savingLoc = false);
    if (!res.ok) {
      if (!res.unauthorized) showSnack(context, res.error.isNotEmpty ? res.error : 'Save failed', tone: Tone.error);
      return;
    }
    showSnack(context, '✅ Location & ${r.radiusKm} km range saved', tone: Tone.success);
    _changed(body);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final name = str(_p['name'], 'Provider');
    final rating = toDouble(_p['rating']);
    final reviews = toInt(_p['review_count']);
    final km = toInt(_p['radius_km'], 5);
    final addr = str(_p['address']);
    final status = str(_p['status'], 'pending');

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Edit profile',
            icon: const Icon(Icons.edit_outlined),
            onPressed: widget.demo
                ? null
                : () async {
                    final r = await Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ProfileEditScreen(providerId: widget.providerId, providerData: _p)));
                    if (r == true) widget.onChanged(_p);
                  },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                GestureDetector(
                  onTap: _changePhoto,
                  child: Stack(children: [
                    _newPhoto != null
                        ? CircleAvatar(radius: 36, backgroundImage: FileImage(_newPhoto!))
                        : Avatar(name: name, photo: photoUrl(_p['photo']), radius: 36),
                    Positioned(
                      right: 0, bottom: 0,
                      child: Container(
                        width: 26, height: 26,
                        decoration: BoxDecoration(
                            color: AppColors.teal,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2)),
                        child: _uploading
                            ? const Padding(
                                padding: EdgeInsets.all(5),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.photo_camera_rounded, size: 13, color: Colors.white),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(widget.providerId, style: t.bodySmall),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      StatusBadge(status),
                      InkWell(
                        onTap: widget.onOpenReviews,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF5A623)),
                          const SizedBox(width: 2),
                          Text(rating > 0 ? '${rating.toStringAsFixed(1)} ($reviews)' : 'New',
                              style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink)),
                        ]),
                      ),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),

          const SectionTitle('Payment setup'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _upiCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Your UPI ID',
                    hintText: 'yourname@ybl / @paytm / @oksbi',
                    helperText: 'Default UPI ID for withdrawing your earnings',
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                BigButton('Save UPI', busy: _savingUpi, onPressed: _saveUpi),
              ]),
            ),
          ),

          const SectionTitle('Service location & range'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ListTile(
                leading: IconTile(_pinned ? Icons.push_pin_outlined : Icons.my_location_rounded),
                title: Text('${_pinned ? 'Pinned location' : 'Live location'} · range $km km',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: addr.isNotEmpty ? Text(addr, maxLines: 2, overflow: TextOverflow.ellipsis) : null,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  BigButton('Set location & range on map',
                      icon: Icons.map_outlined, outlined: true, busy: _savingLoc, onPressed: _pinServiceArea),
                  const SizedBox(height: 8),
                  Text("You get jobs within this range of your pinned location. "
                      "If you don't pin one, your current live location is used.",
                      style: t.bodySmall),
                ]),
              ),
            ]),
          ),

          const SectionTitle('Areas you serve'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _areaCtrl,
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _addArea(),
                  decoration: InputDecoration(
                    labelText: 'Add more areas…',
                    hintText: 'e.g. Gajuwaka, Sheelanagar',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(icon: const Icon(Icons.add_circle_rounded), onPressed: _addArea),
                  ),
                ),
                const SizedBox(height: 12),
                if (_areas.isEmpty)
                  Text('No areas added yet', style: t.bodySmall)
                else
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (var i = 0; i < _areas.length; i++)
                      InputChip(
                        label: Text(_areas[i]),
                        avatar: const Icon(Icons.place_outlined, size: 16, color: AppColors.teal),
                        onDeleted: () => setState(() => _areas.removeAt(i)),
                      ),
                  ]),
                const SizedBox(height: 14),
                BigButton('Save Areas', busy: _savingAreas, color: AppColors.brand, onPressed: _saveAreas),
              ]),
            ),
          ),

          const SectionTitle('More'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              ListTile(
                leading: const IconTile(Icons.star_outline_rounded, color: Color(0xFFE5A100)),
                title: const Text('My ratings & reviews'),
                subtitle: Text(rating > 0
                    ? '⭐ ${rating.toStringAsFixed(1)} ($reviews review${reviews == 1 ? '' : 's'})'
                    : 'New provider — no reviews yet'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: widget.onOpenReviews,
              ),
              const Divider(indent: 72),
              ListTile(
                leading: const IconTile(Icons.history_rounded),
                title: const Text('Job history'),
                subtitle: const Text('Active, completed and cancelled jobs'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: widget.demo
                    ? null
                    : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JobHistoryScreen())),
              ),
              const Divider(indent: 72),
              ListTile(
                leading: const IconTile(Icons.chat_outlined, color: Color(0xFF128C4A)),
                title: const Text('WhatsApp support'),
                subtitle: const Text('Chat with HamaraService'),
                trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                onTap: () => openSupport(context,
                    providerId: widget.providerId, extra: 'Provider ID ${widget.providerId}.'),
              ),
              const Divider(indent: 72),
              ListTile(
                leading: const IconTile(Icons.help_outline_rounded, color: AppColors.muted),
                title: const Text('Help & FAQ'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: widget.demo
                    ? null
                    : () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => SupportScreen(
                            providerName: str(_p['name']),
                            providerEmail: str(_p['email']),
                            providerId: widget.providerId))),
              ),
            ]),
          ),

          const SectionTitle('Account'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.phone_outlined),
                title: Text(str(_p['phone'], '—')),
                subtitle: const Text('Mobile'),
              ),
              const Divider(indent: 56),
              ListTile(
                leading: const Icon(Icons.mail_outline_rounded),
                title: Text(str(_p['email'], '—')),
                subtitle: const Text('Email'),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          BigButton('Logout', icon: Icons.logout_rounded, outlined: true, color: AppColors.red, onPressed: widget.onLogout),
        ],
      ),
    );
  }
}
