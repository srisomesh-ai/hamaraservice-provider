import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/provider_api_service.dart';
import '../utils/parse.dart';
import '../utils/theme.dart';

class ProfileEditScreen extends StatefulWidget {
  final String providerId;
  final Map<String, dynamic>? providerData;
  const ProfileEditScreen({super.key, required this.providerId, this.providerData});
  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _bioCtrl   = TextEditingController();
  final _cityCtrl  = TextEditingController();
  final _instaCtrl = TextEditingController();
  final _ytCtrl    = TextEditingController();
  final _followersCtrl = TextEditingController();
  bool _saving = false;
  String? _photoUrl;
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text  = str(widget.providerData?['name']);
    _phoneCtrl.text = str(widget.providerData?['phone']);
    _bioCtrl.text   = str(widget.providerData?['bio']);
    _cityCtrl.text  = str(widget.providerData?['city']);
    _instaCtrl.text = str(widget.providerData?['instagram_url']);
    _ytCtrl.text    = str(widget.providerData?['youtube_url']);
    _followersCtrl.text = str(widget.providerData?['followers']);
    final p = photoUrl(widget.providerData?['photo']);
    _photoUrl       = p.isEmpty ? null : p;
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose();
    _bioCtrl.dispose(); _cityCtrl.dispose();
    _instaCtrl.dispose(); _ytCtrl.dispose(); _followersCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 70, maxWidth: 1024, maxHeight: 1024);
    if (img != null) setState(() => _selectedImage = File(img.path));
  }

  void _snack(String msg, Color color) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    final phone10 = phone.length > 10 ? phone.substring(phone.length - 10) : phone;
    if (name.isEmpty) { _snack('Enter your name', AppColors.red); return; }
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone10)) {
      _snack('Enter a valid 10-digit mobile number', AppColors.red);
      return;
    }
    setState(() => _saving = true);

    // 1. Photo → upload.php?action=provider_photo (server stores the URL)
    if (_selectedImage != null) {
      final up = await ProviderApiService.uploadPhoto(_selectedImage!);
      if (!mounted) return;
      if (!up.ok) {
        setState(() => _saving = false);
        if (!up.unauthorized) _snack('Photo upload failed: ${up.error}', AppColors.red);
        return;
      }
    }

    // 2. Profile fields
    final res = await ProviderApiService.updateProfile({
      'name':  name,
      'phone': phone10,
      'bio':   _bioCtrl.text.trim(),
      'city':  _cityCtrl.text.trim(),
      'instagram_url': _instaCtrl.text.trim(),
      'youtube_url':   _ytCtrl.text.trim(),
      'followers':     _followersCtrl.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!res.ok) {
      if (!res.unauthorized) _snack(res.error, AppColors.red);
      return;
    }
    _snack('Profile updated!', AppColors.green);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Edit Profile'), backgroundColor: AppColors.teal),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          // Photo
          Center(
            child: Stack(children: [
              CircleAvatar(
                radius: 56,
                backgroundColor: AppColors.teal,
                backgroundImage: _selectedImage != null
                    ? FileImage(_selectedImage!) as ImageProvider
                    : (_photoUrl != null ? NetworkImage(_photoUrl!) : null),
                child: (_selectedImage == null && _photoUrl == null)
                    ? Text((_nameCtrl.text.isNotEmpty ? _nameCtrl.text[0] : 'P').toUpperCase(),
                        style: const TextStyle(fontSize: 36, color: Colors.white, fontWeight: FontWeight.w700))
                    : null,
              ),
              Positioned(
                bottom: 0, right: 0,
                child: GestureDetector(
                  onTap: _pickPhoto,
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.brand, shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          const Text('Tap camera to change photo',
            style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 24),

          _field('Full Name', _nameCtrl, Icons.person_rounded),
          const SizedBox(height: 14),
          _field('Phone Number', _phoneCtrl, Icons.phone_rounded, keyboard: TextInputType.phone),
          const SizedBox(height: 14),
          _field('City', _cityCtrl, Icons.location_city_rounded),
          const SizedBox(height: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('SHORT BIO',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            TextField(
              controller: _bioCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Tell customers about yourself...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
          const SizedBox(height: 20),

          // Anchors / influencers: shown to customers with the quote.
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Anchors / influencers: customers see these with your quote (optional)',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ),
          const SizedBox(height: 10),
          _field('Instagram page', _instaCtrl, Icons.camera_alt_outlined,
              keyboard: TextInputType.url, hint: '@yourpage or instagram.com/yourpage'),
          const SizedBox(height: 14),
          _field('YouTube channel', _ytCtrl, Icons.play_circle_outline_rounded,
              keyboard: TextInputType.url, hint: '@yourchannel or youtube.com/@yourchannel'),
          const SizedBox(height: 14),
          _field('Followers', _followersCtrl, Icons.groups_outlined, hint: 'e.g. 25K', maxLength: 20),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
                  : const Text('Save Changes',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, IconData icon,
      {TextInputType keyboard = TextInputType.text, String? hint, int? maxLength}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.5)),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        keyboardType: keyboard,
        maxLength: maxLength,
        autocorrect: keyboard != TextInputType.url,
        decoration: InputDecoration(
          hintText: hint,
          counterText: '',
          prefixIcon: Icon(icon, color: AppColors.muted, size: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ]);
  }
}
