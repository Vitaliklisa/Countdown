import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../core/countdown.dart';
import '../core/models.dart';

/// Why a write was refused, in words a user can act on.
class DataFailure implements Exception {
  const DataFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// All reads and writes for countdowns, backed by Cloud Firestore.
///
/// Collections (see `firestore.rules` for the enforced version of these rules):
///
/// ```
/// events/{eventId}
///   title, description, at, createdBy, createdAt, updatedAt
///   participants/{userId}   email, role, inviteStatus, displayName, photoUrl
///   notes/{noteId}          userId, text, createdAt, updatedAt
/// invitations/{inviteId}    eventId, invitedBy, inviteeEmail, role, status,
///                           createdAt, expiresAt, eventTitle
/// ```
///
/// A user sees an event when they created it or hold a participant row — the
/// same rule the web app expresses as `buildEventVisibilityWhereClause`. The
/// rules file is the authority; this service deliberately mirrors it so the
/// client fails fast with a readable message.
class EventRepository {
  EventRepository({FirebaseFirestore? firestore, Uuid? uuid})
      : _db = firestore ?? FirebaseFirestore.instance,
        _uuid = uuid ?? const Uuid();

  final FirebaseFirestore _db;
  final Uuid _uuid;

  CollectionReference<Map<String, dynamic>> get _events => _db.collection('events');
  CollectionReference<Map<String, dynamic>> get _invitations => _db.collection('invitations');

  /// Live stream of every event the user created or was invited to.
  ///
  /// Firestore has no server-side OR and no `!=`, so the two halves are merged
  /// here: one query on `createdBy` (filtered to non-deleted rows) and one on
  /// participant-subcollection membership. Results are de-duplicated by id and
  /// sorted by time, so the merged list reads "closest first" as one list.
  Stream<List<CountdownEvent>> watchEvents(String userId) {
    final created = _events
        .where('createdBy', isEqualTo: userId)
        // Soft-deleted rows are hidden at the query level; Firestore has no
        // `!=`, so the filter is "never stamped" rather than "not true".
        .where('deletedAt', isNull: true)
        .orderBy('at')
        .limit(100)
        .snapshots();

    final shared = _db
        .collectionGroup('participants')
        .where('userId', isEqualTo: userId)
        .snapshots();

    // Combine the two feeds. `shared` cannot be ordered by event time (a
    // collection-group query would need the sort key duplicated onto each
    // participant row), so it is only used to collect ids and the full events
    // are fetched in a second pass.
    final controller = StreamController<List<CountdownEvent>>();

    List<CountdownEvent> latestOwned = const [];
    Set<String> latestSharedIds = const {};
    Map<String, CountdownEvent> fetchedShared = const {};
    bool disposed = false;

    // Declared before `fetchShared` because that function calls it: a local
    // function must be declared above its first use in Dart.
    void emit() {
      // Owned events win on id collision: they are the authoritative copy and
      // are already ordered by the query.
      final byId = <String, CountdownEvent>{for (final e in latestOwned) e.id: e};
      fetchedShared.forEach((id, event) => byId.putIfAbsent(id, () => event));

      final merged = byId.values.toList()..sort((a, b) => a.at.compareTo(b.at));
      if (!controller.isClosed) controller.add(merged);
    }

    Future<void> fetchShared() async {
      final wanted = latestSharedIds.where((id) => !fetchedShared.containsKey(id)).toList();
      if (wanted.isEmpty) return;

      // `whereIn` accepts 30 values per query; chunk to stay inside that.
      final fetched = <String, CountdownEvent>{};
      for (var i = 0; i < wanted.length; i += 30) {
        final end = i + 30 > wanted.length ? wanted.length : i + 30;
        final chunk = wanted.sublist(i, end);
        try {
          final snap = await _events
              .where(FieldPath.documentId, whereIn: chunk)
              .where('deletedAt', isNull: true)
              .get();
          for (final doc in snap.docs) {
            fetched[doc.id] = _fromDoc(doc);
          }
        } catch (_) {
          // A chunk that fails (offline, permission) is skipped rather than
          // killing the whole stream.
        }
      }
      if (disposed) return;
      fetchedShared = fetched;
      emit();
    }

    final subOwned = created.listen((snap) {
      latestOwned = snap.docs.map(_fromDoc).toList();
      emit();
    }, onError: controller.addError);
    final subShared = shared.listen((snap) {
      final ids = <String>{};
      for (final doc in snap.docs) {
        final parent = doc.reference.parent.parent;
        if (parent != null) ids.add(parent.id);
      }
      latestSharedIds = ids;
      unawaited(fetchShared());
      emit();
    }, onError: controller.addError);

    controller.onCancel = () async {
      disposed = true;
      await subOwned.cancel();
      await subShared.cancel();
    };

    return controller.stream;
  }

  CountdownEvent _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = Map<String, dynamic>.from(doc.data() ?? {});
    // Participants live in a subcollection, so they are not part of the parent
    // document payload. They are filled in by `watchParticipants` where needed;
    // the fields a countdown face needs are all on the parent.
    return CountdownEvent.fromDoc(doc.id, data);
  }

  /// Live stream of one event's participants.
  Stream<List<Participant>> watchParticipants(String eventId) => _events
      .doc(eventId)
      .collection('participants')
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => Participant.fromMap(d.id, d.data())).toList());

  /// Live stream of an event's notes, newest last.
  Stream<List<EventNote>> watchNotes(String eventId) => _events
      .doc(eventId)
      .collection('notes')
      .orderBy('createdAt')
      .snapshots()
      .map((snap) => snap.docs.map((d) => EventNote.fromMap(d.data())).toList());

  Future<CountdownEvent> fetchEvent(String eventId) async {
    final doc = await _events.doc(eventId).get();
    if (!doc.exists) throw const DataFailure('That countdown no longer exists.');
    final participants = await _events.doc(eventId).collection('participants').get();
    return CountdownEvent.fromDoc(doc.id, doc.data() ?? {}).copyWith(
      participants:
          participants.docs.map((d) => Participant.fromMap(d.id, d.data())).toList(),
    );
  }

  /// Creates a countdown. The creator is written as an accepted admin in the
  /// same batch, so the event is never briefly ownerless.
  Future<CountdownEvent> createEvent({
    required String userId,
    required String email,
    required String title,
    required String description,
    required DateTime at,
    String? displayName,
    String? photoUrl,
  }) async {
    if (title.trim().isEmpty) throw const DataFailure('Give this countdown a title.');
    if (!at.isAfter(DateTime.now())) {
      throw const DataFailure('Pick a moment still ahead of you.');
    }

    final id = _uuid.v4();
    final now = DateTime.now();
    final batch = _db.batch();

    batch.set(_events.doc(id), {
      'title': title.trim(),
      'description': description.trim(),
      'at': Timestamp.fromDate(at),
      'createdBy': userId,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });
    batch.set(_events.doc(id).collection('participants').doc(userId), {
      'email': email,
      'role': ParticipantRole.admin.name,
      'inviteStatus': InviteStatus.accepted.name,
      'joinedAt': Timestamp.fromDate(now),
      if (displayName != null) 'displayName': displayName,
      if (photoUrl != null) 'photoUrl': photoUrl,
    });
    await batch.commit();

    return CountdownEvent(
      id: id,
      title: title.trim(),
      description: description.trim(),
      at: at,
      createdBy: userId,
      createdAt: now,
      updatedAt: now,
      participants: [
        Participant(
          userId: userId,
          email: email,
          role: ParticipantRole.admin,
          inviteStatus: InviteStatus.accepted,
          displayName: displayName,
          photoUrl: photoUrl,
          joinedAt: now,
        ),
      ],
    );
  }

  Future<void> updateEvent({
    required CountdownEvent event,
    required String userId,
    required String title,
    required String description,
    required DateTime at,
  }) async {
    if (!event.canEdit(userId)) {
      throw const DataFailure('Only admins and editors can change this countdown.');
    }
    if (title.trim().isEmpty) throw const DataFailure('Give this countdown a title.');
    if (!at.isAfter(DateTime.now())) {
      throw const DataFailure('Pick a moment still ahead of you.');
    }

    await _events.doc(event.id).update({
      'title': title.trim(),
      'description': description.trim(),
      'at': Timestamp.fromDate(at),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Soft-deletes by stamping `deletedAt`, exactly like the web app: the
  /// document survives so an accidental delete can be recovered, but every read
  /// filters it out.
  Future<void> deleteEvent({required CountdownEvent event, required String userId}) async {
    if (!event.canManage(userId)) {
      throw const DataFailure('Only the owner can delete this countdown.');
    }
    await _events.doc(event.id).update({
      'deletedAt': Timestamp.fromDate(DateTime.now()),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Invites someone by email.
  ///
  /// If an account with that email already exists, a participant row is written
  /// straight away and shows up as pending in the invitee's app. Otherwise the
  /// invitation waits in the `invitations` collection until that email signs up.
  Future<void> inviteByEmail({
    required CountdownEvent event,
    required String inviterId,
    required String email,
    required ParticipantRole role,
    String? knownUserId,
    String? displayName,
    String? photoUrl,
  }) async {
    if (!event.canManage(inviterId)) {
      throw const DataFailure('Only the owner can invite people.');
    }
    final target = email.trim().toLowerCase();
    if (target.isEmpty || !target.contains('@')) {
      throw const DataFailure('Enter a valid email address.');
    }

    if (knownUserId != null) {
      await _events.doc(event.id).collection('participants').doc(knownUserId).set({
        'email': target,
        'role': role.name,
        'inviteStatus': InviteStatus.pending.name,
        'joinedAt': Timestamp.fromDate(DateTime.now()),
        if (displayName != null) 'displayName': displayName,
        if (photoUrl != null) 'photoUrl': photoUrl,
      }, SetOptions(merge: true));
      return;
    }

    final id = _uuid.v4();
    await _invitations.doc(id).set({
      'eventId': event.id,
      'invitedBy': inviterId,
      'inviteeEmail': target,
      'role': role.name,
      'status': InviteStatus.pending.name,
      'createdAt': Timestamp.fromDate(DateTime.now()),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
      'eventTitle': event.title,
    });
  }

  Future<void> updateParticipantRole({
    required String eventId,
    required String actorId,
    required Participant participant,
    required ParticipantRole role,
  }) async {
    await _events.doc(eventId).collection('participants').doc(participant.userId).update({
      'role': role.name,
    });
  }

  /// Live stream of pending invitations addressed to this email.
  Stream<List<Invitation>> watchInvitations(String email) {
    final normalised = email.trim().toLowerCase();
    if (normalised.isEmpty) return Stream.value(const []);
    return _invitations
        .where('inviteeEmail', isEqualTo: normalised)
        .where('status', isEqualTo: InviteStatus.pending.name)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Invitation.fromDoc(d.id, d.data()))
            .where((invite) => !invite.isExpired)
            .toList());
  }

  /// Accepts an invitation addressed to the signed-in user.
  ///
  /// The invitation was matched by the caller's own verified email, so a user
  /// can only ever accept an invite sent to them.
  Future<void> acceptInvitation({
    required Invitation invitation,
    required String userId,
    required String email,
    String? displayName,
    String? photoUrl,
  }) async {
    if (invitation.isExpired) throw const DataFailure('That invitation has expired.');
    if (invitation.status != InviteStatus.pending) {
      throw const DataFailure('That invitation is no longer pending.');
    }

    final batch = _db.batch();
    batch.set(
      _events.doc(invitation.eventId).collection('participants').doc(userId),
      {
        'email': email.toLowerCase(),
        'role': invitation.role.name,
        'inviteStatus': InviteStatus.accepted.name,
        'joinedAt': Timestamp.fromDate(DateTime.now()),
        if (displayName != null) 'displayName': displayName,
        if (photoUrl != null) 'photoUrl': photoUrl,
      },
      SetOptions(merge: true),
    );
    batch.update(_invitations.doc(invitation.id), {'status': InviteStatus.accepted.name});
    await batch.commit();
  }

  Future<void> rejectInvitation(Invitation invitation) async {
    await _invitations.doc(invitation.id).update({'status': InviteStatus.rejected.name});
  }

  Future<void> addNote({
    required String eventId,
    required String userId,
    required String text,
  }) async {
    if (text.trim().isEmpty) return;
    final id = _uuid.v4();
    final now = DateTime.now();
    await _events.doc(eventId).collection('notes').doc(id).set({
      'id': id,
      'userId': userId,
      'text': text.trim(),
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });
  }

  /// Duplicates a countdown a year on, keeping the title so the copy can be
  /// tweaked — the same behaviour as the web app's "Duplicate" action.
  Future<CountdownEvent> duplicateEvent({
    required CountdownEvent event,
    required String userId,
    required String email,
    String? displayName,
    String? photoUrl,
  }) {
    return createEvent(
      userId: userId,
      email: email,
      title: event.title,
      description: event.description,
      at: DateTime(event.at.year + 1, event.at.month, event.at.day, event.at.hour,
          event.at.minute),
      displayName: displayName,
      photoUrl: photoUrl,
    );
  }

  /// A short, shareable summary of a countdown.
  static String shareText(CountdownEvent event) {
    final remaining = remainingUntil(event.at);
    final phrase = describeRemaining(remaining);
    return '${event.title} — ${formatMomentFull(event.at)}\n'
        '${remaining.isPast ? 'It has arrived.' : '$phrase to go.'}';
  }
}