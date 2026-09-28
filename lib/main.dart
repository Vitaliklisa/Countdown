import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'firebase_config.dart';
import 'providers/app_providers.dart';
import 'router.dart';
import 'services/auth_service.dart';
import 'services/event_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // On web the config must be supplied in code; on Android/iOS the native files
  // cover it. If web is missing its keys, show a page that says exactly what to
  // run rather than letting Firebase throw an opaque "API key not valid".
  if (kIsWeb && !hasWebFirebaseConfig) {
    runApp(const _MissingConfigApp());
    return;
  }

  // Firebase is initialised from the platform config files that `flutterfire
  // configure` generates: android/app/google-services.json,
  // ios/Runner/GoogleService-Info.plist, and `firebaseOptions` for web.
  // See `lib/firebase_config.dart` and the README.
  await Firebase.initializeApp(options: firebaseOptions);

  runApp(const ProviderScope(child: UntilApp()));
}

/// Shown on web when `flutterfire configure` has not been run yet.
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    const palette = AppPalette.dark;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(brightness: Brightness.dark),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Firebase is not configured for web yet',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: palette.fg,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'The Until project id is baked in, but the web API key and '
                    'app id are not. Run this once from the project root, then '
                    'rebuild:',
                    style: TextStyle(
                        fontSize: 14, height: 1.5, color: palette.muted),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: palette.border),
                    ),
                    child: const SelectableText(
                      'flutterfire configure --project=until-8ef15',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: Color(0xFF4FD1C5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'That writes lib/firebase_options.dart and the native config '
                    'files. Android and iOS already load theirs automatically.',
                    style: TextStyle(
                        fontSize: 13, height: 1.5, color: palette.subtle),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class UntilApp extends ConsumerWidget {
  const UntilApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Until',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(brightness: Brightness.light),
      darkTheme: AppTheme.build(brightness: Brightness.dark),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}

/// Overrides used by tests and by `main` before Firebase is reachable, so the
/// widget tree can be pumped without a live project.
List<Override> buildOverrides({
  AuthService? authService,
  EventRepository? repository,
}) =>
    [
      if (authService != null)
        authServiceProvider.overrideWithValue(authService),
      if (repository != null)
        eventRepositoryProvider.overrideWithValue(repository),
    ];
