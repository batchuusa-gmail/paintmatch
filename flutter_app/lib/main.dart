import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'screens/auth/auth_wrapper.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/analysis_loading_screen.dart';
import 'screens/palette_suggestions_screen.dart';
import 'screens/room_preview_screen.dart';
import 'screens/project_board_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/paywall_screen.dart';
import 'screens/painter/painter_registration_screen.dart';
import 'screens/painter/painter_dashboard_screen.dart';
import 'screens/painter/painter_directory_screen.dart';
import 'screens/painter/painter_paywall_screen.dart';
import 'screens/admin_screen.dart';
import 'services/subscription_service.dart';
import 'models/paint_color.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  // Start listening for purchase updates immediately
  SubscriptionService().listenToPurchaseUpdates();

  runApp(const PaintMatchApp());
}

final GoRouter _router = GoRouter(
  initialLocation: '/',
  // Redirect to onboarding if user hasn't registered yet
  redirect: (context, state) async {
    final onboarded = await SubscriptionService().hasCompletedOnboarding();
    if (!onboarded && state.matchedLocation != '/onboarding') {
      return '/onboarding';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/',          builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
    GoRoute(path: '/paywall',    builder: (_, state) {
      final trialEnded = (state.extra as bool?) ?? false;
      return PaywallScreen(trialEnded: trialEnded);
    }),
    GoRoute(path: '/loading',    builder: (_, state) {
      final file = state.extra as dynamic;
      return AnalysisLoadingScreen(imageFile: file);
    }),
    GoRoute(path: '/palette',    builder: (_, state) {
      final args = state.extra as Map<String, dynamic>;
      return PaletteSuggestionsScreen(
        imageFile: args['imageFile'],
        analysis: args['analysis'],
      );
    }),
    GoRoute(path: '/preview',    builder: (_, state) {
      final args = state.extra as Map<String, dynamic>;
      return RoomPreviewScreen(
        originalImageUrl: args['originalImageUrl'],
        renderedImageUrl: args['renderedImageUrl'],
        selectedHex: args['selectedHex'],
        selectedColorName: args['selectedColorName'],
        imageFile: args['imageFile'],
        wallHex: args['wallHex'] as String?,
        vendorMatches: args['vendorMatches'] as List<PaintColor>?,
      );
    }),
    GoRoute(path: '/projects',   builder: (_, __) => const AuthWrapper(
      child: ProjectBoardScreen(),
    )),
    GoRoute(path: '/login',      builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/signup',     builder: (_, state) {
      final role = state.uri.queryParameters['role'];
      return SignupScreen(role: role);
    }),
    // Painter role routes
    GoRoute(path: '/painter/register',  builder: (_, __) => const PainterRegistrationScreen()),
    GoRoute(path: '/painter/dashboard', builder: (_, __) => const PainterDashboardScreen()),
    GoRoute(path: '/painter/directory', builder: (_, __) => const PainterDirectoryScreen()),
    GoRoute(path: '/painter/paywall',   builder: (_, __) => const PainterPaywallScreen()),
    GoRoute(path: '/admin',             builder: (_, __) => const AdminScreen()),
  ],
);

class PaintMatchApp extends StatefulWidget {
  const PaintMatchApp({super.key});

  @override
  State<PaintMatchApp> createState() => _PaintMatchAppState();
}

class _PaintMatchAppState extends State<PaintMatchApp> {
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _handleDeepLinks();
  }

  /// Listen for paintmatch://auth/callback deep links.
  /// Supabase sends the user here after they tap the confirmation email.
  void _handleDeepLinks() {
    final appLinks = AppLinks();

    // Handle link that launched the app from cold start
    appLinks.getInitialLink().then((uri) {
      if (uri != null) _processAuthLink(uri);
    });

    // Handle links while app is already running
    _linkSub = appLinks.uriLinkStream.listen(
      _processAuthLink,
      onError: (_) {},
    );
  }

  Future<void> _processAuthLink(Uri uri) async {
    if (uri.scheme != 'paintmatch') return;
    try {
      // Let Supabase parse the token from the URL fragment / query params
      await Supabase.instance.client.auth.getSessionFromUrl(uri);
      // Session is now active — mark onboarding done and go home
      await SubscriptionService().markOnboardingComplete();
      if (mounted) _router.go('/');
    } catch (_) {
      // Invalid or expired token — send to login so user can try again
      if (mounted) _router.go('/login');
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PaintMatch',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: _router,
    );
  }
}
