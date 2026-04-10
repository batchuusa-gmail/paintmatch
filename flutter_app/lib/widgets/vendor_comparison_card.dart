import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../models/paint_color.dart';
import '../utils/color_ext.dart';

class VendorComparisonCard extends StatelessWidget {
  final String targetHex;
  final List<PaintColor> matches;

  const VendorComparisonCard({super.key, required this.targetHex, required this.matches});

  static String _storeUrl(PaintColor c) {
    switch (c.vendor) {
      case 'sherwin_williams': return 'https://www.sherwin-williams.com/en-us/color/color-family';
      case 'benjamin_moore': return 'https://www.benjaminmoore.com/en-us/color-overview/find-your-color';
      case 'behr': return 'https://www.behr.com/consumer/colors/paint';
      case 'ppg': return 'https://www.ppgpaints.com/color';
      case 'valspar': return 'https://www.valspar.com/en/colors';
      default: return 'https://www.homedepot.com';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('No vendor matches found.', style: TextStyle(color: AppColors.textSecondary))),
      );
    }

    final Map<String, PaintColor> bestPerVendor = {};
    for (final m in matches) {
      final existing = bestPerVendor[m.vendor];
      if (existing == null || (m.deltaE ?? 99) < (existing.deltaE ?? 99)) {
        bestPerVendor[m.vendor] = m;
      }
    }

    final vendors = bestPerVendor.values.toList()
      ..sort((a, b) => (a.deltaE ?? 99).compareTo(b.deltaE ?? 99));
    final best = vendors.isNotEmpty ? vendors.first : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: vendors.map((v) => _VendorRow(
          color: v,
          isBestValue: v == best,
          onBuySample: () => launchUrl(Uri.parse(_storeUrl(v))),
        )).toList(),
      ),
    );
  }
}

class _VendorRow extends StatelessWidget {
  final PaintColor color;
  final bool isBestValue;
  final VoidCallback onBuySample;

  const _VendorRow({required this.color, required this.isBestValue, required this.onBuySample});

  @override
  Widget build(BuildContext context) {
    final swatch = HexColor.fromHex(color.hex);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isBestValue ? AppColors.accent : AppColors.border,
          width: isBestValue ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Swatch
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: swatch,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(color.vendorDisplayName,
                        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                    if (isBestValue) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accentDim,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Best Match',
                            style: TextStyle(color: AppColors.accent, fontSize: 9, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text('${color.colorName} · ${color.colorCode}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 5),
                Row(
                  children: [
                    if (color.pricePerGallon != null)
                      Text('\$${color.pricePerGallon!.toStringAsFixed(2)}/gal',
                          style: const TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600)),
                    if (color.coverageSqft != null) ...[
                      const SizedBox(width: 8),
                      Text('${color.coverageSqft} sq ft',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    ],
                    if (color.deltaE != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text('ΔE ${color.deltaE!.toStringAsFixed(1)}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Buy button
          GestureDetector(
            onTap: onBuySample,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accentDim,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.accent.withOpacity(0.3)),
              ),
              child: const Text('Sample',
                  style: TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
