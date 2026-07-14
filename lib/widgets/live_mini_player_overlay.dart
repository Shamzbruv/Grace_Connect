import 'dart:async';

import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../services/church_service.dart';

class LiveMiniPlayerSession {
  const LiveMiniPlayerSession({
    required this.videoId,
    required this.title,
    required this.churchId,
  });

  final String videoId;
  final String title;
  final String churchId;
}

class LiveMiniPlayerService {
  factory LiveMiniPlayerService() => _instance;
  LiveMiniPlayerService._internal();

  static final LiveMiniPlayerService _instance =
      LiveMiniPlayerService._internal();

  final ValueNotifier<LiveMiniPlayerSession?> session =
      ValueNotifier<LiveMiniPlayerSession?>(null);

  void show({
    required String videoId,
    required String title,
    required String churchId,
  }) {
    if (videoId.trim().isEmpty) return;
    session.value = LiveMiniPlayerSession(
      videoId: videoId.trim(),
      title: title.trim().isEmpty ? 'Live Service' : title.trim(),
      churchId: churchId.trim(),
    );
  }

  void close() {
    session.value = null;
  }
}

class LiveMiniPlayerOverlay extends StatelessWidget {
  const LiveMiniPlayerOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        ValueListenableBuilder<LiveMiniPlayerSession?>(
          valueListenable: LiveMiniPlayerService().session,
          builder: (context, session, _) {
            if (session == null) return const SizedBox.shrink();
            return _LiveMiniPlayer(session: session);
          },
        ),
      ],
    );
  }
}

class _LiveMiniPlayer extends StatefulWidget {
  const _LiveMiniPlayer({required this.session});

  final LiveMiniPlayerSession session;

  @override
  State<_LiveMiniPlayer> createState() => _LiveMiniPlayerState();
}

class _LiveMiniPlayerState extends State<_LiveMiniPlayer> {
  late YoutubePlayerController _controller;
  final ChurchService _churchService = ChurchService();
  Timer? _viewerHeartbeatTimer;

  @override
  void initState() {
    super.initState();
    _controller = _createController(widget.session.videoId);
    _startViewerPresence();
  }

  @override
  void didUpdateWidget(covariant _LiveMiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.videoId != widget.session.videoId) {
      _controller.dispose();
      _controller = _createController(widget.session.videoId);
    }
    if (oldWidget.session.churchId != widget.session.churchId) {
      _stopViewerPresence(oldWidget.session.churchId);
      _startViewerPresence();
    }
  }

  @override
  void dispose() {
    _stopViewerPresence(widget.session.churchId);
    _controller.dispose();
    super.dispose();
  }

  void _startViewerPresence() {
    final churchId = widget.session.churchId;
    if (churchId.isEmpty) return;
    _viewerHeartbeatTimer?.cancel();
    unawaited(_churchService.recordLiveViewerHeartbeat(churchId));
    _viewerHeartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_churchService.recordLiveViewerHeartbeat(churchId)),
    );
  }

  void _stopViewerPresence(String churchId) {
    _viewerHeartbeatTimer?.cancel();
    _viewerHeartbeatTimer = null;
    if (churchId.isNotEmpty) {
      unawaited(_churchService.clearLiveViewerHeartbeat(churchId));
    }
  }

  YoutubePlayerController _createController(String videoId) {
    return YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        isLive: true,
        mute: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 480;
            final width = compact ? constraints.maxWidth - 24 : 280.0;
            final right = compact ? 12.0 : 20.0;
            final bottom = compact ? 86.0 : 24.0;

            return Stack(
              children: [
                Positioned(
                  right: right,
                  bottom: bottom,
                  width: width.clamp(220.0, 320.0).toDouble(),
                  child: SafeArea(
                    child: Material(
                      elevation: 10,
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: YoutubePlayer(
                              controller: _controller,
                              showVideoProgressIndicator: true,
                              liveUIColor: Colors.red,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.session.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Open live service',
                                  icon:
                                      const Icon(Icons.open_in_full, size: 18),
                                  onPressed: () {
                                    LiveMiniPlayerService().close();
                                    Navigator.of(context)
                                        .pushNamed('/live_streaming');
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Close mini player',
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: LiveMiniPlayerService().close,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
