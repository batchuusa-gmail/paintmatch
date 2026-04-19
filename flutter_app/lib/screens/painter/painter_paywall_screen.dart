import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../../services/subscription_service.dart';

const kProductPainterMonthly = 'com.srifinance.paintmatch.painter_monthly';

class PainterPaywallScreen extends StatefulWidget {
  const PainterPaywallScreen({super.key});

  @override
  State<PainterPaywallScreen> createState() => _PainterPaywallScreenState();
}

class _PainterPaywallScreenState extends State<PainterPaywallScreen> {
  bool _loading = false;
  String _status = '';
  late StreamSubscription<String> _statusSub;

  @override
  void initState() {
    super.initState();
    _statusSub = SubscriptionService().statusStream.listen((msg) {
      if (!mounted) return;
      setState(() { _status = msg; _loading = false; });
      if (msg.startsWith('Pro activated') || msg.startsWith('Painter activated')) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) context.go('/painter/dashboard');
        });
      }
    });
  }

  @override
  void dispose() {
    _statusSub.cancel();
    super.dispose();
  }

  Future<void> _subscribe() async {
    setState(() { _loading = true; _status = 'Opening store…'; });
    await SubscriptionService().purchasePro(kProductPainterMonthly);
  }

  Future<void> _restore() async {
    setState(() { _loading = true; _status = 'Restoring…'; });
    await SubscriptionService().restorePurchases();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(children: [
            // Header
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppColors.accentDim,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
              ),
              child: const Icon(Icons.workspace_premium,
                  color: AppColors.accent, size: 36),
            ),
            const SizedBox(height: 16),
            Text('Painter Pro',
                style: GoogleFonts.playfairDisplay(
                    color: AppColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Get listed. Get leads. Grow your business.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),

            const SizedBox(height: 32),

            // Price card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.accent),
                gradient: LinearGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: 0.15),
                    AppColors.accent.withValues(alpha: 0.04),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('\$49.99',
                        style: GoogleFonts.playfairDisplay(
                            color: AppColors.accent,
                            fontSize: 48,
                            fontWeight: FontWeight.w700)),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(' /month',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 15)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('FLAT FEE · NO PER-CONTRACT CHARGES',
                      style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8)),
                ),
              ]),
            ),

            const SizedBox(height: 24),

            // Perks
            ..._perks.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                          color: AppColors.accentDim,
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(p.$1, color: AppColors.accent, size: 16),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(p.$2,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      Text(p.$3,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ])),
                  ]),
                )),

            const SizedBox(height: 28),

            // Status message
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_status,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _status.startsWith('Error')
                            ? AppColors.error
                            : AppColors.accent,
                        fontSize: 13)),
              ),

            // Subscribe CTA
            FilledButton(
              onPressed: _loading ? null : _subscribe,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54)),
              child: _loading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Text('Subscribe — \$49.99/mo',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Colors.black)),
            ),
            const SizedBox(height: 12),

            // Restore
            TextButton(
              onPressed: _loading ? null : _restore,
              child: const Text('Restore Purchases'),
            ),
            const SizedBox(height: 8),

            const Text(
              'Subscription renews monthly. Cancel anytime in App Store settings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),

            const SizedBox(height: 20),
            // ── Dev / testing bypass ──────────────────────────────────────
            OutlinedButton(
              onPressed: () async {
                await SubscriptionService().grantPro(plan: 'painter_test');
                if (context.mounted) context.go('/painter/dashboard');
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                side: const BorderSide(color: AppColors.border),
              ),
              child: const Text('Skip for now (Testing)',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ),
          ]),
        ),
      ),
    );
  }

  static const _perks = [
    (Icons.search, 'Homeowner Directory Listing',
        'Your profile shown to homeowners searching for painters'),
    (Icons.mail_outline, 'Unlimited Leads',
        'Homeowners can contact you directly through the app'),
    (Icons.verified_outlined, 'Verified Painter Badge',
        'Stand out with an insured & verified badge'),
    (Icons.bar_chart, 'Lead Inbox Dashboard',
        'Track and respond to all incoming project requests'),
    (Icons.cancel_outlined, 'Cancel Anytime',
        'No contracts, no cancellation fees'),
  ];
}
