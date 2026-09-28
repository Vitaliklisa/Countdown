import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../providers/app_providers.dart';

/// Pending invitations addressed to the signed-in user.
///
/// Renders nothing when there is nothing pending, so it can sit unconditionally
/// at the top of both home states without reserving empty space.
class InvitationsBanner extends ConsumerWidget {
  const InvitationsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final user = ref.watch(currentUserProvider);
    final invitations = ref.watch(invitationsProvider).valueOrNull ?? const <Invitation>[];

    if (user == null || invitations.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final invitation in invitations)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.accent.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.mail_outline_rounded, size: 17, color: colors.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Invitation',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: colors.accent,
                          ),
                        ),
                      ),
                      Text(
                        _roleLabel(invitation.role),
                        style: TextStyle(fontSize: 11.5, color: colors.subtle),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    invitation.eventTitle.isNotEmpty
                        ? 'You have been invited to “${invitation.eventTitle}”.'
                        : 'You have been invited to a countdown.',
                    style: const TextStyle(fontSize: 13.5, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(42),
                          ),
                          onPressed: () => runAction(
                            context,
                            () => ref.read(eventRepositoryProvider).acceptInvitation(
                                  invitation: invitation,
                                  userId: user.id,
                                  email: user.email,
                                  displayName: user.displayName,
                                  photoUrl: user.photoUrl,
                                ),
                            successMessage: 'Joined “${invitation.eventTitle}”.',
                          ),
                          child: const Text('Accept'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(42),
                          ),
                          onPressed: () => runAction(
                            context,
                            () => ref
                                .read(eventRepositoryProvider)
                                .rejectInvitation(invitation),
                            successMessage: 'Invitation declined.',
                          ),
                          child: const Text('Decline'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _roleLabel(ParticipantRole role) => switch (role) {
        ParticipantRole.admin => 'Admin',
        ParticipantRole.editor => 'Editor',
        ParticipantRole.viewer => 'Viewer',
      };
}