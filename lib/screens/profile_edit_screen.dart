import 'dart:io';
import '../services/provider_api_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
  bool _saving = false;
  String? _photoUrl;
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text  = widget.providerData?['name'] ?? '';
    _phoneCtrl.text = widget.providerData?['phone'] ?? '';
    _bioCtrl.text   = widget.providerData?['bio'] ?? '';
    _cityCtrl.text  = widget.providerData?['city'] ?? '';
    _photoUrl       = widget.providerData?['photo'];
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose();
    _bioCtrl.dispose(); _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (img != null) setState(() => _selectedImage = File(img.path));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      String? photoUrl = _photoUrl;

      // Upload photo if selected
      if (_selectedImage != null) {
        final ref = FirebaseStorage.instance
            .ref('provider_photos/${widget.providerId}.jpg');
        await ref.putFile(_selectedImage!);
        photoUrl = await ref.getDownloadURL();
      }

      await ProviderApiService.updateProfile({
        'name':      _nameCtrl.text.trim(),
        'phone':     _phoneCtrl.text.trim(),
        'bio':       _bioCtrl.text.trim(),
        'city':      _cityCtrl.text.trim(),
        if (photoUrl != null) 'photo': photoUrl,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated!'), backgroundColor: AppColors.green));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.red));
    }
    setState(() => _saving = false);
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
      {TextInputType keyboard = TextInputType.text}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.5)),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        keyboardType: keyboard,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: AppColors.muted, size: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ]);
  }
}
