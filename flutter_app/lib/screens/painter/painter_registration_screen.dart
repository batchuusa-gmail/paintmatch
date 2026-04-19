import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../../services/painter_service.dart';
import '../../services/supabase_service.dart';
import 'package:google_fonts/google_fonts.dart';

class PainterRegistrationScreen extends StatefulWidget {
  const PainterRegistrationScreen({super.key});

  @override
  State<PainterRegistrationScreen> createState() =>
      _PainterRegistrationScreenState();
}

class _PainterRegistrationScreenState
    extends State<PainterRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  int _step = 0; // 0 = business info, 1 = service details, 2 = confirm

  // Step 0
  final _companyCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _bioCtrl     = TextEditingController();

  // Step 1
  final _licenseCtrl      = TextEditingController();
  final _areasCtrl        = TextEditingController(); // comma-separated
  final _yearsCtrl        = TextEditingController(text: '1');
  bool  _isInsured        = false;
  final List<String> _selectedSpecialties = [];

  static const _specialtyOptions = [
    'Interior',
    'Exterior',
    'Commercial',
    'Residential',
    'Cabinet',
    'Deck & Fence',
  ];

  bool _saving = false;

  @override
  void dispose() {
    _companyCtrl.dispose();
    _contactCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _bioCtrl.dispose();
    _licenseCtrl.dispose();
    _areasCtrl.dispose();
    _yearsCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmExit(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Exit Registration?',
            style: GoogleFonts.playfairDisplay(color: AppColors.textPrimary)),
        content: const Text(
          'Your painter profile is not complete yet. You will be signed out.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continue',
                style: TextStyle(color: AppColors.accent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Exit & Sign Out',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await SupabaseService().signOut();
      if (context.mounted) context.go('/');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Guard: must be signed in for RLS to allow the INSERT
    if (!SupabaseService().isSignedIn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session expired — please sign in again.'),
            backgroundColor: AppColors.error,
          ),
        );
        context.go('/login');
      }
      return;
    }

    setState(() => _saving = true);

    try {
      final areas = _areasCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      await PainterService().createProfile(
        companyName:      _companyCtrl.text.trim(),
        contactName:      _contactCtrl.text.trim(),
        phone:            _phoneCtrl.text.trim(),
        email:            _emailCtrl.text.trim(),
        bio:              _bioCtrl.text.trim(),
        serviceAreas:     areas,
        specialties:      _selectedSpecialties.map((s) => s.toLowerCase()).toList(),
        yearsExperience:  int.tryParse(_yearsCtrl.text) ?? 1,
        licenseNumber:    _licenseCtrl.text.trim().isEmpty
                              ? null
                              : _licenseCtrl.text.trim(),
        isInsured:        _isInsured,
      );

      if (mounted) context.go('/painter/paywall');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Painter Profile',
            style: GoogleFonts.playfairDisplay(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        leading: _step > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: AppColors.textSecondary, size: 18),
                onPressed: () => setState(() => _step--),
              )
            : IconButton(
                icon: const Icon(Icons.close,
                    color: AppColors.textSecondary, size: 20),
                onPressed: () => _confirmExit(context),
              ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StepIndicator(step: _step, total: 3),
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _step == 0
                      ? _buildStep0()
                      : _step == 1
                          ? _buildStep1()
                          : _buildStep2(),
                ),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ── Step 0: Business info ────────────────────────────────────────────────────

  Widget _buildStep0() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Business Information'),
      const SizedBox(height: 20),
      _field(_companyCtrl, 'Company Name', Icons.business_outlined,
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
      const SizedBox(height: 16),
      _field(_contactCtrl, 'Contact Name', Icons.person_outlined,
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
      const SizedBox(height: 16),
      _field(_phoneCtrl, 'Phone Number', Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
      const SizedBox(height: 16),
      _field(_emailCtrl, 'Business Email', Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Required';
            if (!v.contains('@')) return 'Enter valid email';
            return null;
          }),
      const SizedBox(height: 16),
      _multilineField(_bioCtrl, 'Tell homeowners about your work…',
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
    ]);
  }

  // ── Step 1: Service details ───────────────────────────────────────────────

  Widget _buildStep1() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Service Details'),
      const SizedBox(height: 20),

      // Specialties
      const Text('Specialties',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: _specialtyOptions.map((s) {
        final sel = _selectedSpecialties.contains(s);
        return GestureDetector(
          onTap: () => setState(() {
            if (sel) _selectedSpecialties.remove(s);
            else _selectedSpecialties.add(s);
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? AppColors.accentDim : AppColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: sel ? AppColors.accent : AppColors.border),
            ),
            child: Text(s,
                style: TextStyle(
                    color: sel ? AppColors.accent : AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
          ),
        );
      }).toList()),

      const SizedBox(height: 24),
      _field(_areasCtrl, 'Service Areas (city, zip, comma-separated)',
          Icons.location_on_outlined),
      const SizedBox(height: 16),
      _field(_yearsCtrl, 'Years of Experience', Icons.workspace_premium_outlined,
          keyboardType: TextInputType.number),
      const SizedBox(height: 16),
      _field(_licenseCtrl, 'License Number (optional)', Icons.badge_outlined),
      const SizedBox(height: 20),

      // Insured toggle
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          const Icon(Icons.shield_outlined, color: AppColors.accent, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Insured', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
              Text('Displays a verified badge on your profile',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ]),
          ),
          Switch.adaptive(
            value: _isInsured,
            activeColor: AppColors.accent,
            onChanged: (v) => setState(() => _isInsured = v),
          ),
        ]),
      ),
    ]);
  }

  // ── Step 2: Confirmation ──────────────────────────────────────────────────

  Widget _buildStep2() {
    final areas = _areasCtrl.text.trim().isEmpty
        ? 'Not specified'
        : _areasCtrl.text.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Review & Subscribe'),
      const SizedBox(height: 20),

      // Profile preview card
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                  color: AppColors.accentDim, shape: BoxShape.circle),
              child: const Icon(Icons.business, color: AppColors.accent, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_companyCtrl.text.trim(),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700, fontSize: 16)),
              Text(_contactCtrl.text.trim(),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ])),
            if (_isInsured) ...[
              const Icon(Icons.verified, color: AppColors.accent, size: 18),
              const SizedBox(width: 4),
              const Text('Insured',
                  style: TextStyle(
                      color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ]),
          const Divider(height: 24, color: AppColors.border),
          _reviewRow('Phone', _phoneCtrl.text.trim()),
          _reviewRow('Email', _emailCtrl.text.trim()),
          _reviewRow('Specialties', _selectedSpecialties.isEmpty
              ? 'None selected'
              : _selectedSpecialties.join(', ')),
          _reviewRow('Service Areas', areas),
          _reviewRow('Experience',
              '${_yearsCtrl.text.trim()} year(s)'),
          if (_licenseCtrl.text.trim().isNotEmpty)
            _reviewRow('License', _licenseCtrl.text.trim()),
        ]),
      ),

      const SizedBox(height: 28),

      // Pricing card
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.accent),
          gradient: LinearGradient(
            colors: [
              AppColors.accent.withValues(alpha: 0.12),
              AppColors.accent.withValues(alpha: 0.04),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.workspace_premium, color: AppColors.accent, size: 22),
            const SizedBox(width: 10),
            Text('Painter Pro',
                style: GoogleFonts.playfairDisplay(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 18)),
          ]),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('\$49.99',
                style: GoogleFonts.playfairDisplay(
                    color: AppColors.accent,
                    fontSize: 36,
                    fontWeight: FontWeight.w700)),
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(' / month',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            ),
          ]),
          const SizedBox(height: 4),
          const Text('Flat fee — no per-contract charges',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 16),
          ..._proPerks.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline,
                      color: AppColors.accent, size: 16),
                  const SizedBox(width: 8),
                  Text(p,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                ]),
              )),
        ]),
      ),
    ]);
  }

  static const _proPerks = [
    'Listed in homeowner painter directory',
    'Receive unlimited project leads',
    'Verified badge on your profile',
    'Cancel any time',
  ];

  // ── Bottom bar ────────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: _step < 2
          ? FilledButton(
              onPressed: () {
                if (_step == 0 && !_formKey.currentState!.validate()) return;
                setState(() => _step++);
              },
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: const Text('Continue',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16, color: Colors.black)),
            )
          : FilledButton(
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _saving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Text('Create Profile & Subscribe',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Colors.black)),
            ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _sectionTitle(String t) => Text(t,
      style: GoogleFonts.playfairDisplay(
          color: AppColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w600));

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        validator: validator,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
        ),
      );

  Widget _multilineField(
    TextEditingController ctrl,
    String hint, {
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: ctrl,
        maxLines: 3,
        validator: validator,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          alignLabelWithHint: true,
        ),
      );

  Widget _reviewRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
        ]),
      );
}

// ─── Step indicator ───────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int step;
  final int total;
  const _StepIndicator({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: List.generate(total, (i) {
          final active = i == step;
          final done   = i < step;
          return Expanded(
            child: Container(
              height: 3,
              margin: EdgeInsets.only(right: i < total - 1 ? 6 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: done || active ? AppColors.accent : AppColors.border,
              ),
            ),
          );
        }),
      ),
    );
  }
}
