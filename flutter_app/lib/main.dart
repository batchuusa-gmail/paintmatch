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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  runApp(const PaintMatchApp());
}

final GoRouter _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/loading', builder: (_, state) {
      final file = state.extra as dynamic;
      return AnalysisLoadingScreen(imageFile: file);
    }),
    GoRoute(path: '/palette', builder: (_, state) {
      final args = state.extra as Map<String, dynamic>;
      return PaletteSuggestionsScreen(
        imageFile: args['imageFile'],
        analysis: args['analysis'],
      );
    }),
    GoRoute(path: '/preview', builder: (_, state) {
      final args = state.extra as Map<String, dynamic>;
      return RoomPreviewScreen(
        originalImageUrl: args['originalImageUrl'],
        renderedImageUrl: args['renderedImageUrl'],
        selectedHex: args['selectedHex'],
        selectedColorName: args['selectedColorName'],
        imageFile: args['imageFile'],
        wallHex: args['wallHex'] as String?,
      );
    }),
    GoRoute(path: '/projects', builder: (_, __) => const AuthWrapper(
      child: ProjectBoardScreen(),
    )),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
  ],
);

class PaintMatchApp extends StatelessWidget {
  const PaintMatchApp({super.key});

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
