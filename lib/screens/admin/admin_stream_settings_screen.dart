import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../providers/user_role_provider.dart';
import '../../services/church_service.dart';
import '../../services/notification_service.dart';
import '../../models/church_model.dart';
import '../../utils/youtube_url_utils.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/app_loader.dart';

class AdminStreamSettingsScreen extends StatefulWidget {
  const AdminStreamSettingsScreen({super.key});

  @override
  State<AdminStreamSettingsScreen> createState() =>
      _AdminStreamSettingsScreenState();
}

class _AdminStreamSettingsScreenState extends State<AdminStreamSettingsScreen> {
  final _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>(); // Added form key
  final ChurchService _churchService = ChurchService();
  bool _isLive = false;
  bool _isLoading = true;
  Church? _church;
  YoutubePlayerController? _previewController; // Added for preview
  bool _showPreview = false;
  Timer? _viewerCountTimer;
  int _activeViewerCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  @override
  void dispose() {
    _viewerCountTimer?.cancel();
    _urlController.dispose(); // Always dispose controllers
    _previewController?.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentSettings() async {
    final churchId = Provider.of<UserRoleProvider>(context, listen: false)
        .userProfile
        ?.churchId;
    if (churchId != null) {
      final church = await _churchService.getChurch(churchId);
      if (mounted && church != null) {
        setState(() {
          _church = church;
          _urlController.text = church.liveStreamUrl ?? '';
          _isLive = church.isLive;
          _isLoading = false;
          // Auto-load preview if URL exists
          if (_urlController.text.isNotEmpty) {
            _testLink(quiet: true);
          }
        });
        if (church.isLive) {
          _startViewerCountPolling();
        } else {
          _stopViewerCountPolling();
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
          // Show error or redirect? For now just stop loading
        });
      }
    }
  }

  void _testLink({bool quiet = false}) {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      if (!quiet) {
        AppFeedback.show(
          context,
          'Please enter a URL.',
          type: AppFeedbackType.warning,
        );
      }
      return;
    }

    final videoId = YoutubeUrlUtils.extractVideoId(url);
    if (videoId == null) {
      if (!quiet) {
        AppFeedback.show(
          context,
          'Invalid YouTube URL.',
          type: AppFeedbackType.warning,
        );
      }
      setState(() => _showPreview = false);
      return;
    }

    if (!quiet) {
      AppFeedback.show(
        context,
        'URL is valid. Loading preview...',
        type: AppFeedbackType.success,
      );
    }

    setState(() {
      _showPreview = true;
      _previewController?.dispose(); // Dispose old one
      _previewController = YoutubePlayerController(
        initialVideoId: videoId,
        flags: const YoutubePlayerFlags(
          autoPlay: false,
          mute: false,
        ),
      );
    });
  }

  Future<bool> _saveSettings() async {
    if (_church == null) return false;
    if (!_formKey.currentState!.validate()) return false;

    // Validate ID one last time
    final streamUrl = _urlController.text.trim();
    final normalizedStreamUrl =
        streamUrl.isEmpty ? '' : YoutubeUrlUtils.normalizeWatchUrl(streamUrl);
    if (normalizedStreamUrl == null && streamUrl.isNotEmpty) {
      AppFeedback.show(
        context,
        'Please enter a valid YouTube URL.',
        type: AppFeedbackType.warning,
      );
      return false;
    }

    final wasLive = _church!.isLive;
    final shouldNotifyLive =
        _isLive && !wasLive && normalizedStreamUrl?.isNotEmpty == true;

    setState(() => _isLoading = true);
    try {
      await _churchService.updateStreamSettings(
        _church!.id,
        normalizedStreamUrl ?? '',
        _isLive,
      );
      if (shouldNotifyLive) {
        await _notifyChurchLiveNow();
      }
      if (mounted) {
        _syncSavedChurchState(normalizedStreamUrl ?? '');
        final message = shouldNotifyLive
            ? 'Stream settings saved and members were notified.'
            : 'Stream settings updated successfully!';
        AppFeedback.show(
          context,
          message,
          type: AppFeedbackType.success,
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        AppFeedback.show(
          context,
          'Error saving settings: $e',
          type: AppFeedbackType.error,
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLiveToggle(bool isLive) async {
    final previousValue = _isLive;
    if (isLive && _urlController.text.trim().isEmpty) {
      AppFeedback.show(
        context,
        'Paste a valid YouTube live link before going live.',
        type: AppFeedbackType.warning,
      );
      return;
    }

    setState(() => _isLive = isLive);
    final saved = await _saveSettings();
    if (!saved && mounted) {
      setState(() => _isLive = previousValue);
    }
  }

  Future<void> _notifyChurchLiveNow() async {
    final churchName =
        _church!.name.trim().isEmpty ? 'Your church' : _church!.name.trim();
    await NotificationService().sendNotification(
      '$churchName is live now',
      'Tap to watch the live service inside Grace Connect.',
      NotificationService.appWideTopic,
      route: '/live_streaming',
      type: 'live_stream',
    );
  }

  void _syncSavedChurchState(String streamUrl) {
    final church = _church;
    if (church == null) return;
    _church = Church(
      id: church.id,
      name: church.name,
      placeId: church.placeId,
      address: church.address,
      denomination: church.denomination,
      ownerUserId: church.ownerUserId,
      timezone: church.timezone,
      status: church.status,
      createdAt: church.createdAt,
      parish: church.parish,
      latitude: church.latitude,
      longitude: church.longitude,
      policies: church.policies,
      liveStreamUrl: streamUrl.isEmpty ? null : streamUrl,
      isLive: _isLive,
    );
    if (_isLive) {
      _startViewerCountPolling();
    } else {
      _stopViewerCountPolling();
    }
  }

  String get _viewerChurchId {
    final profile =
        Provider.of<UserRoleProvider>(context, listen: false).userProfile;
    final profileChurchId = profile?.churchId.trim() ?? '';
    if (profileChurchId.isNotEmpty) return profileChurchId;
    final churchPlaceId = _church?.placeId.trim() ?? '';
    if (churchPlaceId.isNotEmpty) return churchPlaceId;
    return _church?.id.trim() ?? '';
  }

  void _startViewerCountPolling() {
    _viewerCountTimer?.cancel();
    unawaited(_refreshViewerCount());
    _viewerCountTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_refreshViewerCount()),
    );
  }

  void _stopViewerCountPolling() {
    _viewerCountTimer?.cancel();
    _viewerCountTimer = null;
    if (mounted && _activeViewerCount != 0) {
      setState(() => _activeViewerCount = 0);
    }
  }

  Future<void> _refreshViewerCount() async {
    final churchId = _viewerChurchId;
    if (!_isLive || churchId.isEmpty) return;

    final count = await _churchService.fetchLiveViewerCount(churchId);
    if (mounted) {
      setState(() => _activeViewerCount = count);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: AppLoader());

    return Scaffold(
      appBar: AppBar(
        title: Text('Live Stream Settings',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          // Wrap in Form
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manage Live Stream',
                style: GoogleFonts.poppins(
                    fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                  'Enter your YouTube Audio/Video link below. Test the link to ensure it works, then toggle "Go Live" to broadcast.'),
              const SizedBox(height: 24),
              TextFormField(
                // Changed to TextFormField for validator
                controller: _urlController,
                decoration: InputDecoration(
                  // Use standard InputDecoration
                  labelText: 'YouTube URL',
                  hintText: 'https://youtube.com/watch?v=...',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.link),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.green),
                    onPressed: () => _testLink(),
                    tooltip: 'Test Link',
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return null; // Empty is allowed (turn off stream)
                  }
                  if (YoutubeUrlUtils.extractVideoId(value) == null) {
                    return 'Invalid YouTube URL';
                  }
                  return null;
                },
                onChanged: (_) =>
                    setState(() {}), // Rebuild to update UI state if needed
              ),
              const SizedBox(height: 12),
              if (_showPreview && _previewController != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: YoutubePlayer(
                      controller: _previewController!,
                      showVideoProgressIndicator: true,
                    ),
                  ),
                ),
              SwitchListTile(
                title: const Text('Go Live Now'),
                subtitle: Text(_isLive
                    ? 'Members can currently see the stream.'
                    : 'Stream is hidden from members.'),
                value: _isLive,
                onChanged: _isLoading ? null : _handleLiveToggle,
                secondary: Icon(Icons.live_tv,
                    color: _isLive ? Colors.red : Colors.grey),
              ),
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.visibility_outlined,
                    color: _isLive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: const Text('Currently watching'),
                  subtitle: Text(
                    _isLive
                        ? '$_activeViewerCount on app now'
                        : 'Viewer count appears when the stream is live.',
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : () => _saveSettings(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: const Text('Save Settings',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
