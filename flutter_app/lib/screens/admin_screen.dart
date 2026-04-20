import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../config/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Admin screen — only accessible to batchuusa@gmail.com
// ─────────────────────────────────────────────────────────────────────────────

const _adminSecret = 'pm_admin_2025';   // must match ADMIN_SECRET on Railway

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _fetch();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/admin/stats');
      final res = await http.get(uri,
          headers: {'X-Admin-Key': _adminSecret});
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['error'] != null) throw Exception(json['error']);
      setState(() { _data = json['data'] as Map<String, dynamic>; });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Admin',
            style: GoogleFonts.playfairDisplay(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.accent),
            onPressed: _fetch,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.accent,
          tabs: const [
            Tab(text: 'Dashboard'),
            Tab(text: 'Users'),
            Tab(text: 'Painters'),
            Tab(text: 'Revenue'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _error != null
              ? Center(child: Text(_error!,
                  style: const TextStyle(color: Colors.red)))
              : TabBarView(
                  controller: _tab,
                  children: [
                    _DashboardTab(data: _data),
                    _UsersTab(data: _data),
                    _PaintersTab(data: _data),
                    _RevenueTab(data: _data),
                  ],
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard tab — KPI summary cards
// ─────────────────────────────────────────────────────────────────────────────

class _DashboardTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _DashboardTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final users    = data['users']     as Map<String, dynamic>? ?? {};
    final painters = data['painters']  as Map<String, dynamic>? ?? {};
    final leads    = data['leads']     as Map<String, dynamic>? ?? {};
    final revenue  = data['revenue']   as Map<String, dynamic>? ?? {};
    final inv      = data['inventory'] as Map<String, dynamic>? ?? {};

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _sectionLabel('Overview'),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: [
            _KpiCard(
              label: 'Total Users',
              value: '${users['total_with_projects'] ?? 0}',
              sub: '${users['premium_estimate'] ?? 0} premium',
              icon: Icons.people_outline,
            ),
            _KpiCard(
              label: 'Painters',
              value: '${painters['total'] ?? 0}',
              sub: '${painters['active'] ?? 0} active',
              icon: Icons.format_paint_outlined,
            ),
            _KpiCard(
              label: 'Projects',
              value: '${users['total_projects'] ?? 0}',
              sub: 'room renders',
              icon: Icons.home_outlined,
            ),
            _KpiCard(
              label: 'Leads',
              value: '${leads['total'] ?? 0}',
              sub: '${leads['new'] ?? 0} new',
              icon: Icons.contact_mail_outlined,
              highlight: (leads['new'] ?? 0) > 0,
            ),
          ],
        ),

        const SizedBox(height: 28),
        _sectionLabel('Revenue'),
        const SizedBox(height: 12),
        _BigRevenueCard(revenue: revenue),

        const SizedBox(height: 28),
        _sectionLabel('Paint Inventory'),
        const SizedBox(height: 12),
        _InventoryCard(inv: inv),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Users tab
// ─────────────────────────────────────────────────────────────────────────────

class _UsersTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _UsersTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final users   = data['users']    as Map<String, dynamic>? ?? {};
    final revenue = data['revenue']  as Map<String, dynamic>? ?? {};

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _StatRow('Total users with projects', '${users['total_with_projects'] ?? 0}'),
        _StatRow('Estimated premium users',   '${users['premium_estimate'] ?? 0}'),
        _StatRow('Total room projects',        '${users['total_projects'] ?? 0}'),
        _StatRow('User MRR (est.)',
            '\$${(revenue['user_mrr'] as num?)?.toStringAsFixed(2) ?? "0.00"}'),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Note', style: TextStyle(
                  color: AppColors.accent, fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              Text(
                'Full user list requires Supabase Auth admin access.\n'
                'Users are counted by unique project activity. '
                'Premium users estimated as those with ≥2 projects.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painters tab
// ─────────────────────────────────────────────────────────────────────────────

class _PaintersTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _PaintersTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final painters = data['painters'] as Map<String, dynamic>? ?? {};
    final list     = (painters['list'] as List<dynamic>?) ?? [];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          _Chip('Total: ${painters['total'] ?? 0}',  AppColors.textSecondary),
          const SizedBox(width: 8),
          _Chip('Active: ${painters['active'] ?? 0}', AppColors.accent),
          const SizedBox(width: 8),
          _Chip('Verified: ${painters['verified'] ?? 0}', Colors.green),
        ]),
        const SizedBox(height: 16),
        if (list.isEmpty)
          const Center(child: Padding(
            padding: EdgeInsets.all(40),
            child: Text('No painters registered yet',
                style: TextStyle(color: AppColors.textSecondary)),
          ))
        else
          ...list.map((p) => _PainterCard(painter: p as Map<String, dynamic>)),
      ],
    );
  }
}

class _PainterCard extends StatelessWidget {
  final Map<String, dynamic> painter;
  const _PainterCard({required this.painter});

  @override
  Widget build(BuildContext context) {
    final active   = (painter['subscription_active'] as bool?) ?? false;
    final verified = (painter['is_verified'] as bool?) ?? false;
    final rating   = (painter['avg_rating'] as num?)?.toDouble() ?? 0.0;
    final reviews  = (painter['total_reviews'] as num?)?.toInt() ?? 0;
    final created  = (painter['created_at'] as String?) ?? '';
    final date     = created.isNotEmpty
        ? created.substring(0, 10)
        : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(
            painter['company_name'] as String? ?? '—',
            style: const TextStyle(color: AppColors.textPrimary,
                fontWeight: FontWeight.w700, fontSize: 15),
          )),
          if (verified)
            const Icon(Icons.verified, color: Colors.blue, size: 16),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: active ? Colors.green.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              active ? 'Active' : 'Inactive',
              style: TextStyle(
                color: active ? Colors.green : AppColors.textSecondary,
                fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(painter['contact_name'] as String? ?? '',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        Text(painter['email'] as String? ?? '',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.star, color: AppColors.accent, size: 14),
          const SizedBox(width: 4),
          Text('${rating.toStringAsFixed(1)} ($reviews reviews)',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const Spacer(),
          Text('Joined $date',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ]),
        if ((painter['specialties'] as List?)?.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final s in (painter['specialties'] as List? ?? []))
              _Chip(s.toString(), AppColors.textSecondary),
          ]),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Revenue tab
// ─────────────────────────────────────────────────────────────────────────────

class _RevenueTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _RevenueTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final r = data['revenue'] as Map<String, dynamic>? ?? {};

    final totalMrr     = (r['total_mrr']    as num?)?.toDouble() ?? 0;
    final totalArr     = (r['total_arr']    as num?)?.toDouble() ?? 0;
    final painterMrr   = (r['painter_mrr']  as num?)?.toDouble() ?? 0;
    final userMrr      = (r['user_mrr']     as num?)?.toDouble() ?? 0;
    final activePainters = r['active_painters'] as int? ?? 0;
    final premiumUsers   = r['premium_users']   as int? ?? 0;
    final painterPrice   = (r['painter_price']  as num?)?.toDouble() ?? 29;
    final userPrice      = (r['user_price']     as num?)?.toDouble() ?? 9.99;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Big MRR card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1a1400), Color(0xFF2a1f00)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
          ),
          child: Column(children: [
            const Text('Monthly Recurring Revenue',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13,
                    letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Text('\$${totalMrr.toStringAsFixed(2)}',
                style: GoogleFonts.playfairDisplay(
                    color: AppColors.accent, fontSize: 40,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('ARR: \$${totalArr.toStringAsFixed(0)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          ]),
        ),

        const SizedBox(height: 24),
        _sectionLabel('Breakdown'),
        const SizedBox(height: 12),

        _RevenueRow(
          label: 'Painter subscriptions',
          sub: '$activePainters × \$${painterPrice.toStringAsFixed(0)}/mo',
          value: '\$${painterMrr.toStringAsFixed(2)}',
          icon: Icons.format_paint_outlined,
        ),
        _RevenueRow(
          label: 'User subscriptions',
          sub: '$premiumUsers × \$${userPrice.toStringAsFixed(2)}/mo',
          value: '\$${userMrr.toStringAsFixed(2)}',
          icon: Icons.people_outline,
        ),

        const SizedBox(height: 24),
        _sectionLabel('Projections'),
        const SizedBox(height: 12),

        _StatRow('MRR (current)',  '\$${totalMrr.toStringAsFixed(2)}'),
        _StatRow('ARR (×12)',      '\$${totalArr.toStringAsFixed(2)}'),
        _StatRow('3-month target', '\$${(totalMrr * 3).toStringAsFixed(2)}'),
        _StatRow('Annual target',  '\$${totalArr.toStringAsFixed(2)}'),

        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: const Text(
            'Revenue is estimated based on active painter subscriptions (\$29/mo) '
            'and users with ≥2 projects (assumed premium at \$9.99/mo). '
            'Connect Stripe for exact figures.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label, value, sub;
  final IconData icon;
  final bool highlight;
  const _KpiCard({
    required this.label, required this.value,
    required this.sub,   required this.icon,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
          color: highlight ? AppColors.accent : AppColors.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: AppColors.accent, size: 20),
      const Spacer(),
      Text(value, style: GoogleFonts.playfairDisplay(
          color: AppColors.textPrimary, fontSize: 26,
          fontWeight: FontWeight.w700)),
      Text(label, style: const TextStyle(
          color: AppColors.textSecondary, fontSize: 11)),
      Text(sub, style: TextStyle(
          color: highlight ? AppColors.accent : AppColors.textSecondary,
          fontSize: 11, fontWeight: FontWeight.w600)),
    ]),
  );
}

class _BigRevenueCard extends StatelessWidget {
  final Map<String, dynamic> revenue;
  const _BigRevenueCard({required this.revenue});

  @override
  Widget build(BuildContext context) {
    final mrr = (revenue['total_mrr'] as num?)?.toDouble() ?? 0;
    final arr = (revenue['total_arr'] as num?)?.toDouble() ?? 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.attach_money, color: AppColors.accent, size: 28),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('\$${mrr.toStringAsFixed(2)} MRR',
              style: GoogleFonts.playfairDisplay(
                  color: AppColors.accent, fontSize: 22,
                  fontWeight: FontWeight.w700)),
          Text('\$${arr.toStringAsFixed(0)} ARR',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ]),
      ]),
    );
  }
}

class _InventoryCard extends StatelessWidget {
  final Map<String, dynamic> inv;
  const _InventoryCard({required this.inv});

  @override
  Widget build(BuildContext context) {
    final total     = inv['total_colors'] as int? ?? 0;
    final byVendor  = (inv['by_vendor'] as Map<String, dynamic>?) ?? {};
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.palette_outlined, color: AppColors.accent, size: 18),
          const SizedBox(width: 8),
          Text('$total total paint colors',
              style: const TextStyle(color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        ...byVendor.entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(child: Text(e.key,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
            Text('${e.value}',
                style: const TextStyle(color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        )),
        if (total == 0)
          const Text('No colors seeded yet',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      ]),
    );
  }
}

class _RevenueRow extends StatelessWidget {
  final String label, sub, value;
  final IconData icon;
  const _RevenueRow({required this.label, required this.sub,
      required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(children: [
      Icon(icon, color: AppColors.accent, size: 20),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(
            color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        Text(sub, style: const TextStyle(
            color: AppColors.textSecondary, fontSize: 12)),
      ])),
      Text(value, style: const TextStyle(
          color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 16)),
    ]),
  );
}

class _StatRow extends StatelessWidget {
  final String label, value;
  const _StatRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(children: [
      Expanded(child: Text(label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14))),
      Text(value, style: const TextStyle(
          color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
    ]),
  );
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

Widget _sectionLabel(String text) => Text(text.toUpperCase(),
    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11,
        fontWeight: FontWeight.w700, letterSpacing: 1.2));
