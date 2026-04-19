import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

class PainterProfile {
  final String id;
  final String userId;
  final String companyName;
  final String contactName;
  final String phone;
  final String email;
  final String bio;
  final List<String> serviceAreas;   // city names / zip codes
  final List<String> specialties;    // 'interior', 'exterior', 'commercial', 'residential'
  final int yearsExperience;
  final String? licenseNumber;
  final bool isInsured;
  final bool isVerified;
  final bool subscriptionActive;
  final double avgRating;
  final int totalReviews;
  final DateTime createdAt;

  const PainterProfile({
    required this.id,
    required this.userId,
    required this.companyName,
    required this.contactName,
    required this.phone,
    required this.email,
    required this.bio,
    required this.serviceAreas,
    required this.specialties,
    required this.yearsExperience,
    this.licenseNumber,
    required this.isInsured,
    required this.isVerified,
    required this.subscriptionActive,
    required this.avgRating,
    required this.totalReviews,
    required this.createdAt,
  });

  factory PainterProfile.fromJson(Map<String, dynamic> j) => PainterProfile(
        id:                  j['id'] as String,
        userId:              j['user_id'] as String,
        companyName:         j['company_name'] as String? ?? '',
        contactName:         j['contact_name'] as String? ?? '',
        phone:               j['phone'] as String? ?? '',
        email:               j['email'] as String? ?? '',
        bio:                 j['bio'] as String? ?? '',
        serviceAreas:        List<String>.from(j['service_areas'] as List? ?? []),
        specialties:         List<String>.from(j['specialties'] as List? ?? []),
        yearsExperience:     (j['years_experience'] as int?) ?? 0,
        licenseNumber:       j['license_number'] as String?,
        isInsured:           j['is_insured'] as bool? ?? false,
        isVerified:          j['is_verified'] as bool? ?? false,
        subscriptionActive:  j['subscription_active'] as bool? ?? false,
        avgRating:           (j['avg_rating'] as num?)?.toDouble() ?? 0.0,
        totalReviews:        (j['total_reviews'] as int?) ?? 0,
        createdAt:           DateTime.parse(j['created_at'] as String),
      );
}

class PainterLead {
  final String id;
  final String painterId;
  final String? homeownerId;
  final String? projectId;
  final String message;
  final String contactName;
  final String contactEmail;
  final String contactPhone;
  final String status;   // 'new' | 'viewed' | 'responded' | 'closed'
  final DateTime createdAt;

  const PainterLead({
    required this.id,
    required this.painterId,
    this.homeownerId,
    this.projectId,
    required this.message,
    required this.contactName,
    required this.contactEmail,
    required this.contactPhone,
    required this.status,
    required this.createdAt,
  });

  factory PainterLead.fromJson(Map<String, dynamic> j) => PainterLead(
        id:           j['id'] as String,
        painterId:    j['painter_id'] as String,
        homeownerId:  j['homeowner_id'] as String?,
        projectId:    j['project_id'] as String?,
        message:      j['message'] as String? ?? '',
        contactName:  j['contact_name'] as String? ?? '',
        contactEmail: j['contact_email'] as String? ?? '',
        contactPhone: j['contact_phone'] as String? ?? '',
        status:       j['status'] as String? ?? 'new',
        createdAt:    DateTime.parse(j['created_at'] as String),
      );

  bool get isNew => status == 'new';
}

// ─── Service ─────────────────────────────────────────────────────────────────

class PainterService {
  static final PainterService _i = PainterService._();
  factory PainterService() => _i;
  PainterService._();

  SupabaseClient get _sb => Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  // ── Profile ────────────────────────────────────────────────────────────────

  Future<PainterProfile?> myProfile() async {
    if (_uid == null) return null;
    final res = await _sb
        .from('painter_profiles')
        .select()
        .eq('user_id', _uid!)
        .maybeSingle();
    return res == null ? null : PainterProfile.fromJson(res);
  }

  Future<PainterProfile> createProfile({
    required String companyName,
    required String contactName,
    required String phone,
    required String email,
    required String bio,
    required List<String> serviceAreas,
    required List<String> specialties,
    required int yearsExperience,
    String? licenseNumber,
    required bool isInsured,
  }) async {
    final res = await _sb.from('painter_profiles').insert({
      'user_id':          _uid,
      'company_name':     companyName,
      'contact_name':     contactName,
      'phone':            phone,
      'email':            email,
      'bio':              bio,
      'service_areas':    serviceAreas,
      'specialties':      specialties,
      'years_experience': yearsExperience,
      'license_number':   licenseNumber,
      'is_insured':       isInsured,
    }).select().single();
    return PainterProfile.fromJson(res);
  }

  Future<void> updateProfile(String id, Map<String, dynamic> updates) async {
    await _sb.from('painter_profiles').update(updates).eq('id', id);
  }

  // ── Directory (homeowner view) ─────────────────────────────────────────────

  Future<List<PainterProfile>> getActivePainters() async {
    final res = await _sb
        .from('painter_profiles')
        .select()
        .eq('subscription_active', true)
        .order('is_verified', ascending: false)
        .order('avg_rating', ascending: false);
    return (res as List).map((e) => PainterProfile.fromJson(e)).toList();
  }

  // ── Leads ──────────────────────────────────────────────────────────────────

  Future<void> sendLead({
    required String painterId,
    required String contactName,
    required String contactEmail,
    required String contactPhone,
    required String message,
    String? projectId,
  }) async {
    await _sb.from('painter_leads').insert({
      'painter_id':    painterId,
      'homeowner_id':  _uid,
      'project_id':    projectId,
      'contact_name':  contactName,
      'contact_email': contactEmail,
      'contact_phone': contactPhone,
      'message':       message,
      'status':        'new',
    });
  }

  Future<List<PainterLead>> myLeads() async {
    final profile = await myProfile();
    if (profile == null) return [];
    final res = await _sb
        .from('painter_leads')
        .select()
        .eq('painter_id', profile.id)
        .order('created_at', ascending: false);
    return (res as List).map((e) => PainterLead.fromJson(e)).toList();
  }

  Future<void> markLeadViewed(String leadId) async {
    await _sb
        .from('painter_leads')
        .update({'status': 'viewed'})
        .eq('id', leadId)
        .eq('status', 'new');
  }

  // ── Role helpers (stored in Supabase user metadata) ───────────────────────

  static const rolePainter    = 'painter';
  static const roleHomeowner  = 'homeowner';

  String? get currentRole =>
      _sb.auth.currentUser?.userMetadata?['role'] as String?;

  bool get isPainter => currentRole == rolePainter;
}
