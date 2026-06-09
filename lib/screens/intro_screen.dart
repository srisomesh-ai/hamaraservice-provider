import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/theme.dart';
import 'login_screen.dart';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});
  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _pageCtrl = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _pages = [
    {
      'emoji': '💼',
      'title': 'Earn on Your\nOwn Schedule',
      'subtitle': 'Accept bookings when you want. Work flexible hours and be your own boss.',
      'bg': [Color(0xFF0D3D47), AppColors.teal],
    },
    {
      'emoji': '📱',
      'title': 'Get Bookings\nInstantly',
      'subtitle': 'Customers near you book services. You get notified instantly and can accept in one tap.',
      'bg': [Color(0xFF1a1a4e), Color(0xFF2d2d8f)],
    },
    {
      'emoji': '💰',
      'title': 'Get Paid\nFast & Safely',
      'subtitle': 'Transparent pricing, direct payments. Build your reputation with ratings from customers.',
      'bg': [Color(0xFF2d1b00), AppColors.brand],
    },
  ];

  @override
  void dispose() { _pageCtrl.dispose(); super.dispose(); }

  Future<void> _getStarted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('provider_intro_seen', true);
    if (!mounted) return;
    Navigator.pushReplacement(context,
      MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageCtrl,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: _pages.length,
            itemBuilder: (_, i) => _buildPage(_pages[i]),
          ),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.4)],
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pages.length, (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _currentPage ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _currentPage ? Colors.white : Colors.white38,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    )),
                  ),
                  const SizedBox(height: 24),
                  if (_currentPage == _pages.length - 1)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _getStarted,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brand,
                          minimumSize: const Size(double.infinity, 54),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Get Started →', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: _getStarted,
                          child: const Text('Skip', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                        ElevatedButton(
                          onPressed: () => _pageCtrl.nextPage(
                            duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.teal,
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Next →', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(Map<String, dynamic> page) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: page['bg'] as List<Color>,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.home_repair_service_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 10),
                RichText(text: const TextSpan(children: [
                  TextSpan(text: 'Hamara', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                  TextSpan(text: 'Service', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.brand)),
                ])),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.brand.withOpacity(0.3), borderRadius: BorderRadius.circular(6)),
                  child: const Text('PROVIDER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ]),
              const Spacer(),
              Text(page['emoji'] as String, style: const TextStyle(fontSize: 80)),
              const SizedBox(height: 24),
              Text(page['title'] as String,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white, height: 1.2)),
              const SizedBox(height: 16),
              Text(page['subtitle'] as String,
                style: const TextStyle(fontSize: 15, color: Colors.white70, height: 1.6)),
              const SizedBox(height: 160),
            ],
          ),
        ),
      ),
    );
  }
}
