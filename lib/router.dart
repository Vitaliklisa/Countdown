import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/models.dart';
import 'providers/app_providers.dart';
import 'screens/event_detail_screen.dart';
import 'screens/event_editor_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';

/// Route names, kept in one place so navigation calls never use raw strings.
class Routes {
  const Routes._();

  static const home = '/';
  static const login = '/login';
  static const settings = '/settings';
  static const newEvent = '/event/new';
  static const eventDetail = '/event';
}

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.home,
    // The redirect guard keeps the sign-in screen reachable while signed out
    // but never blocks the countdown list: a visitor can browse and create
    // locally, and is only asked to sign in when they share or sync.
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      if (auth.isLoading) return null;
      final signedIn = auth.valueOrNull != null;
      final goingToLogin = state.matchedLocation == Routes.login;

      if (signedIn && goingToLogin) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.home,
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: Routes.login,
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.settings,
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: Routes.newEvent,
        name: 'newEvent',
        builder: (context, state) => EventEditorScreen(
          event: state.extra is CountdownEvent ? state.extra as CountdownEvent : null,
        ),
      ),
      // NOTE: the more specific `/:id/edit` route must be declared BEFORE
      // `/:id`. go_router matches in declaration order, so with the reverse
      // order every `/event/123` would match the edit route first and open the
      // editor instead of the detail screen.
      GoRoute(
        path: '${Routes.eventDetail}/:id/edit',
        name: 'editEvent',
        builder: (context, state) => EventEditorScreen(
          event: state.extra is CountdownEvent ? state.extra as CountdownEvent : null,
        ),
      ),
      GoRoute(
        path: '${Routes.eventDetail}/:id',
        name: 'eventDetail',
        builder: (context, state) => EventDetailScreen(
          eventId: state.pathParameters['id']!,
          startInEditMode: state.uri.queryParameters['edit'] == '1',
        ),
      ),
    ],
  );
});
