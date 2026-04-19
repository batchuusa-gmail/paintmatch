import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';
import '../models/paint_color.dart';
import '../models/room_dimensions.dart';

class PaintCalculatorCard extends StatefulWidget {
  final DimensionEstimate dimensions;
  final List<PaintColor> vendors;

  const PaintCalculatorCard({
    super.key,
    required this.dimensions,
    required this.vendors,
  });

  @override
  State<PaintCalculatorCard> createState() => _PaintCalculatorCardState();
}

class _PaintCalculatorCardState extends State<PaintCalculatorCard> {
  bool _twoCoats = true;

  // ── Calculation ─────────────────────────────────────────────────────────────

  double get _totalWallArea => widget.dimensions.grossWallSqft;
  double get _subtract => widget.dimensions.openingsSqft;
  double get _paintableArea => widget.dimensions.paintableWallSqft;

  int get _gallonsOneCoat => max(1, (_paintableArea / 400).ceil());
  int get _gallonsNeeded => _twoCoats ? _gallonsOneCoat * 2 : _gallonsOneCoat;

  double _costFor(PaintColor vendor) {
    final price = vendor.pricePerGallon ?? 35.0;
    return price * _gallonsNeeded;
  }

  double? get _cheapestCost {
    if (widget.vendors.isEmpty) return null;
    return widget.vendors
        .map(_costFor)
        .reduce((a, b) => a < b ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    final cheapest = _cheapestCost;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accentDim,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.format_paint, color: AppColors.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Paint Calculator',
                      style: GoogleFonts.playfairDisplay(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  Text(
                    'Coverage: ${_paintableArea.toStringAsFixed(0)} sq ft paintable area',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ]),
              ),
            ]),
          ),

          const Divider(color: AppColors.border, height: 1),

          // Coverage breakdown
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              _InfoChip(label: 'Wall area', value: '${_totalWallArea.toStringAsFixed(0)} ft²'),
              const SizedBox(width: 8),
              _InfoChip(
                label: 'Subtract',
                value: '−${_subtract.toStringAsFixed(0)} ft²',
                dimmed: true,
              ),
              const SizedBox(width: 8),
              _InfoChip(
                label: 'Paintable',
                value: '${_paintableArea.toStringAsFixed(0)} ft²',
                accent: true,
              ),
            ]),
          ),

          // 1-coat / 2-coat toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(children: [
              const Text('Coats:',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(width: 12),
              _CoatToggle(
                label: '1 coat',
                selected: !_twoCoats,
                onTap: () => setState(() => _twoCoats = false),
              ),
              const SizedBox(width: 8),
              _CoatToggle(
                label: '2 coats',
                selected: _twoCoats,
                onTap: () => setState(() => _twoCoats = true),
                badge: 'RECOMMENDED',
              ),
            ]),
          ),

          const SizedBox(height: 14),
          const Divider(color: AppColors.border, height: 1),

          // Per-vendor rows
          if (widget.vendors.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No vendor data available',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            )
          else
            ...widget.vendors.map((v) {
              final cost = _costFor(v);
              final isCheapest = cheapest != null && (cost - cheapest).abs() < 0.01;
              return _VendorRow(
                vendor: v,
                gallons: _gallonsNeeded,
                totalCost: cost,
                isCheapest: isCheapest,
              );
            }),

          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Estimates based on 400 sq ft/gallon coverage. '
              'Doors deducted at 21 sq ft each, windows at 15 sq ft each.',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 10, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;
  final bool dimmed;

  const _InfoChip({
    required this.label,
    required this.value,
    this.accent = false,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent
            ? AppColors.accentDim
            : AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: accent ? AppColors.accent.withValues(alpha: 0.4) : AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                color: dimmed ? AppColors.border : AppColors.textSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: accent ? AppColors.accent : AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _CoatToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  const _CoatToggle({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentDim : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.accent : AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  color: selected ? AppColors.accent : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          if (badge != null && selected) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(badge!,
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 8,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ]),
      ),
    );
  }
}

class _VendorRow extends StatelessWidget {
  final PaintColor vendor;
  final int gallons;
  final double totalCost;
  final bool isCheapest;

  const _VendorRow({
    required this.vendor,
    required this.gallons,
    required this.totalCost,
    required this.isCheapest,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
        color: isCheapest
            ? Colors.green.shade900.withValues(alpha: 0.12)
            : Colors.transparent,
      ),
      child: Row(children: [
        // Color swatch
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: Color(
                int.tryParse(vendor.hex.replaceAll('#', '0xFF')) ?? 0xFFCCCCCC),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(vendor.vendorDisplayName,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              if (isCheapest) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade800,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('BEST PRICE',
                      style: TextStyle(
                          color: Colors.green.shade300,
                          fontSize: 9,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ]),
            Text('${vendor.colorName} · $gallons gal',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${totalCost.toStringAsFixed(2)}',
              style: TextStyle(
                  color: isCheapest ? Colors.green.shade400 : AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          Text('\$${(vendor.pricePerGallon ?? 35.0).toStringAsFixed(2)}/gal',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 10)),
        ]),
      ]),
    );
  }
}
