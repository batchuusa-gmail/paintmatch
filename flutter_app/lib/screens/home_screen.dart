import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_theme.dart';
import '../models/user_project.dart';
import '../services/painter_service.dart';
import '../services/subscription_service.dart';
import '../services/supabase_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _analysesRemaining = kTrialLimit;
  List<UserProject> _recentProjects = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    await Future.wait([_refreshTrialBadge(), _loadRecentProjects()]);
  }

  Future<void> _refreshTrialBadge() async {
    final r = await SubscriptionService().analysesRemaining();
    if (mounted) setState(() => _analysesRemaining = r);
  }

  Future<void> _loadRecentProjects() async {
    if (!SupabaseService().isSignedIn) return;
    try {
      final projects = await SupabaseService().getUserProjects();
      if (mounted) setState(() => _recentProjects = projects.take(6).toList());
    } catch (_) {}
  }

  void _showAccountSheet(BuildContext context) {
    final user = SupabaseService().currentUser;
    final email = user?.email ?? 'Not signed in';
    final isPainter = PainterService().isPainter;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.accentDim, shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person, color: AppColors.accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPainter ? 'Painter Account' : 'Homeowner Account',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    Text(email,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ],
                )),
              ]),
              const SizedBox(height: 20),
              const Divider(color: AppColors.border),
              const SizedBox(height: 8),

              if (!SupabaseService().isSignedIn) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.login, color: AppColors.accent),
                  title: const Text('Sign In',
                      style: TextStyle(color: AppColors.textPrimary)),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/login');
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.home_outlined,
                      color: AppColors.textSecondary),
                  title: const Text('Register as Homeowner',
                      style: TextStyle(color: AppColors.textPrimary)),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/signup');
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.format_paint_outlined,
                      color: AppColors.textSecondary),
                  title: const Text('Register as Painter',
                      style: TextStyle(color: AppColors.textPrimary)),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/signup?role=painter');
                  },
                ),
              ] else ...[
                if (isPainter)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.dashboard_outlined,
                        color: AppColors.accent),
                    title: const Text('Painter Dashboard',
                        style: TextStyle(color: AppColors.textPrimary)),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/painter/dashboard');
                    },
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout, color: AppColors.error),
                  title: const Text('Sign Out',
                      style: TextStyle(color: AppColors.error)),
                  onTap: () async {
                    Navigator.pop(context);
                    await SupabaseService().signOut();
                    if (context.mounted) context.go('/login');
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage(BuildContext context, ImageSource source) async {
    // Trial / paywall gate
    final canRun = await SubscriptionService().canRunAnalysis();
    if (!canRun && context.mounted) {
      context.push('/paywall', extra: true);
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 768,
      maxHeight: 768,
      imageQuality: 70,
    );
    if (picked == null || !context.mounted) return;
    context.push('/loading', extra: File(picked.path));
  }

  @override
  Widget build(BuildContext context) {
    final trialExhausted = _analysesRemaining == 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // App bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.format_paint, color: Colors.black, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'PaintMatch',
                        style: GoogleFonts.playfairDisplay(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Row(children: [
                    // Admin button — only for admin email
                    if (['11d04c21-23c6-4600-825d-ec49d381b06d',
                         'batchuusa@gmail.com', 'batchuusa@yahoo.com']
                        .contains(SupabaseService().currentUser?.id ??
                                  SupabaseService().currentUser?.email))
                      IconButton(
                        icon: const Icon(Icons.admin_panel_settings_outlined,
                            color: AppColors.accent),
                        onPressed: () => context.push('/admin'),
                      ),
                    // Account / logout
                    IconButton(
                      icon: const Icon(Icons.person_outline,
                          color: AppColors.textSecondary),
                      onPressed: () => _showAccountSheet(context),
                    ),
                    // Trial badge / Pro badge (long-press to reset trial in dev)
                    GestureDetector(
                      onTap: () => context.push('/paywall', extra: false),
                      onLongPress: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('analyses_used');
                        await prefs.remove('is_pro');
                        await prefs.remove('pro_plan');
                        await prefs.remove('pro_expiry_ms');
                        if (context.mounted) {
                          await _refreshTrialBadge();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Trial reset')),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: trialExhausted
                              ? Colors.red.shade900.withValues(alpha: 0.35)
                              : AppColors.accentDim,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: trialExhausted
                                ? Colors.red.shade700
                                : AppColors.accent.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                            trialExhausted
                                ? Icons.lock_outline
                                : Icons.auto_awesome,
                            size: 12,
                            color: trialExhausted
                                ? Colors.red.shade400
                                : AppColors.accent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            trialExhausted
                                ? 'Trial ended'
                                : '$_analysesRemaining left',
                            style: TextStyle(
                              color: trialExhausted
                                  ? Colors.red.shade400
                                  : AppColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ]),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.workspace_premium_outlined,
                          color: AppColors.textSecondary),
                      onPressed: () => context.push('/paywall', extra: false),
                    ),
                  ]),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),

                    // Hero heading
                    Text(
                      'Find your\nperfect color',
                      style: GoogleFonts.playfairDisplay(
                        color: AppColors.textPrimary,
                        fontSize: 36,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Upload a room photo and AI will suggest\npalettes, render the result, compare prices.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
                    ),

                    const SizedBox(height: 36),

                    // Upload CTA
                    _DarkUploadCard(
                      icon: Icons.photo_library_outlined,
                      title: 'Upload Room Photo',
                      subtitle: 'Choose from gallery',
                      onTap: () => _pickImage(context, ImageSource.gallery),
                      isPrimary: true,
                    ),
                    const SizedBox(height: 12),

                    // Camera CTA (mobile only)
                    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid))
                      _DarkUploadCard(
                        icon: Icons.camera_alt_outlined,
                        title: 'Take a Photo',
                        subtitle: 'Use your camera',
                        onTap: () => _pickImage(context, ImageSource.camera),
                        isPrimary: false,
                      ),

                    const SizedBox(height: 12),

                    // Find a Painter CTA
                    _DarkUploadCard(
                      icon: Icons.format_paint_outlined,
                      title: 'Find a Painter',
                      subtitle: 'Browse local painters near you',
                      onTap: () => context.push('/painter/directory'),
                      isPrimary: false,
                    ),

                    const SizedBox(height: 36),

                    // Style chips
                    Text(
                      'Popular Styles',
                      style: GoogleFonts.playfairDisplay(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: const [
                        'Modern', 'Scandinavian', 'Traditional',
                        'Farmhouse', 'Industrial', 'Coastal',
                      ].map((s) => _StyleChip(label: s)).toList(),
                    ),

                    const SizedBox(height: 36),

                    // Recent section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Recent Analyses',
                          style: GoogleFonts.playfairDisplay(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_recentProjects.isNotEmpty)
                          TextButton(
                            onPressed: () => context.push('/projects'),
                            child: const Text('See all',
                                style: TextStyle(color: AppColors.accent, fontSize: 13)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_recentProjects.isEmpty)
                      Center(
                        child: Column(
                          children: [
                            Icon(Icons.image_outlined, size: 48,
                                color: AppColors.textSecondary.withValues(alpha: 0.3)),
                            const SizedBox(height: 8),
                            const Text('No rooms analyzed yet',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          ],
                        ),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.1,
                        ),
                        itemCount: _recentProjects.length,
                        itemBuilder: (_, i) => _RecentProjectCard(
                          project: _recentProjects[i],
                          onTap: () => context.push('/projects'),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Bottom nav
            _BottomNav(
              selectedIndex: 0,
              onTap: (i) {
                if (i == 1) context.push('/projects');
                if (i == 2) context.push('/painter/directory');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkUploadCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isPrimary;

  const _DarkUploadCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.isPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isPrimary ? AppColors.accent : AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: isPrimary ? null : Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isPrimary ? Colors.black.withOpacity(0.15) : AppColors.accentDim,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 24, color: isPrimary ? Colors.black : AppColors.accent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isPrimary ? Colors.black : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isPrimary ? Colors.black54 : AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14,
                color: isPrimary ? Colors.black54 : AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _StyleChip extends StatelessWidget {
  final String label;
  const _StyleChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
    );
  }
}

class _RecentProjectCard extends StatelessWidget {
  final UserProject project;
  final VoidCallback onTap;
  const _RecentProjectCard({required this.project, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final imageUrl = project.renderedImageUrl ?? project.roomImageUrl;
    final hex = project.selectedHex;
    Color? swatch;
    if (hex != null && hex.length >= 6) {
      try {
        swatch = Color(int.parse(hex.replaceAll('#', '0xFF')));
      } catch (_) {}
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null)
              Image.network(imageUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox())
            else if (swatch != null)
              Container(color: swatch),
            // Gradient overlay + label
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                  ),
                ),
                child: Text(
                  project.projectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (swatch != null && imageUrl == null)
              Positioned(
                top: 8, right: 8,
                child: Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    color: swatch,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white54),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bottomNav,
      child: SafeArea(
        top: false,
        child: NavigationBar(
          backgroundColor: AppColors.bottomNav,
          selectedIndex: selectedIndex,
          onDestinationSelected: onTap,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Projects'),
            NavigationDestination(icon: Icon(Icons.format_paint_outlined), selectedIcon: Icon(Icons.format_paint), label: 'Painters'),
          ],
        ),
      ),
    );
  }
}
