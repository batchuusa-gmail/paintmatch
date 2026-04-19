import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';
import '../services/painter_service.dart';
import '../services/subscription_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;
  // null = not chosen yet, 'homeowner' or 'painter'
  String? _selectedRole;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.auto_awesome,
      headline: 'See it before\nyou paint it',
      body: 'Upload any room photo. Our AI picks palette combinations that actually work — then shows you the result instantly.',
      tag: 'AI-Powered Visualizer',
    ),
    _OnboardingPage(
      icon: Icons.storefront_outlined,
      headline: 'Every major\nbrand. One search.',
      body: 'Compare Sherwin-Williams, Benjamin Moore, Behr, PPG, and Valspar side by side. Find the best price without leaving the app.',
      tag: 'Multi-Vendor Matching',
    ),
    _OnboardingPage(
      icon: Icons.folder_special_outlined,
      headline: 'Save rooms,\ntrack projects.',
      body: 'Build a library of rooms you\'re working on. Share previews with family, contractors, or your designer.',
      tag: 'Project Board',
    ),
  ];

  void _next() {
    if (_page < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _goAuth(String route) async {
    await SubscriptionService().markOnboardingComplete();
    if (mounted) context.go(route);
  }

  Future<void> _goAsPainter() async {
    await SubscriptionService().markOnboardingComplete();
    if (mounted) context.go('/signup?role=painter');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Skip (pages 0–1 only)
            Align(
              alignment: Alignment.centerRight,
              child: !isLast
                  ? TextButton(
                      onPressed: () => _pageController.animateToPage(
                        _pages.length - 1,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeInOut,
                      ),
                      child: const Text('Skip',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 14)),
                    )
                  : const SizedBox(height: 40),
            ),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) => _PageContent(page: _pages[i]),
              ),
            ),

            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width:  i == _page ? 24 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == _page ? AppColors.accent : AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              )),
            ),
            const SizedBox(height: 32),

            // CTAs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: isLast
                  ? Column(children: [
                      // Role selector
                      const Text('I am a…',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: _RoleChip(
                          label: 'Homeowner',
                          icon: Icons.home_outlined,
                          selected: _selectedRole == PainterService.roleHomeowner,
                          onTap: () => setState(
                              () => _selectedRole = PainterService.roleHomeowner),
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: _RoleChip(
                          label: 'Painter',
                          icon: Icons.format_paint_outlined,
                          selected: _selectedRole == PainterService.rolePainter,
                          onTap: () => setState(
                              () => _selectedRole = PainterService.rolePainter),
                        )),
                      ]),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _selectedRole == null
                            ? null
                            : () => _selectedRole == PainterService.rolePainter
                                ? _goAsPainter()
                                : _goAuth('/signup'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Create Free Account',
                            style: TextStyle(
                                fontSize: 16,
                                color: Colors.black,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => _goAuth('/login'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        child: const Text('Sign In',
                            style: TextStyle(
                                color: AppColors.textPrimary, fontSize: 16)),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Free trial includes $kTrialLimit room analyses.\nNo credit card required.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ])
                  : FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Continue',
                          style: TextStyle(
                              fontSize: 16,
                              color: Colors.black,
                              fontWeight: FontWeight.w700)),
                    ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ─── Role chip ────────────────────────────────────────────────────────────────

class _RoleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _RoleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentDim : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
              width: selected ? 1.5 : 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              color: selected ? AppColors.accent : AppColors.textSecondary,
              size: 22),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  color: selected
                      ? AppColors.accent
                      : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
        ]),
      ),
    );
  }
}

// ─── Single page ──────────────────────────────────────────────────────────────

class _OnboardingPage {
  final IconData icon;
  final String headline;
  final String body;
  final String tag;
  const _OnboardingPage({
    required this.icon,
    required this.headline,
    required this.body,
    required this.tag,
  });
}

class _PageContent extends StatelessWidget {
  final _OnboardingPage page;
  const _PageContent({required this.page});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon badge
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.accentDim,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
            ),
            child: Icon(page.icon, color: AppColors.accent, size: 44),
          ),
          const SizedBox(height: 12),

          // Tag chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(page.tag,
                style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6)),
          ),
          const SizedBox(height: 28),

          // Headline
          Text(page.headline,
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                  color: AppColors.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  height: 1.2)),
          const SizedBox(height: 18),

          // Body
          Text(page.body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  height: 1.55)),
        ],
      ),
    );
  }
}
