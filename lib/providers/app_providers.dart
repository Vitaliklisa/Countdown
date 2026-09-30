import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/circles.dart';
import '../core/models.dart';
import '../services/auth_service.dart';
import '../services/event_repository.dart';

/// Overridden in `main()` (and in tests) with a ready-to-use instance.
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final eventRepositoryProvider =
    Provider<EventRepository>((ref) => EventRepository());

/// The signed-in user, or `null`. `AsyncValue.loading` covers the first frame,
/// before Firebase has restored the persisted session.
///
/// `autoDispose` is deliberate under Riverpod 3: when the last listener goes
/// away (the app is backgrounded and the router's listener is the only one
/// left), the Firebase auth subscription is torn down instead of being kept
/// alive for the process lifetime, which is what avoids a leaked listener
/// across hot restart.
final activeAuthStateProvider = StreamProvider<AppUser?>((ref) {
  ref.keepAlive();
  return ref.watch(authServiceProvider).authStateChanges();
}, isAutoDispose: true);

/// Just the user, with loading collapsed to `null` for widgets that only need
/// to branch on signed-in vs signed-out.
final currentUserProvider = Provider<AppUser?>((ref) {
  return ref.watch(activeAuthStateProvider).value;
});

/// All countdowns visible to the signed-in user, nearest first.
///
/// A local-only visitor (no account) gets an empty list rather than an error:
/// there is nothing to sync, and the UI invites them to sign in.
final eventsProvider = StreamProvider<List<CountdownEvent>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(const []);
  return ref.watch(eventRepositoryProvider).watchEvents(user.id);
});

/// Pending invitations addressed to the signed-in user's email.
final invitationsProvider = StreamProvider<List<Invitation>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null || user.email.isEmpty) return Stream.value(const []);
  return ref.watch(eventRepositoryProvider).watchInvitations(user.email);
});

/// Pending circle invitations addressed to the signed-in user's email.
final circleInvitationsProvider = StreamProvider<List<CircleInvitation>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null || user.email.isEmpty) return Stream.value(const []);
  return ref.watch(eventRepositoryProvider).watchCircleInvitations(user.email);
});

/// Circles the signed-in user belongs to.
final circlesProvider = StreamProvider<List<Circle>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(const []);
  return ref.watch(eventRepositoryProvider).watchCircles(user.id);
});

/// Members of one circle, hydrated with names and avatars.
final circleMembersProvider =
    StreamProvider.family<List<CircleMember>, String>((ref, circleId) {
  return ref.watch(eventRepositoryProvider).watchCircleMembers(circleId);
});

/// Answers to invitations the signed-in user sent — the "your friend joined"
/// feedback.
final responsesProvider = StreamProvider<List<InvitationResponse>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(const []);
  return ref.watch(eventRepositoryProvider).watchResponses(user.id);
});

/// How many answers are still unread, for the badge on the home screen.
final unreadResponseCountProvider = Provider<int>((ref) {
  final responses = ref.watch(responsesProvider).value ?? const [];
  return responses.where((r) => !r.read).length;
});

/// Everything awaiting the signed-in user's answer: countdown invites and
/// circle invites, in one list for a single inbox.
final pendingInviteCountProvider = Provider<int>((ref) {
  final events = ref.watch(invitationsProvider).value ?? const [];
  final circles = ref.watch(circleInvitationsProvider).value ?? const [];
  return events.length + circles.length;
});

/// Participants of one event, live.
final participantsProvider =
    StreamProvider.family<List<Participant>, String>((ref, eventId) {
  return ref.watch(eventRepositoryProvider).watchParticipants(eventId);
});

/// Notes on one event, live, oldest first.
final notesProvider =
    StreamProvider.family<List<EventNote>, String>((ref, eventId) {
  return ref.watch(eventRepositoryProvider).watchNotes(eventId);
});

/// Which countdown is pinned as the hero. `null` means "pick automatically":
/// the soonest upcoming one.
///
/// Riverpod 3 retired `StateProvider`; a plain `Notifier` is the replacement and
/// gives the same `ref.read(...).set(id)` ergonomics at the call sites.
class SelectedEventId extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) => state = id;
}

final selectedEventIdProvider =
    NotifierProvider<SelectedEventId, String?>(SelectedEventId.new);

/// The countdown shown on the home screen.
///
/// Follows the web app's `pickFeatured`: an explicit selection wins, otherwise
/// the soonest future event, and if everything is in the past, the most recent
/// one.
final featuredEventProvider = Provider<CountdownEvent?>((ref) {
  final events = ref.watch(eventsProvider).value ?? const <CountdownEvent>[];
  if (events.isEmpty) return null;

  final selectedId = ref.watch(selectedEventIdProvider);
  if (selectedId != null) {
    for (final event in events) {
      if (event.id == selectedId) return event;
    }
  }

  final now = DateTime.now();
  final upcoming = events.where((e) => e.at.isAfter(now)).toList()
    ..sort((a, b) => a.at.compareTo(b.at));
  if (upcoming.isNotEmpty) return upcoming.first;

  final past = [...events]..sort((a, b) => b.at.compareTo(a.at));
  return past.first;
});

/// Ticks once a second so every countdown face updates in lockstep, and the
/// whole app re-renders from one timer instead of one per widget.
final clockProvider = StreamProvider<DateTime>((ref) {
  return Stream<DateTime>.periodic(
      const Duration(seconds: 1), (_) => DateTime.now()).asBroadcastStream();
});

/// Theme mode, persisted per device (not per account — appearance is a device
/// preference, and requiring a sign-in to pick light/dark would be odd).
///
/// Riverpod 3 retired `StateNotifierProvider`; `Notifier` is its successor and
/// removes the `state`-vs-`super` split that used to bite here.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.dark;

  void set(ThemeMode mode) => state = mode;

  void toggle() =>
      state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// Small helper so screens can run an action and show either a success or a
/// failure message without repeating try/catch.
Future<String?> runAction(
  BuildContext context,
  Future<void> Function() action, {
  String? successMessage,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
    if (successMessage != null) {
      messenger?.showSnackBar(SnackBar(content: Text(successMessage)));
    }
    return null;
  } on AuthFailure catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    return e.message;
  } on DataFailure catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    return e.message;
  } on FirebaseAuthException catch (e) {
    messenger?.showSnackBar(
        SnackBar(content: Text(e.message ?? 'Something went wrong.')));
    return e.message;
  } on FirebaseException catch (e) {
    final message = e.code == 'permission-denied'
        ? 'You do not have permission to do that.'
        : (e.message ?? 'Something went wrong.');
    messenger?.showSnackBar(SnackBar(content: Text(message)));
    return message;
  } catch (e) {
    messenger
        ?.showSnackBar(const SnackBar(content: Text('Something went wrong.')));
    return e.toString();
  }
}
