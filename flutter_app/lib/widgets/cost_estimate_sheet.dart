import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';
import '../models/paint_color.dart';
import '../models/room_dimensions.dart';

/// Opens the full cost estimate bottom sheet.
void showCostEstimateSheet(
  BuildContext context, {
  required List<PaintColor> vendorMatches,
  required String paletteName,
  DimensionEstimate? estimate,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CostEstimateSheet(
      vendorMatches: vendorMatches,
      paletteName: paletteName,
      estimate: estimate ?? DimensionEstimate.fallback,
    ),
  );
}

class CostEstimateSheet extends StatefulWidget {
  final List<PaintColor> vendorMatches;
  final String paletteName;
  final DimensionEstimate estimate;

  const CostEstimateSheet({
    super.key,
    required this.vendorMatches,
    required this.paletteName,
    required this.estimate,
  });

  @override
  State<CostEstimateSheet> createState() => _CostEstimateSheetState();
}

class _CostEstimateSheetState extends State<CostEstimateSheet> {
  int _coats = 2;
  bool _includeTrim = true;
  static const double _laborPerSqft = 2.75;
  static const double _trimLaborPerSqft = 3.50; // trim is more detailed work

  DimensionEstimate get _est => widget.estimate;

  double get _wallSqft => _est.paintableWallSqft;
  double get _trimSqft => _includeTrim ? _est.trimSqft : 0.0;

  int _wallGallons(int coverageSqft) =>
      _est.wallGallons(coats: _coats, coverageSqft: coverageSqft);

  int _trimGallons(int coverageSqft) =>
      _includeTrim && _est.trimSqft > 0
          ? _est.trimGallons(coats: _coats, coverageSqft: coverageSqft)
          : 0;

  double _paintCost(PaintColor c) {
    final price = c.pricePerGallon ?? 0.0;
    final coverage = c.coverageSqft ?? 400;
    return (_wallGallons(coverage) + _trimGallons(coverage)) * price;
  }

  double _laborCost() =>
      _wallSqft * _laborPerSqft + _trimSqft * _trimLaborPerSqft;

  double _totalCost(PaintColor c) => _paintCost(c) + _laborCost();

  List<PaintColor> get _bestPerVendor {
    final map = <String, PaintColor>{};
    for (final c in widget.vendorMatches) {
      if (!map.containsKey(c.vendor) ||
          (c.deltaE ?? 999) < (map[c.vendor]!.deltaE ?? 999)) {
        map[c.vendor] = c;
      }
    }
    return map.values.toList()
      ..sort((a, b) => _totalCost(a).compareTo(_totalCost(b)));
  }

  @override
  Widget build(BuildContext context) {
    final vendors = _bestPerVendor;
    final cheapest = vendors.isNotEmpty ? vendors.first : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Cost Estimate',
                      style: GoogleFonts.playfairDisplay(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w600)),
                  Text(widget.paletteName,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                ]),
                const Spacer(),
                // Confidence badge
                _ConfidenceBadge(_est.confidence),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close,
                      color: AppColors.textSecondary, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),

            const Divider(color: AppColors.border, height: 20),

            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [

                  // ── Wall breakdown ───────────────────────────────────────
                  _SectionLabel('Walls Detected'),
                  const SizedBox(height: 8),
                  ..._est.walls.map((w) => _DimRow(
                        label: w.label,
                        detail: '${w.widthFt.toStringAsFixed(1)}ft × ${w.heightFt.toStringAsFixed(1)}ft',
                        value: '${w.areaSqft.toStringAsFixed(0)} sq ft',
                      )),
                  if (_est.openings.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ..._est.openings.map((o) => _DimRow(
                          label: '− ${o.label}',
                          detail: '${o.widthFt.toStringAsFixed(1)}ft × ${o.heightFt.toStringAsFixed(1)}ft',
                          value: '−${o.areaSqft.toStringAsFixed(0)} sq ft',
                          isDeduction: true,
                        )),
                  ],
                  const SizedBox(height: 8),
                  _AreaSummaryRow(
                    label: 'Paintable wall area',
                    sqft: _wallSqft,
                  ),
                  const SizedBox(height: 20),

                  // ── Trim breakdown ───────────────────────────────────────
                  if (_est.trim.isNotEmpty) ...[
                    Row(children: [
                      const Expanded(child: _SectionLabel('Trim Detected')),
                      Transform.scale(
                        scale: 0.8,
                        child: Switch.adaptive(
                          value: _includeTrim,
                          activeColor: AppColors.accent,
                          onChanged: (v) => setState(() => _includeTrim = v),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    ..._est.trim.map((t) => _DimRow(
                          label: t.label,
                          detail: '${t.lengthFt.toStringAsFixed(1)} lin ft × ${t.widthIn.toStringAsFixed(1)}"',
                          value: '${t.areaSqft.toStringAsFixed(1)} sq ft',
                          dimmed: !_includeTrim,
                        )),
                    const SizedBox(height: 8),
                    _AreaSummaryRow(
                      label: 'Trim paint area',
                      sqft: _trimSqft,
                      dimmed: !_includeTrim,
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Settings ─────────────────────────────────────────────
                  _SectionLabel('Paint Settings'),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: _StepperField(
                        label: 'Coats',
                        value: _coats,
                        min: 1, max: 3,
                        onChanged: (v) => setState(() => _coats = v),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),

                  // ── Notes from AI ─────────────────────────────────────────
                  if (_est.notes.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline,
                              color: AppColors.textSecondary, size: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_est.notes,
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11,
                                    height: 1.5)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Per-vendor breakdown ─────────────────────────────────
                  _SectionLabel('Cost by Vendor'),
                  const SizedBox(height: 12),

                  if (vendors.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No vendor data available',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ),
                    )
                  else
                    ...vendors.map((c) {
                      final coverage = c.coverageSqft ?? 400;
                      return _VendorCostCard(
                        color: c,
                        wallSqft: _wallSqft,
                        trimSqft: _trimSqft,
                        wallGallons: _wallGallons(coverage),
                        trimGallons: _trimGallons(coverage),
                        paintCost: _paintCost(c),
                        laborCost: _laborCost(),
                        totalCost: _totalCost(c),
                        isCheapest: c == cheapest,
                        includeTrim: _includeTrim && _est.trimSqft > 0,
                      );
                    }),

                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      'Wall labor at \$${_laborPerSqft.toStringAsFixed(2)}/sq ft · '
                      'Trim labor at \$${_trimLaborPerSqft.toStringAsFixed(2)}/sq ft · '
                      'US averages — actual costs vary by region.',
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Confidence badge ────────────────────────────────────────────────────────

class _ConfidenceBadge extends StatelessWidget {
  final String confidence;
  const _ConfidenceBadge(this.confidence);

  @override
  Widget build(BuildContext context) {
    final color = confidence == 'high'
        ? Colors.green.shade400
        : confidence == 'medium'
            ? AppColors.accent
            : Colors.orange.shade400;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '${confidence[0].toUpperCase()}${confidence.substring(1)} accuracy',
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6));
}

// ─── Dimension row ────────────────────────────────────────────────────────────

class _DimRow extends StatelessWidget {
  final String label;
  final String detail;
  final String value;
  final bool isDeduction;
  final bool dimmed;

  const _DimRow({
    required this.label,
    required this.detail,
    required this.value,
    this.isDeduction = false,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = dimmed
        ? AppColors.textSecondary.withValues(alpha: 0.4)
        : isDeduction
            ? AppColors.textSecondary
            : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    color: textColor, fontSize: 12, fontWeight: FontWeight.w500)),
            Text(detail,
                style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: dimmed ? 0.3 : 0.7),
                    fontSize: 10)),
          ]),
        ),
        Text(value,
            style: TextStyle(
                color: isDeduction ? Colors.orange.shade400 : textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ─── Area summary row ─────────────────────────────────────────────────────────

class _AreaSummaryRow extends StatelessWidget {
  final String label;
  final double sqft;
  final bool dimmed;
  const _AreaSummaryRow({required this.label, required this.sqft, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: dimmed ? AppColors.background : AppColors.accentDim,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: dimmed
                ? AppColors.border
                : AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(Icons.square_foot,
            color: dimmed ? AppColors.textSecondary : AppColors.accent, size: 16),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                color: dimmed ? AppColors.textSecondary : AppColors.textSecondary,
                fontSize: 12)),
        const Spacer(),
        Text('${sqft.toStringAsFixed(0)} sq ft',
            style: TextStyle(
                color: dimmed ? AppColors.textSecondary : AppColors.accent,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ─── Stepper field ────────────────────────────────────────────────────────────

class _StepperField extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _StepperField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const Spacer(),
        GestureDetector(
          onTap: value > min ? () => onChanged(value - 1) : null,
          child: Icon(Icons.remove_circle_outline,
              size: 22,
              color: value > min ? AppColors.accent : AppColors.textSecondary),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('$value',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
        ),
        GestureDetector(
          onTap: value < max ? () => onChanged(value + 1) : null,
          child: Icon(Icons.add_circle_outline,
              size: 22,
              color: value < max ? AppColors.accent : AppColors.textSecondary),
        ),
      ]),
    );
  }
}

// ─── Vendor cost card ─────────────────────────────────────────────────────────

class _VendorCostCard extends StatelessWidget {
  final PaintColor color;
  final double wallSqft;
  final double trimSqft;
  final int wallGallons;
  final int trimGallons;
  final double paintCost;
  final double laborCost;
  final double totalCost;
  final bool isCheapest;
  final bool includeTrim;

  const _VendorCostCard({
    required this.color,
    required this.wallSqft,
    required this.trimSqft,
    required this.wallGallons,
    required this.trimGallons,
    required this.paintCost,
    required this.laborCost,
    required this.totalCost,
    required this.isCheapest,
    required this.includeTrim,
  });

  @override
  Widget build(BuildContext context) {
    final price = color.pricePerGallon?.toStringAsFixed(0) ?? '—';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCheapest ? AppColors.accent : AppColors.border,
          width: isCheapest ? 1.5 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: Color(int.parse('0xFF${color.hex.replaceAll('#', '')}')),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(color.vendorDisplayName,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              Text('${color.colorName} · ${color.colorCode}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
            ]),
          ),
          if (isCheapest)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accentDim,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Best Value',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
        ]),

        const SizedBox(height: 14),
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 12),

        _CostRow(
          label: 'Wall paint ($wallGallons gal × \$$price)',
          amount: wallGallons * (color.pricePerGallon ?? 0),
        ),
        if (includeTrim && trimGallons > 0) ...[
          const SizedBox(height: 6),
          _CostRow(
            label: 'Trim paint ($trimGallons gal × \$$price)',
            amount: trimGallons * (color.pricePerGallon ?? 0),
          ),
        ],
        const SizedBox(height: 6),
        _CostRow(
          label: 'Labor (${(wallSqft + trimSqft).toStringAsFixed(0)} sq ft)',
          amount: laborCost,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(color: AppColors.border, height: 1),
        ),
        Row(children: [
          const Text('Total Estimate',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
          const Spacer(),
          Text('\$${totalCost.toStringAsFixed(0)}',
              style: TextStyle(
                  color: isCheapest ? AppColors.accent : AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 18)),
        ]),
      ]),
    );
  }
}

class _CostRow extends StatelessWidget {
  final String label;
  final double amount;
  const _CostRow({required this.label, required this.amount});

  @override
  Widget build(BuildContext context) => Row(children: [
        Text(label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const Spacer(),
        Text('\$${amount.toStringAsFixed(0)}',
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
      ]);
}
