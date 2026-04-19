import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../../services/painter_service.dart';
import '../../services/subscription_service.dart';
import '../../services/supabase_service.dart';

class PainterDashboardScreen extends StatefulWidget {
  const PainterDashboardScreen({super.key});

  @override
  State<PainterDashboardScreen> createState() =>
      _PainterDashboardScreenState();
}

class _PainterDashboardScreenState extends State<PainterDashboardScreen> {
  PainterProfile? _profile;
  List<PainterLead>? _leads;
  bool _loading = true;
  bool _testSubActive = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await PainterService().myProfile();
      final l = await PainterService().myLeads();
      final testSub = await SubscriptionService().isProActive();
      if (mounted) setState(() { _profile = p; _leads = l; _testSubActive = testSub; });
    } catch (_) {
      if (mounted) setState(() { _leads = []; });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    await SupabaseService().signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
            child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    // No profile yet — redirect to registration
    if (_profile == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/painter/register');
      });
      return const SizedBox();
    }

    final newLeads = (_leads ?? []).where((l) => l.isNew).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        automaticallyImplyLeading: false,
        title: Text('Painter Dashboard',
            style: GoogleFonts.playfairDisplay(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline,
                color: AppColors.textSecondary, size: 22),
            tooltip: 'Profile',
            onPressed: () => context.push('/painter/profile'),
          ),
          IconButton(
            icon: const Icon(Icons.logout,
                color: AppColors.textSecondary, size: 20),
            tooltip: 'Sign Out',
            onPressed: _signOut,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(delegate: SliverChildListDelegate([
              // Greeting
              _GreetingCard(profile: _profile!, newLeads: newLeads),
              const SizedBox(height: 20),

              // Subscription status — hide banner if test grant is active
              if (!_profile!.subscriptionActive && !_testSubActive)
                _SubscriptionBanner(
                    onUpgrade: () => context.push('/painter/paywall')),

              const SizedBox(height: 4),
              _sectionHeader('Leads Inbox',
                  badge: newLeads > 0 ? '$newLeads new' : null),
              const SizedBox(height: 12),
            ])),
          ),

          // Leads list
          _leads == null || _leads!.isEmpty
              ? SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyLeads(),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _LeadCard(
                        lead: _leads![i],
                        onTap: () async {
                          if (_leads![i].isNew) {
                            await PainterService()
                                .markLeadViewed(_leads![i].id);
                            _load();
                          }
                          if (mounted) {
                            _showLeadDetail(_leads![i]);
                          }
                        },
                      ),
                      childCount: _leads!.length,
                    ),
                  ),
                ),
        ]),
      ),
    );
  }

  void _showLeadDetail(PainterLead lead) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _LeadDetailSheet(lead: lead),
    );
  }

  Widget _sectionHeader(String title, {String? badge}) {
    return Row(children: [
      Text(title,
          style: GoogleFonts.playfairDisplay(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600)),
      if (badge != null) ...[
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(badge,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
      ],
    ]);
  }
}

// ─── Greeting card ────────────────────────────────────────────────────────────

class _GreetingCard extends StatelessWidget {
  final PainterProfile profile;
  final int newLeads;
  const _GreetingCard({required this.profile, required this.newLeads});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: AppColors.accentDim,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.business, color: AppColors.accent, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(profile.companyName,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Row(children: [
            if (profile.isVerified) ...[
              const Icon(Icons.verified, color: AppColors.accent, size: 14),
              const SizedBox(width: 4),
            ],
            Text(profile.subscriptionActive ? 'Active' : 'Inactive',
                style: TextStyle(
                    color: profile.subscriptionActive
                        ? AppColors.accent
                        : AppColors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${profile.totalReviews}',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 20)),
          const Text('reviews',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ]),
      ]),
    );
  }
}

// ─── Subscription banner ──────────────────────────────────────────────────────

class _SubscriptionBanner extends StatelessWidget {
  final VoidCallback onUpgrade;
  const _SubscriptionBanner({required this.onUpgrade});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
        color: AppColors.error.withValues(alpha: 0.08),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded,
            color: AppColors.error, size: 20),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('Your subscription is inactive. Subscribe to receive leads.',
              style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 13)),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onUpgrade,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('Subscribe',
                style: TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}

// ─── Lead card ────────────────────────────────────────────────────────────────

class _LeadCard extends StatelessWidget {
  final PainterLead lead;
  final VoidCallback onTap;
  const _LeadCard({required this.lead, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: lead.isNew
                  ? AppColors.accent.withValues(alpha: 0.4)
                  : AppColors.border),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: lead.isNew
                  ? AppColors.accentDim
                  : AppColors.border.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_outline,
                color: lead.isNew
                    ? AppColors.accent
                    : AppColors.textSecondary,
                size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              Expanded(
                child: Text(lead.contactName,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (lead.isNew)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('NEW',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 9,
                          fontWeight: FontWeight.w800)),
                ),
            ]),
            const SizedBox(height: 2),
            Text(lead.message,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(_formatDate(lead.createdAt),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
          ])),
          const Icon(Icons.chevron_right,
              color: AppColors.textSecondary, size: 18),
        ]),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug',
        'Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}';
  }
}

// ─── Lead detail sheet ────────────────────────────────────────────────────────

class _LeadDetailSheet extends StatelessWidget {
  final PainterLead lead;
  const _LeadDetailSheet({required this.lead});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, ctrl) => SingleChildScrollView(
        controller: ctrl,
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Text('Lead Details',
              style: GoogleFonts.playfairDisplay(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          _detailRow('Name', lead.contactName),
          _detailRow('Email', lead.contactEmail),
          _detailRow('Phone', lead.contactPhone),
          const Divider(height: 28, color: AppColors.border),
          const Text('Message',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 8),
          Text(lead.message,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14, height: 1.5)),
          const SizedBox(height: 28),
          // Contact actions
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.phone_outlined, size: 18),
                label: const Text('Call'),
                onPressed: () {},
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.email_outlined,
                    size: 18, color: Colors.black),
                label: const Text('Email',
                    style: TextStyle(color: Colors.black)),
                onPressed: () {},
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 56,
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }
}

// ─── Empty leads state ────────────────────────────────────────────────────────

class _EmptyLeads extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.inbox_outlined,
                size: 32, color: AppColors.accent),
          ),
          const SizedBox(height: 16),
          const Text('No leads yet',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text(
            'Homeowners will appear here\nwhen they request your services',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 13, height: 1.5),
          ),
        ]),
      ),
    );
  }
}
