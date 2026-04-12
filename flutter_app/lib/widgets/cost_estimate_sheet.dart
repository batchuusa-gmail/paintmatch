import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';
import '../models/paint_color.dart';

/// Shows a cost breakdown bottom sheet.
/// Pass the vendor matches for the selected palette color.
void showCostEstimateSheet(
  BuildContext context, {
  required List<PaintColor> vendorMatches,
  required String paletteName,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CostEstimateSheet(
      vendorMatches: vendorMatches,
      paletteName: paletteName,
    ),
  );
}

class CostEstimateSheet extends StatefulWidget {
  final List<PaintColor> vendorMatches;
  final String paletteName;

  const CostEstimateSheet({
    super.key,
    required this.vendorMatches,
    required this.paletteName,
  });

  @override
  State<CostEstimateSheet> createState() => _CostEstimateSheetState();
}

class _CostEstimateSheetState extends State<CostEstimateSheet> {
  final _lengthCtrl = TextEditingController(text: '12');
  final _widthCtrl  = TextEditingController(text: '12');
  final _heightCtrl = TextEditingController(text: '9');
  int _coats = 2;
  int _doors = 1;
  int _windows = 2;

  // Labor rate per sq ft (US average interior paint)
  static const double _laborPerSqft = 2.75;

  double get _wallSqft {
    final l = double.tryParse(_lengthCtrl.text) ?? 0;
    final w = double.tryParse(_widthCtrl.text) ?? 0;
    final h = double.tryParse(_heightCtrl.text) ?? 0;
    final gross = 2 * (l + w) * h;
    final deductions = _doors * 20.0 + _windows * 15.0;
    return max(0, gross - deductions);
  }

  int _gallonsNeeded(int coverageSqft) {
    if (coverageSqft <= 0 || _wallSqft <= 0) return 0;
    return ((_wallSqft * _coats) / coverageSqft).ceil();
  }

  double _paintCost(PaintColor c) {
    final price = c.pricePerGallon ?? 0;
    final coverage = c.coverageSqft ?? 400;
    return _gallonsNeeded(coverage) * price;
  }

  double _laborCost() => _wallSqft * _laborPerSqft;

  double _totalCost(PaintColor c) => _paintCost(c) + _laborCost();

  // Best match per vendor (lowest delta-E)
  List<PaintColor> get _bestPerVendor {
    final map = <String, PaintColor>{};
    for (final c in widget.vendorMatches) {
      if (!map.containsKey(c.vendor) ||
          (c.deltaE ?? 999) < (map[c.vendor]!.deltaE ?? 999)) {
        map[c.vendor] = c;
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => _totalCost(a).compareTo(_totalCost(b)));
    return list;
  }

  @override
  void dispose() {
    _lengthCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vendors = _bestPerVendor;
    final cheapest = vendors.isNotEmpty ? vendors.first : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cost Estimate',
                          style: GoogleFonts.playfairDisplay(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w600)),
                      Text(widget.paletteName,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: AppColors.textSecondary, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(color: AppColors.border, height: 20),

            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  // ── Room dimensions ──────────────────────────────────────
                  _SectionLabel('Room Dimensions (ft)'),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _DimField(ctrl: _lengthCtrl, label: 'Length', onChanged: (_) => setState(() {}))),
                    const SizedBox(width: 10),
                    Expanded(child: _DimField(ctrl: _widthCtrl,  label: 'Width',  onChanged: (_) => setState(() {}))),
                    const SizedBox(width: 10),
                    Expanded(child: _DimField(ctrl: _heightCtrl, label: 'Height', onChanged: (_) => setState(() {}))),
                  ]),
                  const SizedBox(height: 16),

                  // ── Deductions & coats ───────────────────────────────────
                  Row(children: [
                    Expanded(
                      child: _StepperField(
                        label: 'Coats',
                        value: _coats,
                        min: 1, max: 3,
                        onChanged: (v) => setState(() => _coats = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StepperField(
                        label: 'Doors',
                        value: _doors,
                        min: 0, max: 6,
                        onChanged: (v) => setState(() => _doors = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StepperField(
                        label: 'Windows',
                        value: _windows,
                        min: 0, max: 8,
                        onChanged: (v) => setState(() => _windows = v),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),

                  // ── Wall area summary ────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.accentDim,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.square_foot, color: AppColors.accent, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        'Paintable wall area: ',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      Text(
                        '${_wallSqft.toStringAsFixed(0)} sq ft',
                        style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 14,
                            fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        '$_coats coat${_coats > 1 ? 's' : ''}',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 24),

                  // ── Per-vendor breakdown ─────────────────────────────────
                  _SectionLabel('Cost Breakdown by Vendor'),
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
                    ...vendors.map((c) => _VendorCostCard(
                          color: c,
                          wallSqft: _wallSqft,
                          gallons: _gallonsNeeded(c.coverageSqft ?? 400),
                          paintCost: _paintCost(c),
                          laborCost: _laborCost(),
                          totalCost: _totalCost(c),
                          isCheapest: c == cheapest,
                        )),

                  // ── Labor note ───────────────────────────────────────────
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            color: AppColors.textSecondary, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Labor estimated at \$${_laborPerSqft.toStringAsFixed(2)}/sq ft '
                            '(US average for interior painting). '
                            'Actual costs vary by region and contractor.',
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                height: 1.5),
                          ),
                        ),
                      ],
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

// ─── Section label ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6));
  }
}

// ─── Dimension text field ────────────────────────────────────────────────────

class _DimField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final ValueChanged<String> onChanged;

  const _DimField(
      {required this.ctrl, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        filled: true,
        fillColor: AppColors.background,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
      ),
    );
  }
}

// ─── Stepper field ───────────────────────────────────────────────────────────

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
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: value > min ? () => onChanged(value - 1) : null,
                child: Icon(Icons.remove,
                    size: 16,
                    color: value > min
                        ? AppColors.accent
                        : AppColors.textSecondary),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('$value',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
              GestureDetector(
                onTap: value < max ? () => onChanged(value + 1) : null,
                child: Icon(Icons.add,
                    size: 16,
                    color: value < max
                        ? AppColors.accent
                        : AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Vendor cost card ────────────────────────────────────────────────────────

class _VendorCostCard extends StatelessWidget {
  final PaintColor color;
  final double wallSqft;
  final int gallons;
  final double paintCost;
  final double laborCost;
  final double totalCost;
  final bool isCheapest;

  const _VendorCostCard({
    required this.color,
    required this.wallSqft,
    required this.gallons,
    required this.paintCost,
    required this.laborCost,
    required this.totalCost,
    required this.isCheapest,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCheapest
              ? AppColors.accent
              : AppColors.border,
          width: isCheapest ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(children: [
            // Color swatch
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Color(int.parse('0xFF${color.hex.replaceAll('#', '')}')),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(color.vendorDisplayName,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  Text('${color.colorName} · ${color.colorCode}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            if (isCheapest)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

          // Cost rows
          _CostRow(
            label: 'Paint ($gallons gal × \$${color.pricePerGallon?.toStringAsFixed(0) ?? "—"})',
            amount: paintCost,
          ),
          const SizedBox(height: 6),
          _CostRow(
            label: 'Labor (${wallSqft.toStringAsFixed(0)} sq ft)',
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
                    color: isCheapest
                        ? AppColors.accent
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18)),
          ]),
        ],
      ),
    );
  }
}

class _CostRow extends StatelessWidget {
  final String label;
  final double amount;

  const _CostRow({required this.label, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label,
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 12)),
      const Spacer(),
      Text('\$${amount.toStringAsFixed(0)}',
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13)),
    ]);
  }
}
