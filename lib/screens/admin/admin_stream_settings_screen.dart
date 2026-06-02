import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../providers/user_role_provider.dart';
import '../../services/church_service.dart';
import '../../models/church_model.dart';
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
  bool _isLive = false;
  bool _isLoading = true;
  Church? _church;
  YoutubePlayerController? _previewController; // Added for preview
  bool _showPreview = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  @override
  void dispose() {
    _urlController.dispose(); // Always dispose controllers
    _previewController?.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentSettings() async {
    final churchId = Provider.of<UserRoleProvider>(context, listen: false)
        .userProfile
        ?.churchId;
    if (churchId != null) {
      final church = await ChurchService().getChurch(churchId);
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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Please enter a URL')));
      }
      return;
    }

    final videoId = YoutubePlayer.convertUrlToId(url);
    if (videoId == null) {
      if (!quiet) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Invalid YouTube URL')));
      }
      setState(() => _showPreview = false);
      return;
    }

    if (!quiet) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URL is valid! Loading preview...')));
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

  Future<void> _saveSettings() async {
    if (_church == null) return;
    if (!_formKey.currentState!.validate()) return;

    // Validate ID one last time
    final videoId = YoutubePlayer.convertUrlToId(_urlController.text.trim());
    if (videoId == null && _urlController.text.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid YouTube URL')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ChurchService().updateStreamSettings(
          _church!.id, _urlController.text.trim(), _isLive);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Stream settings updated successfully!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error saving settings: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                  if (YoutubePlayer.convertUrlToId(value) == null) {
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
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                onChanged: (val) => setState(() => _isLive = val),
                secondary: Icon(Icons.live_tv,
                    color: _isLive ? Colors.red : Colors.grey),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saveSettings,
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
