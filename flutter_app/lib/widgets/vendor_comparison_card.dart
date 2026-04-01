import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/paint_color.dart';
import '../utils/color_ext.dart';

class VendorComparisonCard extends StatelessWidget {
  final String targetHex;
  final List<PaintColor> matches;

  const VendorComparisonCard({
    super.key,
    required this.targetHex,
    required this.matches,
  });

  // Affiliate / store URLs per vendor
  static String _storeUrl(PaintColor c) {
    switch (c.vendor) {
      case 'sherwin_williams':
        return 'https://www.sherwin-williams.com/en-us/color/color-family';
      case 'benjamin_moore':
        return 'https://www.benjaminmoore.com/en-us/color-overview/find-your-color';
      case 'behr':
        return 'https://www.behr.com/consumer/colors/paint';
      case 'ppg':
        return 'https://www.ppgpaints.com/color';
      case 'valspar':
        return 'https://www.valspar.com/en/colors';
      default:
        return 'https://www.homedepot.com';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('No vendor matches found.')),
      );
    }

    // Group by vendor, pick best (lowest delta_e) per vendor
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: vendors.map((v) {
          final isBest = v == best;
          return _VendorRow(
            color: v,
            isBestValue: isBest,
            onBuySample: () => launchUrl(Uri.parse(_storeUrl(v))),
          );
        }).toList(),
      ),
    );
  }
}

class _VendorRow extends StatelessWidget {
  final PaintColor color;
  final bool isBestValue;
  final VoidCallback onBuySample;

  const _VendorRow({
    required this.color,
    required this.isBestValue,
    required this.onBuySample,
  });

  @override
  Widget build(BuildContext context) {
    final swatch = HexColor.fromHex(color.hex);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isBestValue
              ? Theme.of(context).colorScheme.primary
              : Colors.grey[200]!,
          width: isBestValue ? 2 : 1,
        ),
        color: Colors.white,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Color swatch
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: swatch,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
            ),
            const SizedBox(width: 12),

            // Color info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        color.vendorDisplayName,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      if (isBestValue) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Best Match',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${color.colorName} · ${color.colorCode}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (color.pricePerGallon != null)
                        Text(
                          '\$${color.pricePerGallon!.toStringAsFixed(2)}/gal',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      if (color.coverageSqft != null) ...[
                        const SizedBox(width: 8),
                        Text('${color.coverageSqft} sq ft',
                            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      ],
                      if (color.deltaE != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'ΔE ${color.deltaE!.toStringAsFixed(1)}',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Buy Sample button
            TextButton(
              onPressed: onBuySample,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Text(
                'Buy\nSample',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
