import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_project.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._();
  factory SupabaseService() => _instance;
  SupabaseService._();

  SupabaseClient get _sb => Supabase.instance.client;

  User? get currentUser => _sb.auth.currentUser;
  bool get isSignedIn => currentUser != null;

  // -------------------------------------------------------------------------
  // Auth
  // -------------------------------------------------------------------------
  Future<AuthResponse> signUp(String email, String password) =>
      _sb.auth.signUp(email: email, password: password);

  Future<AuthResponse> signIn(String email, String password) =>
      _sb.auth.signInWithPassword(email: email, password: password);

  Future<void> signInWithGoogle() =>
      _sb.auth.signInWithOAuth(OAuthProvider.google);

  Future<void> signOut() => _sb.auth.signOut();

  Future<void> resetPassword(String email) =>
      _sb.auth.resetPasswordForEmail(email);

  Stream<AuthState> get authStateChanges => _sb.auth.onAuthStateChange;

  // -------------------------------------------------------------------------
  // User Projects
  // -------------------------------------------------------------------------
  Future<List<UserProject>> getUserProjects() async {
    final userId = currentUser?.id;
    if (userId == null) return [];

    final response = await _sb
        .from('user_projects')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List<dynamic>)
        .map((e) => UserProject.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<UserProject> saveProject({
    required String projectName,
    String? roomImageUrl,
    String? renderedImageUrl,
    String? selectedHex,
    List<Map<String, dynamic>> vendorPicks = const [],
  }) async {
    final userId = currentUser?.id;
    if (userId == null) throw Exception('Not signed in');

    final response = await _sb.from('user_projects').insert({
      'user_id': userId,
      'project_name': projectName,
      'room_image_url': roomImageUrl,
      'rendered_image_url': renderedImageUrl,
      'selected_hex': selectedHex,
      'vendor_picks': vendorPicks,
    }).select().single();

    return UserProject.fromJson(response);
  }

  Future<void> deleteProject(String projectId) async {
    await _sb.from('user_projects').delete().eq('id', projectId);
  }

  Future<void> renameProject(String projectId, String newName) async {
    await _sb
        .from('user_projects')
        .update({'project_name': newName})
        .eq('id', projectId);
  }
}
