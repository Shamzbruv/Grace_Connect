import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/developer_service.dart';
import '../../models/user_profile.dart';
import 'developer_email_test_screen.dart';

class DeveloperConsoleScreen extends StatefulWidget {
  const DeveloperConsoleScreen({super.key});

  @override
  State<DeveloperConsoleScreen> createState() => _DeveloperConsoleScreenState();
}

class _DeveloperConsoleScreenState extends State<DeveloperConsoleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DeveloperService _devService = DeveloperService();
  bool _isChecking = true;
  bool _isAuthorized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _verifyAccess();
  }

  Future<void> _verifyAccess() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final doc = await Supabase.instance.client
          .from('users')
          .select()
          .eq('uid', user.id)
          .maybeSingle();
      if (doc != null) {
        final profile = UserProfile.fromMap(doc);
        if (mounted) {
          setState(() {
            _isAuthorized = profile.isDeveloper;
            _isChecking = false;
          });
        }
        return;
      }
    }
    if (mounted) {
      setState(() {
        _isAuthorized = false;
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAuthorized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body:
            Center(child: Icon(Icons.lock, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Developer Console',
            style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold, color: Theme.of(context).appBarTheme.foregroundColor)),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Theme.of(context).colorScheme.secondary,
          labelColor: Theme.of(context).appBarTheme.foregroundColor ?? Colors.white,
          unselectedLabelColor: (Theme.of(context).appBarTheme.foregroundColor ?? Colors.white).withValues(alpha: 0.54),
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
            Tab(icon: Icon(Icons.church), text: 'Churches'),
            Tab(icon: Icon(Icons.dns), text: 'System'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildChurchesTab(),
          _buildSystemTab(context),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _devService.getPlatformStats(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final data = snapshot.data ?? {};

        return Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatCard(
                  title: 'Total Users',
                  value: data['totalUsers']?.toString() ?? '0',
                  color: Colors.blue),
              const SizedBox(height: 12),
              _StatCard(
                  title: 'Total Churches',
                  value: data['totalChurches']?.toString() ?? '0',
                  color: Colors.indigo),
              const SizedBox(height: 12),
              _StatCard(
                  title: 'Server Status',
                  value: data['serverHealth'] ?? 'Unknown',
                  color: Colors.green),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChurchesTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _devService.getAllChurches(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final churches = snapshot.data!;

        return ListView.builder(
          itemCount: churches.length,
          itemBuilder: (context, index) {
            final church = churches[index];
            return ListTile(
              leading: const Icon(Icons.location_city),
              title: Text(church['name'] ?? 'Unknown'),
              subtitle: Text(church['address'] ?? 'No address'),
              trailing: IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () {
                  // Stub for managing church
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSystemTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: Icon(Icons.key, color: Colors.green),
          title: Text('Google Places API'),
          subtitle: Text('Status: Active'),
          trailing: Icon(Icons.check_circle, color: Colors.green),
        ),
        Divider(),
        ListTile(
          leading: Icon(Icons.notifications_active, color: Colors.green),
          title: Text('Push Notifications'),
          subtitle: Text('Status: Configured'),
          trailing: Icon(Icons.check_circle, color: Colors.green),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.email, color: Colors.blueAccent),
          title: const Text('Email Extension Test'),
          subtitle: const Text('Send trigger emails'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => DeveloperEmailTestScreen()));
          },
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _StatCard(
      {required this.title, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.analytics, color: color, size: 32),
            ),
            const SizedBox(width: 24),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14)),
                Text(value,
                    style: GoogleFonts.poppins(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
