import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../../services/painter_service.dart';

class PainterDirectoryScreen extends StatefulWidget {
  const PainterDirectoryScreen({super.key});

  @override
  State<PainterDirectoryScreen> createState() =>
      _PainterDirectoryScreenState();
}

class _PainterDirectoryScreenState extends State<PainterDirectoryScreen> {
  List<PainterProfile>? _painters;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await PainterService().getActivePainters();
      if (mounted) setState(() => _painters = list);
    } catch (_) {
      if (mounted) setState(() => _painters = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Find a Painter',
            style: GoogleFonts.playfairDisplay(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : (_painters == null || _painters!.isEmpty)
              ? _EmptyDirectory()
              : RefreshIndicator(
                  color: AppColors.accent,
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _painters!.length,
                    itemBuilder: (_, i) => _PainterCard(
                      painter: _painters![i],
                      onTap: () => _showPainterDetail(_painters![i]),
                    ),
                  ),
                ),
    );
  }

  void _showPainterDetail(PainterProfile painter) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PainterDetailSheet(painter: painter),
    );
  }
}

// ─── Painter card ─────────────────────────────────────────────────────────────

class _PainterCard extends StatelessWidget {
  final PainterProfile painter;
  final VoidCallback onTap;
  const _PainterCard({required this.painter, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header row
          Row(children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                color: AppColors.accentDim,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.business,
                  color: AppColors.accent, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Expanded(
                  child: Text(painter.companyName,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (painter.isVerified) ...[
                  const Icon(Icons.verified,
                      color: AppColors.accent, size: 15),
                  const SizedBox(width: 4),
                ],
                if (painter.isInsured) ...[
                  const Icon(Icons.shield,
                      color: AppColors.accent, size: 14),
                ],
              ]),
              const SizedBox(height: 2),
              Text(painter.contactName,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ])),
            // Rating
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Row(children: [
                const Icon(Icons.star_rounded,
                    color: AppColors.accent, size: 14),
                const SizedBox(width: 2),
                Text(painter.avgRating.toStringAsFixed(1),
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ]),
              Text('(${painter.totalReviews})',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 10)),
            ]),
          ]),

          const SizedBox(height: 12),

          // Bio
          if (painter.bio.isNotEmpty)
            Text(painter.bio,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),

          const SizedBox(height: 10),

          // Specialties chips
          if (painter.specialties.isNotEmpty)
            Wrap(spacing: 6, runSpacing: 6,
                children: painter.specialties.take(3).map((s) =>
                    _chip(_capitalize(s))).toList()),

          if (painter.serviceAreas.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.location_on_outlined,
                  color: AppColors.textSecondary, size: 13),
              const SizedBox(width: 4),
              Expanded(
                child: Text(painter.serviceAreas.take(3).join(', '),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.accentDim,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: const TextStyle(
                color: AppColors.accent,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      );

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ─── Painter detail sheet ─────────────────────────────────────────────────────

class _PainterDetailSheet extends StatefulWidget {
  final PainterProfile painter;
  const _PainterDetailSheet({required this.painter});

  @override
  State<_PainterDetailSheet> createState() => _PainterDetailSheetState();
}

class _PainterDetailSheetState extends State<_PainterDetailSheet> {
  final _nameCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _sending = false;
  bool _sent    = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendLead() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        _messageCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill name, email, and message')));
      return;
    }
    setState(() => _sending = true);
    try {
      await PainterService().sendLead(
        painterId:    widget.painter.id,
        contactName:  _nameCtrl.text.trim(),
        contactEmail: _emailCtrl.text.trim(),
        contactPhone: _phoneCtrl.text.trim(),
        message:      _messageCtrl.text.trim(),
      );
      if (mounted) setState(() { _sent = true; _sending = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.painter;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
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

          // Profile header
          Row(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                  color: AppColors.accentDim, shape: BoxShape.circle),
              child: const Icon(Icons.business,
                  color: AppColors.accent, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(p.companyName,
                  style: GoogleFonts.playfairDisplay(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Row(children: [
                if (p.isVerified) ...[
                  const Icon(Icons.verified,
                      color: AppColors.accent, size: 14),
                  const SizedBox(width: 4),
                  const Text('Verified',
                      style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                ],
                if (p.isInsured) ...[
                  const Icon(Icons.shield,
                      color: AppColors.accent, size: 13),
                  const SizedBox(width: 3),
                  const Text('Insured',
                      style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ]),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Row(children: [
                const Icon(Icons.star_rounded,
                    color: AppColors.accent, size: 16),
                const SizedBox(width: 2),
                Text(p.avgRating.toStringAsFixed(1),
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ]),
              Text('${p.totalReviews} reviews',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 10)),
            ]),
          ]),

          const SizedBox(height: 16),
          if (p.bio.isNotEmpty) ...[
            Text(p.bio,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.5)),
            const SizedBox(height: 14),
          ],

          // Details
          if (p.serviceAreas.isNotEmpty) _detailRow(
              Icons.location_on_outlined, p.serviceAreas.join(', ')),
          _detailRow(Icons.work_outline,
              '${p.yearsExperience} year${p.yearsExperience == 1 ? '' : 's'} experience'),
          if (p.specialties.isNotEmpty)
            _detailRow(Icons.format_paint_outlined,
                p.specialties.map(_capitalize).join(', ')),

          const SizedBox(height: 20),
          const Divider(color: AppColors.border),
          const SizedBox(height: 16),

          // Contact form or success
          if (_sent) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.accentDim,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.4)),
              ),
              child: Column(children: [
                const Icon(Icons.check_circle_outline,
                    color: AppColors.accent, size: 36),
                const SizedBox(height: 10),
                Text('Message Sent!',
                    style: GoogleFonts.playfairDisplay(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('${p.contactName} will be in touch soon.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              ]),
            ),
          ] else ...[
            Text('Request a Quote',
                style: GoogleFonts.playfairDisplay(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            _inputField(_nameCtrl, 'Your Name', Icons.person_outlined),
            const SizedBox(height: 12),
            _inputField(_emailCtrl, 'Your Email', Icons.email_outlined,
                keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 12),
            _inputField(_phoneCtrl, 'Your Phone (optional)',
                Icons.phone_outlined,
                keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            TextFormField(
              controller: _messageCtrl,
              maxLines: 3,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                  hintText: 'Describe your project…'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _sending ? null : _sendLead,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: _sending
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Text('Send Request',
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, color: AppColors.textSecondary, size: 15),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ),
      ]),
    );
  }

  Widget _inputField(TextEditingController ctrl, String hint, IconData icon,
      {TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyDirectory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.business_outlined,
                size: 36, color: AppColors.accent),
          ),
          const SizedBox(height: 20),
          const Text('No painters listed yet',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'Check back soon — painters in your area will appear here',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 13, height: 1.5),
          ),
        ]),
      ),
    );
  }
}
