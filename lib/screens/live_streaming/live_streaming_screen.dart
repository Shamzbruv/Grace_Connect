import 'dart:async';

import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/user_role_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/church_service.dart';
import '../../services/membership_service.dart';
import '../../utils/youtube_url_utils.dart';
import '../../widgets/live_mini_player_overlay.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/app_loader.dart';

class LiveStreamingScreen extends StatefulWidget {
  const LiveStreamingScreen({super.key, this.churchId});

  final String? churchId;

  @override
  State<LiveStreamingScreen> createState() => _LiveStreamingScreenState();
}

class _LiveStreamingScreenState extends State<LiveStreamingScreen>
    with WidgetsBindingObserver {
  YoutubePlayerController? _controller;
  final AttendanceService _attendanceService = AttendanceService();
  final ChurchService _churchService = ChurchService();
  bool _isLoading = true;
  String? _error;
  bool _isLive = false;
  bool _hasActiveService = false;
  bool _leftAppDuringService = false;
  bool _isMarkingRemotePresent = false;
  bool _isManualSignInChecking = false;
  bool _autoRemotePromptShown = false;
  bool _remoteAttendanceCompleted = false;
  bool _isVisitorStream = false;
  String? _churchId;
  String? _churchName;
  String? _currentUserId;
  String? _activeServiceId;
  String? _activeServiceName;
  String? _activeVideoId;
  Timer? _engagementTimer;
  Timer? _viewerHeartbeatTimer;
  Timer? _viewerCountTimer;
  Timer? _progressSaveTimer;
  int _activeViewerCount = 0;
  int _engagedSeconds = 0;
  static const int _requiredEngagementSeconds = 60 * 60;
  static const String _progressPrefix = 'live_attendance_progress_v2';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStream();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isLive) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_saveEngagementProgress());
      _stopEngagementTimer();
      _stopViewerPresence(markInactive: true);
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      if (!_remoteAttendanceCompleted) {
        _startEngagementTimer();
      }
      final churchId = _churchId;
      if (_isLive && churchId != null) {
        _startViewerPresence(churchId);
      }
    }
  }

  Future<void> _loadStream() async {
    final roleProvider = Provider.of<UserRoleProvider>(context, listen: false);
    final profileChurchId = roleProvider.userProfile?.churchId.trim() ?? '';
    var churchId = widget.churchId?.trim();
    if (churchId == null || churchId.isEmpty) {
      churchId = profileChurchId;
    }
    if (churchId.isEmpty) {
      final liveChurches = await _churchService.fetchLiveChurches();
      if (liveChurches.isNotEmpty) {
        final firstChurch = liveChurches.first;
        churchId = firstChurch.placeId.trim().isNotEmpty
            ? firstChurch.placeId
            : firstChurch.id;
      }
    }
    final currentUser = roleProvider.user;
    if (churchId.isEmpty) {
      _stopViewerPresence(markInactive: true);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'No public live churches are active right now.';
        });
      }
      return;
    }
    final isOwnChurch =
        profileChurchId.isNotEmpty && churchId == profileChurchId;
    _churchId = churchId;
    _isVisitorStream = !isOwnChurch;
    _currentUserId = currentUser?.uid;

    final church = await ChurchService().getChurch(churchId);
    final visibleToViewer =
        isOwnChurch || (church?.liveIsPublic == true && church?.isLive == true);
    final activeService = isOwnChurch
        ? await _attendanceService.getActiveService(churchId)
        : null;
    final activeServiceId = activeService?['id']?.toString();
    final alreadyPresent = isOwnChurch &&
        activeService != null &&
        currentUser != null &&
        await _attendanceService.hasAttendanceForActiveService(
          churchId,
          userId: currentUser.uid,
        );
    if (mounted) {
      if (church != null &&
          visibleToViewer &&
          church.isLive &&
          church.liveStreamUrl != null) {
        final videoId = YoutubeUrlUtils.extractVideoId(church.liveStreamUrl!);
        if (videoId != null) {
          LiveMiniPlayerService().close();
          final savedSeconds = alreadyPresent
              ? _requiredEngagementSeconds
              : isOwnChurch
                  ? await _loadEngagementProgress(
                      churchId: churchId,
                      serviceId: activeServiceId,
                      videoId: videoId,
                      userId: currentUser?.uid,
                    )
                  : 0;
          _controller = YoutubePlayerController(
            initialVideoId: videoId,
            flags: const YoutubePlayerFlags(
              autoPlay: true,
              isLive: true,
            ),
          );
          setState(() {
            _isLive = true;
            _hasActiveService = activeService != null;
            _churchName =
                church.name.trim().isEmpty ? null : church.name.trim();
            _activeServiceId = activeServiceId;
            _activeServiceName = activeService?['name']?.toString();
            _activeVideoId = videoId;
            _leftAppDuringService = false;
            _autoRemotePromptShown = alreadyPresent;
            _remoteAttendanceCompleted = alreadyPresent;
            _engagedSeconds = savedSeconds;
            _isLoading = false;
          });
          if (isOwnChurch && !alreadyPresent) _startEngagementTimer();
          _startViewerPresence(churchId);
          return;
        }
      }
      _stopViewerPresence(markInactive: true);
      setState(() {
        _isLive = false;
        _hasActiveService = activeService != null;
        _churchName =
            church?.name.trim().isEmpty == false ? church!.name.trim() : null;
        _activeServiceId = activeServiceId;
        _activeServiceName = activeService?['name']?.toString();
        _activeVideoId = null;
        _isLoading = false;
      });
    }
  }

  void _startEngagementTimer() {
    _engagementTimer?.cancel();
    if (!_isLive || _leftAppDuringService || _remoteAttendanceCompleted) {
      return;
    }
    _startProgressSaveTimer();
    _engagementTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted ||
          !_isLive ||
          _leftAppDuringService ||
          _remoteAttendanceCompleted) {
        return;
      }
      setState(() => _engagedSeconds++);
      if (_hasActiveService &&
          !_autoRemotePromptShown &&
          _engagedSeconds >= _requiredEngagementSeconds) {
        _autoRemotePromptShown = true;
        unawaited(_saveEngagementProgress());
        unawaited(_showLiveAttendancePrompt());
      }
    });
  }

  void _stopEngagementTimer() {
    _engagementTimer?.cancel();
    _engagementTimer = null;
    _progressSaveTimer?.cancel();
    _progressSaveTimer = null;
    unawaited(_saveEngagementProgress());
  }

  void _startProgressSaveTimer() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_saveEngagementProgress()),
    );
  }

  String? _progressKey({
    required String? churchId,
    required String? serviceId,
    required String? videoId,
    required String? userId,
  }) {
    final cleanUserId = userId?.trim() ?? '';
    final cleanChurchId = churchId?.trim() ?? '';
    final cleanVideoId = videoId?.trim() ?? '';
    final cleanServiceId = serviceId?.trim();
    if (cleanUserId.isEmpty || cleanChurchId.isEmpty || cleanVideoId.isEmpty) {
      return null;
    }
    return [
      _progressPrefix,
      cleanUserId,
      cleanChurchId,
      cleanServiceId?.isNotEmpty == true ? cleanServiceId : 'live',
      cleanVideoId,
    ].join('|');
  }

  Future<int> _loadEngagementProgress({
    required String? churchId,
    required String? serviceId,
    required String? videoId,
    required String? userId,
  }) async {
    final key = _progressKey(
      churchId: churchId,
      serviceId: serviceId,
      videoId: videoId,
      userId: userId,
    );
    if (key == null) return 0;
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(key) ?? 0)
        .clamp(0, _requiredEngagementSeconds)
        .toInt();
  }

  Future<void> _saveEngagementProgress() async {
    if (_engagedSeconds <= 0) return;
    final key = _progressKey(
      churchId: _churchId,
      serviceId: _activeServiceId,
      videoId: _activeVideoId,
      userId: _currentUserId,
    );
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      key,
      _engagedSeconds.clamp(0, _requiredEngagementSeconds).toInt(),
    );
  }

  void _startViewerPresence(String churchId) {
    _viewerHeartbeatTimer?.cancel();
    _viewerCountTimer?.cancel();
    unawaited(_sendViewerHeartbeat(churchId));
    unawaited(_refreshViewerCount(churchId));
    _viewerHeartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_sendViewerHeartbeat(churchId)),
    );
    _viewerCountTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_refreshViewerCount(churchId)),
    );
  }

  Future<void> _sendViewerHeartbeat(String churchId) async {
    try {
      await _churchService.recordLiveViewerHeartbeat(churchId);
    } catch (error) {
      debugPrint('Could not record live viewer heartbeat: $error');
    }
  }

  Future<void> _refreshViewerCount(String churchId) async {
    final count = await _churchService.fetchLiveViewerCount(churchId);
    if (mounted) {
      setState(() => _activeViewerCount = count);
    }
  }

  void _stopViewerPresence({bool markInactive = false}) {
    _viewerHeartbeatTimer?.cancel();
    _viewerHeartbeatTimer = null;
    _viewerCountTimer?.cancel();
    _viewerCountTimer = null;
    final churchId = _churchId;
    if (markInactive && churchId != null) {
      unawaited(_churchService.clearLiveViewerHeartbeat(churchId));
    }
  }

  Future<void> _markRemotePresentFromLive() async {
    if (_isVisitorStream) return;
    await _showLiveAttendancePrompt();
  }

  Future<void> _handleManualOnSiteSignIn() async {
    final churchId = _churchId;
    if (churchId == null || _isVisitorStream) return;

    setState(() => _isManualSignInChecking = true);
    try {
      final prompt =
          await _attendanceService.getManualOnSiteCheckInPrompt(churchId);
      if (!mounted) return;

      if (prompt.alreadyMarked) {
        AppFeedback.show(
          context,
          prompt.message,
          type: AppFeedbackType.info,
        );
        return;
      }

      if (!prompt.canMarkPresent) {
        AppFeedback.show(
          context,
          prompt.message,
          type: AppFeedbackType.warning,
        );
        return;
      }

      final confirmed = await AppFeedback.confirm(
        context,
        title: 'Location Confirmed',
        message:
            '${prompt.message} You can now mark yourself present for this service.',
        confirmLabel: 'Mark Present',
        icon: Icons.location_on_outlined,
      );
      if (!confirmed) return;

      await _attendanceService.markManualOnSitePresent(churchId);
      if (!mounted) return;
      _stopEngagementTimer();
      setState(() {
        _remoteAttendanceCompleted = true;
        _engagedSeconds = _requiredEngagementSeconds;
      });
      unawaited(_saveEngagementProgress());
      AppFeedback.show(
        context,
        'Attendance marked present. Thank you for joining service.',
        type: AppFeedbackType.success,
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        'Could not complete manual sign-in: $error',
        type: AppFeedbackType.error,
      );
    } finally {
      if (mounted) setState(() => _isManualSignInChecking = false);
    }
  }

  Future<void> _showLiveAttendancePrompt() async {
    final churchId = _churchId;
    final user = context.read<UserRoleProvider>().user;
    if (churchId == null || user == null || !mounted || _isVisitorStream) {
      return;
    }
    if (_isMarkingRemotePresent) return;

    final reasonOptions = [
      'Watching church live online',
      'Sick / Medical',
      'Traveling',
      'Work conflict',
      'Caring for family',
      'Distance / Transportation',
      'Other',
    ];
    final reasonController = TextEditingController();
    final engagementController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var selectedReason = reasonOptions.first;
    var isSubmitting = false;
    String? submissionError;

    setState(() => _isMarkingRemotePresent = true);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> submit() async {
                if (!formKey.currentState!.validate()) return;
                setDialogState(() {
                  isSubmitting = true;
                  submissionError = null;
                });

                try {
                  await _attendanceService.markRemotePresent(
                    userId: user.uid,
                    churchId: churchId,
                    reason: selectedReason == 'Other'
                        ? reasonController.text.trim()
                        : selectedReason,
                    engagementAnswer: engagementController.text.trim(),
                    watchedMinutes: (_engagedSeconds / 60).floor(),
                  );
                  _stopEngagementTimer();
                  if (mounted) {
                    setState(() {
                      _remoteAttendanceCompleted = true;
                      _engagedSeconds = _engagedSeconds
                          .clamp(
                            _requiredEngagementSeconds,
                            1 << 31,
                          )
                          .toInt();
                    });
                    unawaited(_saveEngagementProgress());
                  }
                  if (!mounted || !dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  AppFeedback.show(
                    this.context,
                    'You are marked present. Thank you for joining service thus far; we encourage you to stay throughout the entire service.',
                    type: AppFeedbackType.success,
                  );
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  setDialogState(() {
                    submissionError = error.toString();
                    isSubmitting = false;
                  });
                }
              }

              return Dialog(
                insetPadding: const EdgeInsets.symmetric(horizontal: 20),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.emoji_events_outlined,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'You qualify for remote attendance',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Thank you for joining service through Grace Connect for over an hour. Complete this note so leaders can see why you joined remotely and review the attendance record clearly.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 18),
                        DropdownButtonFormField<String>(
                          // ignore: deprecated_member_use
                          value: selectedReason,
                          decoration: const InputDecoration(
                            labelText: 'Why are you watching remotely?',
                            prefixIcon: Icon(Icons.live_tv_outlined),
                          ),
                          items: reasonOptions
                              .map(
                                (reason) => DropdownMenuItem(
                                  value: reason,
                                  child: Text(reason),
                                ),
                              )
                              .toList(),
                          onChanged: isSubmitting
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setDialogState(() {
                                    selectedReason = value;
                                    if (value != 'Other') {
                                      reasonController.clear();
                                    }
                                  });
                                },
                        ),
                        if (selectedReason == 'Other') ...[
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: reasonController,
                            enabled: !isSubmitting,
                            decoration: const InputDecoration(
                              labelText: 'Remote reason',
                              hintText: 'Briefly explain why you are remote',
                            ),
                            validator: (value) =>
                                value == null || value.trim().length < 4
                                    ? 'Please add a short reason.'
                                    : null,
                          ),
                        ],
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: engagementController,
                          enabled: !isSubmitting,
                          minLines: 3,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Service engagement note',
                            hintText:
                                'What scripture, sermon topic, worship moment, or takeaway stood out?',
                            prefixIcon: Icon(Icons.notes_outlined),
                          ),
                          validator: (value) =>
                              value == null || value.trim().length < 10
                                  ? 'Please add a clearer note for leaders.'
                                  : null,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Watched in app: ${(_engagedSeconds / 60).floor()} minutes',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (submissionError != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Remote attendance failed: $submissionError',
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: isSubmitting
                                    ? null
                                    : () => Navigator.pop(dialogContext),
                                child: const Text('Later'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: isSubmitting ? null : submit,
                                icon: isSubmitting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.how_to_reg_outlined),
                                label: const Text('Submit'),
                              ),
                            ),
                          ],
                        ),
                        if (submissionError != null) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: isSubmitting
                                  ? null
                                  : () {
                                      Navigator.pop(dialogContext);
                                      unawaited(_handleManualOnSiteSignIn());
                                    },
                              icon: const Icon(Icons.location_on_outlined),
                              label: const Text('Try manual on-site sign-in'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      reasonController.dispose();
      engagementController.dispose();
      if (mounted) setState(() => _isMarkingRemotePresent = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_saveEngagementProgress());
    _stopEngagementTimer();
    _stopViewerPresence(markInactive: true);
    if (!_isVisitorStream &&
        _remoteAttendanceCompleted &&
        _isLive &&
        _activeVideoId?.trim().isNotEmpty == true) {
      LiveMiniPlayerService().show(
        videoId: _activeVideoId!,
        title: _activeServiceName == null
            ? '${_churchName ?? 'Live Service'} is Live'
            : '${_activeServiceName!} is Live',
        churchId: _churchId ?? '',
      );
    }
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<UserRoleProvider>().userProfile;
    final canManageLive = profile?.isDeveloper == true ||
        profile?.capabilities.canManageMediaUploads == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(_churchName ?? 'Live Service',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        actions: [
          if (canManageLive)
            IconButton(
              icon: const Icon(Icons.settings_input_antenna_outlined),
              tooltip: 'Manage live stream',
              onPressed: () => Navigator.of(context).pushNamed(
                '/admin/live_stream',
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _isLoading = true;
                _controller?.dispose();
                _controller = null;
              });
              _stopViewerPresence(markInactive: true);
              _loadStream();
            },
          ),
        ],
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading
          ? const AppLoader()
          : _isLive && _controller != null
              ? Center(
                  child: YoutubePlayerBuilder(
                    player: YoutubePlayer(
                      controller: _controller!,
                      showVideoProgressIndicator: true,
                      liveUIColor: Colors.red,
                    ),
                    builder: (context, player) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            player,
                            const SizedBox(height: 16),
                            Text(
                              _activeServiceName == null
                                  ? '${_churchName ?? 'Church'} is Live'
                                  : '${_activeServiceName!} is Live',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildViewerCountBadge(context),
                            const SizedBox(height: 12),
                            _buildEngagementCard(context),
                            if (_isVisitorStream) ...[
                              const SizedBox(height: 12),
                              _buildVisitRequestCard(context),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.tv_off,
                          size: 64,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text(
                        _error ?? 'No live stream currently active.',
                        style: GoogleFonts.poppins(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Check back during service times.',
                        style: GoogleFonts.poppins(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 14),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _loadStream,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          foregroundColor:
                              Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      if (canManageLive) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context)
                              .pushNamed('/admin/live_stream'),
                          icon:
                              const Icon(Icons.settings_input_antenna_outlined),
                          label: const Text('Manage Live Stream'),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildEngagementCard(BuildContext context) {
    final theme = Theme.of(context);
    if (_isVisitorStream) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.public_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'You are watching a public church live. Attendance is only recorded for members of their own church workspace.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final progress =
        (_engagedSeconds / _requiredEngagementSeconds).clamp(0, 1).toDouble();
    final remainingSeconds =
        (_requiredEngagementSeconds - _engagedSeconds).clamp(0, 999999).toInt();
    final canMarkRemote = _isLive &&
        _hasActiveService &&
        !_leftAppDuringService &&
        !_remoteAttendanceCompleted &&
        _engagedSeconds >= _requiredEngagementSeconds;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_user_outlined,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Online Attendance Engagement',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _remoteAttendanceCompleted
                    ? 'Remote attendance is recorded. You can continue using Grace Connect while the live service stays available as a mini-player.'
                    : _hasActiveService
                        ? 'Watch time is saved on this device. If you leave and come back, Grace Connect continues from your saved progress.'
                        : 'The stream is live, but no attendance service window is active yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text(
                _remoteAttendanceCompleted
                    ? 'Remote attendance completed.'
                    : canMarkRemote
                        ? 'Remote attendance note is ready.'
                        : '${(_engagedSeconds / 60).floor()} min watched. ${Duration(seconds: remainingSeconds).inMinutes + 1} min remaining.',
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: canMarkRemote && !_isMarkingRemotePresent
                        ? _markRemotePresentFromLive
                        : null,
                    icon: _isMarkingRemotePresent
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.how_to_reg_outlined),
                    label: Text(_remoteAttendanceCompleted
                        ? 'Attendance Completed'
                        : 'Complete Remote Attendance'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _hasActiveService && !_isManualSignInChecking
                        ? _handleManualOnSiteSignIn
                        : null,
                    icon: _isManualSignInChecking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.location_on_outlined),
                    label: const Text('Manual On-Site Sign-In'),
                  ),
                ],
              ),
              if (_hasActiveService) ...[
                const SizedBox(height: 8),
                Text(
                  'Manual sign-in asks for location access and only works when you are at the church location.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewerCountBadge(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.visibility_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '$_activeViewerCount watching',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisitRequestCard(BuildContext context) {
    final churchId = _churchId?.trim() ?? '';
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.church_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Interested in ${_churchName ?? 'this church'}?',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton(
                onPressed: churchId.isEmpty ? null : _requestVisit,
                child: const Text('Request Visit'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestVisit() async {
    final churchId = _churchId?.trim() ?? '';
    if (churchId.isEmpty) return;
    try {
      await MembershipService().requestMembership(
        churchId: churchId,
        message:
            'Visit request from a public livestream viewer in Grace Connect.',
      );
      if (!mounted) return;
      AppFeedback.show(
        context,
        'Visit request sent to ${_churchName ?? 'the church'}.',
        type: AppFeedbackType.success,
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        'Could not send visit request: $error',
        type: AppFeedbackType.error,
      );
    }
  }
}
