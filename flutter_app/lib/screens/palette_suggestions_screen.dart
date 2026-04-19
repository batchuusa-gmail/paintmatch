import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';
import '../models/room_analysis.dart';
import '../models/paint_color.dart';
import '../models/room_dimensions.dart';
import '../services/api_service.dart';
import '../widgets/vendor_comparison_card.dart';
import '../widgets/cost_estimate_sheet.dart';
import '../widgets/paint_calculator_card.dart';
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
  DimensionEstimate? _dimensionEstimate;

  @override
  void initState() {
    super.initState();
    // Load vendor matches and dimension estimate in parallel
    _loadVendorMatches();
    _loadDimensionEstimate();
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

  Future<void> _loadDimensionEstimate() async {
    try {
      final estimate = await ApiService().estimateDimensions(widget.imageFile);
      if (mounted) setState(() => _dimensionEstimate = estimate);
    } catch (_) {
      if (mounted) setState(() => _dimensionEstimate = DimensionEstimate.fallback);
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

            // ── Cost Estimate card ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GestureDetector(
                onTap: () => showCostEstimateSheet(
                  context,
                  vendorMatches: _vendorMatches ?? [],
                  paletteName: _selected.name,
                  estimate: _dimensionEstimate,
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.accentDim,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.calculate_outlined,
                          color: AppColors.accent, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Paint & Labour Cost',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(
                            _vendorMatches != null && _vendorMatches!.isNotEmpty
                                ? 'Tap to estimate total project cost'
                                : 'Tap to estimate — vendor data loading…',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: AppColors.accent, size: 20),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 12),

            const SizedBox(height: 12),

            // ── Paint Calculator (auto-shown once AI estimate loads) ─────────
            if (_dimensionEstimate == null)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        color: AppColors.accent, strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Estimating room dimensions…',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ]),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  const Icon(Icons.check_circle,
                      color: AppColors.accent, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    () {
                      final e = _dimensionEstimate!;
                      final wallCount = e.walls.length;
                      final area = e.paintableWallSqft.toStringAsFixed(0);
                      return '$wallCount walls detected · $area sq ft paintable';
                    }(),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              PaintCalculatorCard(
                dimensions: _dimensionEstimate!,
                vendors: _vendorMatches ?? [],
              ),
            ],

            const SizedBox(height: 12),

            // ── Preview CTA ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: FilledButton.icon(
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
                  'vendorMatches': _vendorMatches,
                }),
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
