import 'package:flutter/material.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../services/church_service.dart';

class DeveloperConsoleScreen extends StatefulWidget {
  const DeveloperConsoleScreen({super.key});

  @override
  State<DeveloperConsoleScreen> createState() => _DeveloperConsoleScreenState();
}

class _DeveloperConsoleScreenState extends State<DeveloperConsoleScreen> {
  final ChurchService _churchService = ChurchService();
  bool _isLoading = false;
  String? _statusMessage;

  Future<void> _seedChurches() async {
    setState(() {
      _isLoading = true;
      _statusMessage = "Seeding churches...";
    });

    try {
      final int count = await _churchService.seedInitialChurches();
      if (mounted) {
        setState(() {
          _statusMessage = "Success! Added $count new churches.";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = "Error: $e";
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Developer Console',
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.build_circle_outlined,
                  size: 64, color: Colors.grey),
              const SizedBox(height: 24),
              const Text(
                'Data Management',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                const CircularProgressIndicator()
              else
                ElevatedButton.icon(
                  onPressed: _seedChurches,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Seed Initial Church List'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                  ),
                ),
              const SizedBox(height: 24),
              if (_statusMessage != null)
                Text(
                  _statusMessage!,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
