import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';
import '../models/room_analysis.dart';
import '../models/paint_color.dart';
import '../services/api_service.dart';
import '../widgets/vendor_comparison_card.dart';
import '../widgets/cost_estimate_sheet.dart';
import '../utils/color_ext.dart';

class PaletteSuggestionsScreen extends StatefulWidget {
  final File imageFile;
  final RoomAnalysis analysis;

  const PaletteSuggestionsScreen({
    super.key,
    required this.imageFile,
    required this.analysis,
  });

  @override
  State<PaletteSuggestionsScreen> createState() => _PaletteSuggestionsScreenState();
}

class _PaletteSuggestionsScreenState extends State<PaletteSuggestionsScreen> {
  int _selectedIndex = 0;
  List<PaintColor>? _vendorMatches;
  bool _loadingVendors = false;

  @override
  void initState() {
    super.initState();
    _loadVendorMatches();
  }

  Future<void> _loadVendorMatches() async {
    final hex = widget.analysis.recommendedPalettes[_selectedIndex].hex;
    setState(() => _loadingVendors = true);
    try {
      final matches = await ApiService().matchColors(hex);
      if (mounted) setState(() => _vendorMatches = matches);
    } catch (_) {
      if (mounted) setState(() => _vendorMatches = []);
    } finally {
      if (mounted) setState(() => _loadingVendors = false);
    }
  }

  void _selectPalette(int index) {
    setState(() { _selectedIndex = index; _vendorMatches = null; });
    _loadVendorMatches();
  }

  PaletteSuggestion get _selected => widget.analysis.recommendedPalettes[_selectedIndex];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary, size: 18),
          onPressed: () => context.go('/'),
        ),
        title: Text('Color Suggestions',
            style: GoogleFonts.playfairDisplay(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.refresh, color: AppColors.accent, size: 16),
            label: const Text('Regenerate', style: TextStyle(color: AppColors.accent, fontSize: 13)),
            onPressed: () => context.pushReplacement('/loading', extra: widget.imageFile),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Room image
            SizedBox(
              height: 200,
              width: double.infinity,
              child: Image.file(widget.imageFile, fit: BoxFit.cover),
            ),

            // Gradient overlay at bottom of image
            Container(
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, AppColors.background],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Choose a palette',
                      style: GoogleFonts.playfairDisplay(
                          color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Tap a card to see vendor matches below',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Horizontal palette cards
            SizedBox(
              height: 170,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: widget.analysis.recommendedPalettes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _PaletteCard(
                  palette: widget.analysis.recommendedPalettes[i],
                  isSelected: i == _selectedIndex,
                  onTap: () => _selectPalette(i),
                ),
              ),
            ),

            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Vendor Matches',
                  style: GoogleFonts.playfairDisplay(
                      color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 12),

            if (_loadingVendors)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
              )
            else if (_vendorMatches != null)
              VendorComparisonCard(targetHex: _selected.hex, matches: _vendorMatches!),

            const SizedBox(height: 24),

            // Cost estimate + Preview CTAs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Cost estimate button (only when vendor data loaded)
                  if (_vendorMatches != null && _vendorMatches!.isNotEmpty)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.calculate_outlined, color: AppColors.accent, size: 18),
                      label: const Text('Estimate Paint & Labour Cost',
                          style: TextStyle(color: AppColors.accent, fontSize: 14)),
                      onPressed: () => showCostEstimateSheet(
                        context,
                        vendorMatches: _vendorMatches!,
                        paletteName: _selected.name,
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        side: const BorderSide(color: AppColors.accent),
                      ),
                    ),
                  if (_vendorMatches != null && _vendorMatches!.isNotEmpty)
                    const SizedBox(height: 12),

                  FilledButton.icon(
                    icon: const Icon(Icons.visibility, color: Colors.black),
                    label: const Text('Preview in Your Room'),
                    onPressed: () => context.push('/preview', extra: {
                      'originalImageUrl': widget.imageFile.path,
                      'renderedImageUrl': null,
                      'selectedHex': _selected.hex,
                      'selectedColorName': _selected.name,
                      'imageFile': widget.imageFile,
                      'wallHex': widget.analysis.wallHex,
                      'finish': 'eggshell',
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _PaletteCard extends StatelessWidget {
  final PaletteSuggestion palette;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaletteCard({required this.palette, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = HexColor.fromHex(palette.hex);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 145,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          color: AppColors.card,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Color swatch
              Expanded(flex: 3, child: Container(color: color)),
              // Info
              Container(
                color: AppColors.card,
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(palette.name,
                        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 12),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(palette.rationale,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (isSelected) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accentDim,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Selected',
                            style: TextStyle(color: AppColors.accent, fontSize: 9, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
