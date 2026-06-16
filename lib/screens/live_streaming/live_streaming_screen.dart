import 'dart:async';

import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/user_role_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/church_service.dart';
import '../../widgets/ui/app_loader.dart';

class LiveStreamingScreen extends StatefulWidget {
  const LiveStreamingScreen({super.key});

  @override
  State<LiveStreamingScreen> createState() => _LiveStreamingScreenState();
}

class _LiveStreamingScreenState extends State<LiveStreamingScreen>
    with WidgetsBindingObserver {
  YoutubePlayerController? _controller;
  final AttendanceService _attendanceService = AttendanceService();
  bool _isLoading = true;
  String? _error;
  bool _isLive = false;
  bool _hasActiveService = false;
  bool _leftAppDuringService = false;
  bool _isMarkingRemotePresent = false;
  String? _churchId;
  String? _activeServiceName;
  Timer? _engagementTimer;
  int _engagedSeconds = 0;
  static const int _requiredEngagementSeconds = 15 * 60;

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
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _leftAppDuringService = true;
      _stopEngagementTimer();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && !_leftAppDuringService) {
      _startEngagementTimer();
    }
  }

  Future<void> _loadStream() async {
    final churchId = Provider.of<UserRoleProvider>(context, listen: false)
        .userProfile
        ?.churchId;
    if (churchId == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'No church found.';
        });
      }
      return;
    }
    _churchId = churchId;

    final church = await ChurchService().getChurch(churchId);
    final activeService = await _attendanceService.getActiveService(churchId);
    if (mounted) {
      if (church != null && church.isLive && church.liveStreamUrl != null) {
        final videoId = YoutubePlayer.convertUrlToId(church.liveStreamUrl!);
        if (videoId != null) {
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
            _activeServiceName = activeService?['name']?.toString();
            _leftAppDuringService = false;
            _engagedSeconds = 0;
            _isLoading = false;
          });
          _startEngagementTimer();
          return;
        }
      }
      setState(() {
        _isLive = false;
        _hasActiveService = activeService != null;
        _activeServiceName = activeService?['name']?.toString();
        _isLoading = false;
      });
    }
  }

  void _startEngagementTimer() {
    _engagementTimer?.cancel();
    if (!_isLive || _leftAppDuringService) return;
    _engagementTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isLive || _leftAppDuringService) return;
      setState(() => _engagedSeconds++);
    });
  }

  void _stopEngagementTimer() {
    _engagementTimer?.cancel();
    _engagementTimer = null;
  }

  Future<void> _markRemotePresentFromLive() async {
    final churchId = _churchId;
    final user = context.read<UserRoleProvider>().user;
    if (churchId == null || user == null) return;

    setState(() => _isMarkingRemotePresent = true);
    try {
      await _attendanceService.markRemotePresent(
        userId: user.uid,
        churchId: churchId,
        reason: 'Joined the live service online',
        engagementAnswer:
            'Stayed in the Grace Connect live screen for the service.',
        watchedMinutes: (_engagedSeconds / 60).floor(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remote attendance marked present.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not mark remote present: $error')),
      );
    } finally {
      if (mounted) setState(() => _isMarkingRemotePresent = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopEngagementTimer();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Live Service',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _isLoading = true;
                _controller?.dispose();
                _controller = null;
              });
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
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          player,
                          const SizedBox(height: 16),
                          Text(
                            _activeServiceName == null
                                ? 'Live Now'
                                : '${_activeServiceName!} is Live',
                            style: GoogleFonts.poppins(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 18),
                          ),
                          const SizedBox(height: 12),
                          _buildEngagementCard(context),
                        ],
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
                    ],
                  ),
                ),
    );
  }

  Widget _buildEngagementCard(BuildContext context) {
    final theme = Theme.of(context);
    final progress =
        (_engagedSeconds / _requiredEngagementSeconds).clamp(0, 1).toDouble();
    final remainingSeconds =
        (_requiredEngagementSeconds - _engagedSeconds).clamp(0, 999999);
    final canMarkRemote = _isLive &&
        _hasActiveService &&
        !_leftAppDuringService &&
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
                _leftAppDuringService
                    ? 'Engagement reset because the app was left during the live service. Reopen the live screen and stay here to qualify.'
                    : _hasActiveService
                        ? 'Stay on this live screen. Remote present unlocks after sustained in-app participation.'
                        : 'The stream is live, but no attendance service window is active yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text(
                canMarkRemote
                    ? 'Remote check-in is ready.'
                    : '${(_engagedSeconds / 60).floor()} min watched. ${Duration(seconds: remainingSeconds).inMinutes + 1} min remaining.',
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
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
                  label: const Text('Mark Remote Present'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
