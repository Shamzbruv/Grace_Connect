import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/priority_follow_up.dart';
import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/attendance_analysis_service.dart';
import '../../services/direct_message_service.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_loader.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../messages/message_thread_screen.dart';

class AttendanceInsightsScreen extends StatefulWidget {
  const AttendanceInsightsScreen({super.key});

  @override
  State<AttendanceInsightsScreen> createState() =>
      _AttendanceInsightsScreenState();
}

class _AttendanceInsightsScreenState extends State<AttendanceInsightsScreen> {
  final AttendanceAnalysisService _analysisService =
      AttendanceAnalysisService();
  final DirectMessageService _messageService = DirectMessageService();

  Future<void>? _loadFuture;
  String? _loadedChurchId;
  int _thresholdWeeks = AttendanceAnalysisService.defaultAlertThresholdWeeks;
  bool _isSavingThreshold = false;

  bool _hasLeadershipAccess(UserProfile user) {
    final roles = user.roles.map(_normalize).toSet();
    return roles.any({
      'pastor',
      'senior_pastor',
      'assistant_pastor',
      'acting_pastor',
      'admin',
      'administrator',
      'church_admin',
    }.contains);
  }

  bool _canViewAlerts(UserProfile user) {
    return _hasLeadershipAccess(user) ||
        user.appPrivileges.contains('viewPriorityList') ||
        user.appPrivileges.contains('viewAttendanceInsights') ||
        user.appPrivileges.contains('managePriorityList');
  }

  bool _canManageAlerts(UserProfile user) {
    return _hasLeadershipAccess(user) ||
        user.appPrivileges.contains('managePriorityList');
  }

  String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  Future<void> _load(String churchId, bool canManage) async {
    final threshold = await _analysisService.getAlertThresholdWeeks(churchId);
    if (canManage) {
      await _analysisService.refreshPriorityList(
        churchId,
        thresholdWeeks: threshold,
      );
    }
    if (!mounted) return;
    setState(() => _thresholdWeeks = threshold);
  }

  Future<void> _saveThreshold(String churchId, int weeks) async {
    final nextWeeks = weeks.clamp(1, 26).toInt();
    setState(() => _isSavingThreshold = true);
    try {
      await _analysisService.saveAlertThresholdWeeks(churchId, nextWeeks);
      await _analysisService.refreshPriorityList(
        churchId,
        thresholdWeeks: nextWeeks,
      );
      if (!mounted) return;
      setState(() => _thresholdWeeks = nextWeeks);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Attendance alert set to $nextWeeks week${nextWeeks == 1 ? '' : 's'}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save attendance alert: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSavingThreshold = false);
    }
  }

  Future<void> _openMessage(PriorityFollowUp followUp) async {
    final currentUser = context.read<UserRoleProvider>().userProfile;
    if (currentUser == null) return;

    try {
      final conversation =
          await _messageService.getOrCreateConversationWithUserId(
        currentUser: currentUser,
        otherUserId: followUp.userId,
      );
      final otherUser = await _messageService.getConversationPeer(
            conversation,
            currentUser.uid,
          ) ??
          _profileFromFollowUp(followUp);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MessageThreadScreen(
            conversation: conversation,
            otherUser: otherUser,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open message: $error')),
      );
    }
  }

  UserProfile _profileFromFollowUp(PriorityFollowUp followUp) {
    return UserProfile(
      uid: followUp.userId,
      email: '',
      fullName: followUp.userName.isEmpty ? 'Member' : followUp.userName,
      phoneNumber: '',
      placeId: followUp.churchId,
      placeName: '',
      roles: const ['Member'],
      joinDate: DateTime.now(),
      photoUrl: followUp.userPhotoUrl,
      allowMessages: true,
    );
  }

  Future<void> _resolve(PriorityFollowUp followUp) async {
    final currentUser = context.read<UserRoleProvider>().userProfile;
    if (currentUser == null) return;

    try {
      await _analysisService.resolveFlag(
        followUp.id,
        currentUser.uid,
        'resolved',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not resolve alert: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserRoleProvider>().userProfile;
    final churchId = user?.churchId ?? '';
    final canView = user != null && _canViewAlerts(user);
    final canManage = user != null && _canManageAlerts(user);

    if (user == null) {
      return const AppScaffold(
        title: 'Attendance Alerts',
        body: Center(child: AppLoader()),
      );
    }

    if (churchId.isEmpty) {
      return const AppScaffold(
        title: 'Attendance Alerts',
        body: Center(child: Text('Join a church to view attendance alerts.')),
      );
    }

    if (!canView) {
      return const AppScaffold(
        title: 'Attendance Alerts',
        body:
            Center(child: Text('You do not have access to attendance alerts.')),
      );
    }

    if (_loadFuture == null || _loadedChurchId != churchId) {
      _loadedChurchId = churchId;
      _loadFuture = _load(churchId, canManage);
    }

    return AppScaffold(
      title: 'Attendance Alerts',
      showBottomMenu: true,
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: AppLoader());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child:
                    Text('Could not load attendance alerts: ${snapshot.error}'),
              ),
            );
          }

          return StreamBuilder<List<PriorityFollowUp>>(
            stream: _analysisService.getPriorityList(churchId),
            builder: (context, followUpSnapshot) {
              final followUps =
                  followUpSnapshot.data ?? const <PriorityFollowUp>[];
              return RefreshIndicator(
                onRefresh: () async {
                  if (!canManage) return;
                  await _analysisService.refreshPriorityList(
                    churchId,
                    thresholdWeeks: _thresholdWeeks,
                  );
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    _buildThresholdCard(
                      context,
                      churchId,
                      followUps.length,
                      canManage: canManage,
                    ),
                    const SizedBox(height: 16),
                    if (followUps.isEmpty)
                      _buildEmptyState(context)
                    else
                      ...followUps.map(
                        (followUp) => _buildFollowUpCard(
                          context,
                          followUp,
                          canManage: canManage,
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildThresholdCard(
      BuildContext context, String churchId, int activeCount,
      {required bool canManage}) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.volunteer_activism_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Care Alert Rule',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: activeCount == 0
                      ? theme.colorScheme.secondaryContainer
                      : theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$activeCount active',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: activeCount == 0
                        ? theme.colorScheme.onSecondaryContainer
                        : theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Alert after $_thresholdWeeks missed week${_thresholdWeeks == 1 ? '' : 's'}',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          if (canManage) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Decrease weeks',
                  onPressed: _isSavingThreshold || _thresholdWeeks <= 1
                      ? null
                      : () => _saveThreshold(churchId, _thresholdWeeks - 1),
                  icon: const Icon(Icons.remove),
                ),
                Expanded(
                  child: Slider(
                    value: _thresholdWeeks.toDouble(),
                    min: 1,
                    max: 12,
                    divisions: 11,
                    label: '$_thresholdWeeks',
                    onChanged: _isSavingThreshold
                        ? null
                        : (value) => setState(
                              () => _thresholdWeeks = value.round(),
                            ),
                    onChangeEnd: _isSavingThreshold
                        ? null
                        : (value) => _saveThreshold(churchId, value.round()),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Increase weeks',
                  onPressed: _isSavingThreshold || _thresholdWeeks >= 12
                      ? null
                      : () => _saveThreshold(churchId, _thresholdWeeks + 1),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (_isSavingThreshold)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        children: [
          Icon(
            Icons.favorite_border,
            size: 44,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'No care alerts right now',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Members are inside the current attendance window.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowUpCard(
    BuildContext context,
    PriorityFollowUp followUp, {
    required bool canManage,
  }) {
    final theme = Theme.of(context);
    final color = followUp.absenceStreakWeeks >= _thresholdWeeks + 2
        ? theme.colorScheme.error
        : Colors.orange.shade700;
    final lastSeen = followUp.lastAttendedDate == null
        ? 'No attendance recorded'
        : 'Last attended ${_formatShortDate(followUp.lastAttendedDate!)}';

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: followUp.userPhotoUrl.isNotEmpty
                        ? NetworkImage(followUp.userPhotoUrl)
                        : null,
                    child: followUp.userPhotoUrl.isEmpty
                        ? Text(_initial(followUp.userName))
                        : null,
                  ),
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      followUp.userName.isEmpty ? 'Member' : followUp.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      lastSeen,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${followUp.absenceStreakWeeks} wk',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _openMessage(followUp),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Reach Out'),
                ),
              ),
              if (canManage) ...[
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: 'Mark resolved',
                  onPressed: () => _resolve(followUp),
                  icon: const Icon(Icons.check),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatShortDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _initial(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'M' : trimmed.characters.first.toUpperCase();
  }
}
