import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/room_analysis.dart';
import '../models/paint_color.dart';
import '../services/api_service.dart';
import '../widgets/vendor_comparison_card.dart';
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
    setState(() {
      _selectedIndex = index;
      _vendorMatches = null;
    });
    _loadVendorMatches();
  }

  PaletteSuggestion get _selected =>
      widget.analysis.recommendedPalettes[_selectedIndex];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Color Suggestions'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Regenerate'),
            onPressed: () => context.pushReplacement('/loading', extra: widget.imageFile),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Room image thumbnail
            SizedBox(
              height: 200,
              child: Image.file(widget.imageFile, fit: BoxFit.cover),
            ),

            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Choose a palette',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 12),

            // Horizontal scrollable palette cards
            SizedBox(
              height: 160,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.analysis.recommendedPalettes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final palette = widget.analysis.recommendedPalettes[i];
                  final isSelected = i == _selectedIndex;
                  return _PaletteCard(
                    palette: palette,
                    isSelected: isSelected,
                    onTap: () => _selectPalette(i),
                  );
                },
              ),
            ),

            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Vendor Matches',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 12),

            if (_loadingVendors)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_vendorMatches != null)
              VendorComparisonCard(
                targetHex: _selected.hex,
                matches: _vendorMatches!,
              ),

            const SizedBox(height: 24),

            // Preview button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                icon: const Icon(Icons.visibility),
                label: const Text('Preview in Your Room'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => context.push('/preview', extra: {
                  'originalImageUrl': widget.imageFile.path,
                  'renderedImageUrl': null,
                  'selectedHex': _selected.hex,
                  'selectedColorName': _selected.name,
                  'imageFile': widget.imageFile,
                }),
              ),
            ),
            const SizedBox(height: 32),
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
        width: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 4))]
              : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: Container(color: color)),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(palette.name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(palette.rationale,
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
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
