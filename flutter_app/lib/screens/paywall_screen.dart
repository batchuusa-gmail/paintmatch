import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';
import '../services/subscription_service.dart';

class PaywallScreen extends StatefulWidget {
  /// If true, shown because trial ended — no back button.
  final bool trialEnded;

  const PaywallScreen({super.key, this.trialEnded = false});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _annual  = true;   // toggle: annual vs monthly
  bool _loading = false;
  String _status = '';
  late StreamSubscription<String> _statusSub;

  @override
  void initState() {
    super.initState();
    _statusSub = SubscriptionService().statusStream.listen((msg) {
      if (!mounted) return;
      setState(() { _status = msg; _loading = false; });
      if (msg.startsWith('Pro activated')) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) context.go('/');
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
    final id = _annual ? kProductAnnual : kProductMonthly;
    await SubscriptionService().purchasePro(id);
  }

  Future<void> _restore() async {
    setState(() { _loading = true; _status = 'Checking previous purchases…'; });
    await SubscriptionService().restorePurchases();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.trialEnded
          ? null
          : AppBar(
              backgroundColor: AppColors.background,
              leading: IconButton(
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
                onPressed: () => context.pop(),
              ),
            ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.trialEnded) ...[
                const SizedBox(height: 24),
                // Trial ended banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade900.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.orange.shade700, width: 1),
                  ),
                  child: Row(children: [
                    Icon(Icons.lock_clock, color: Colors.orange.shade400, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your free trial of ${kTrialLimit} analyses is complete.\nUpgrade to keep going.',
                        style: TextStyle(
                            color: Colors.orange.shade200, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 28),
              ] else
                const SizedBox(height: 8),

              // Icon + headline
              Center(
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: AppColors.accentDim,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.workspace_premium,
                      color: AppColors.accent, size: 34),
                ),
              ),
              const SizedBox(height: 16),
              Text('PaintMatch Pro',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.playfairDisplay(
                      color: AppColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('Unlimited rooms. Every brand. No limits.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 14)),
              const SizedBox(height: 28),

              // Annual / Monthly toggle
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  Expanded(child: _PlanTab(
                    label: 'Annual',
                    price: '\$59.99',
                    sub: '\$4.99 / mo  •  Save 50%',
                    badge: 'BEST VALUE',
                    selected: _annual,
                    onTap: () => setState(() => _annual = true),
                  )),
                  const SizedBox(width: 4),
                  Expanded(child: _PlanTab(
                    label: 'Monthly',
                    price: '\$9.99',
                    sub: 'per month',
                    selected: !_annual,
                    onTap: () => setState(() => _annual = false),
                  )),
                ]),
              ),
              const SizedBox(height: 28),

              // Feature list
              _FeatureList(),
              const SizedBox(height: 28),

              // Status message
              if (_status.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: _status.startsWith('Pro activated')
                        ? Colors.green.shade900.withValues(alpha: 0.3)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_status,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: _status.startsWith('Pro activated')
                              ? Colors.green.shade300
                              : AppColors.textSecondary,
                          fontSize: 13)),
                ),
                const SizedBox(height: 16),
              ],

              // Subscribe CTA
              FilledButton(
                onPressed: _loading ? null : _subscribe,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : Text(
                        'Start ${_annual ? "Annual" : "Monthly"} Plan',
                        style: const TextStyle(
                            fontSize: 17,
                            color: Colors.black,
                            fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 14),

              // Restore
              TextButton(
                onPressed: _loading ? null : _restore,
                child: const Text('Restore previous purchase',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              ),
              const SizedBox(height: 8),

              // Legal
              const Text(
                'Subscriptions auto-renew unless cancelled at least 24 hours before the '
                'end of the current period. Manage or cancel in your App Store account settings.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    height: 1.5),
              ),

              const SizedBox(height: 20),
              // ── Dev / testing bypass ──────────────────────────────────────
              OutlinedButton(
                onPressed: () async {
                  await SubscriptionService().grantPro(plan: 'pro_test');
                  if (context.mounted) context.go('/');
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: const Text('Skip for now (Testing)',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Plan tab ─────────────────────────────────────────────────────────────────

class _PlanTab extends StatelessWidget {
  final String label;
  final String price;
  final String sub;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _PlanTab({
    required this.label,
    required this.price,
    required this.sub,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentDim : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(children: [
          if (badge != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(badge!,
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8)),
            ),
            const SizedBox(height: 6),
          ],
          Text(label,
              style: TextStyle(
                  color: selected ? AppColors.accent : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(price,
              style: TextStyle(
                  color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(sub,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 10)),
        ]),
      ),
    );
  }
}

// ─── Feature list ─────────────────────────────────────────────────────────────

class _FeatureList extends StatelessWidget {
  static const _features = [
    ('Unlimited room analyses',                true,  true),
    ('5 free analyses to start',               true,  false),
    ('Match colors across 5+ paint brands',    true,  true),
    ('Paint & labour cost estimator',          true,  true),
    ('Save rooms to project board',            false, true),
    ('Share previews with contractors',        false, true),
    ('Wall, ceiling, floor & trim painting',   false, true),
    ('Priority customer support',              false, true),
  ];

  const _FeatureList({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        // Header row
        Row(children: [
          const Expanded(child: SizedBox()),
          _ColHeader(label: 'Free'),
          _ColHeader(label: 'Pro', accent: true),
        ]),
        const SizedBox(height: 12),
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 12),
        ..._features.map((f) => _FeatureRow(
          label: f.$1, free: f.$2, pro: f.$3)),
      ]),
    );
  }
}

class _ColHeader extends StatelessWidget {
  final String label;
  final bool accent;
  const _ColHeader({required this.label, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      child: Center(
        child: Text(label,
            style: TextStyle(
                color: accent ? AppColors.accent : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String label;
  final bool free;
  final bool pro;
  const _FeatureRow({required this.label, required this.free, required this.pro});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
        ),
        _Check(active: free),
        _Check(active: pro, accent: true),
      ]),
    );
  }
}

class _Check extends StatelessWidget {
  final bool active;
  final bool accent;
  const _Check({required this.active, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      child: Center(
        child: Icon(
          active ? Icons.check_circle_rounded : Icons.remove,
          size: 18,
          color: active
              ? (accent ? AppColors.accent : AppColors.textSecondary)
              : AppColors.border,
        ),
      ),
    );
  }
}
