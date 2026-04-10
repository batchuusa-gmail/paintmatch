import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../config/app_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _pickImage(BuildContext context, ImageSource source) async {
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
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, color: AppColors.textSecondary),
                    onPressed: () {},
                  ),
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
                    Text(
                      'Recent Analyses',
                      style: GoogleFonts.playfairDisplay(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Column(
                        children: [
                          Icon(Icons.image_outlined, size: 48, color: AppColors.textSecondary.withOpacity(0.3)),
                          const SizedBox(height: 8),
                          const Text('No rooms analyzed yet', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom nav
            _BottomNav(
              selectedIndex: 0,
              onTap: (i) { if (i == 1) context.push('/projects'); },
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
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}
