import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/user_role_provider.dart';
import '../../services/church_service.dart';
import '../../widgets/ui/app_loader.dart';

class LiveStreamingScreen extends StatefulWidget {
  const LiveStreamingScreen({super.key});

  @override
  State<LiveStreamingScreen> createState() => _LiveStreamingScreenState();
}

class _LiveStreamingScreenState extends State<LiveStreamingScreen> {
  YoutubePlayerController? _controller;
  bool _isLoading = true;
  String? _error;
  bool _isLive = false;

  @override
  void initState() {
    super.initState();
    _loadStream();
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

    final church = await ChurchService().getChurch(churchId);
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
            _isLoading = false;
          });
          return;
        }
      }
      setState(() {
        _isLive = false;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
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
                            'Live Now',
                            style: GoogleFonts.poppins(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 18),
                          ),
                        ],
                      );
                    },
                  ),
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.tv_off, size: 64, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text(
                        _error ?? 'No live stream currently active.',
                        style: GoogleFonts.poppins(
                            color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Check back during service times.',
                        style: GoogleFonts.poppins(
                            color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _loadStream,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          foregroundColor: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
