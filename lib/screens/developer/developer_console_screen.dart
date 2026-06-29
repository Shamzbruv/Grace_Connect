import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/developer_service.dart';
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
    try {
      final session = await _devService.getDeveloperSession();
      if (mounted) {
        setState(() {
          _isAuthorized = session != null;
          _isChecking = false;
        });
      }
      return;
    } catch (_) {
      // Fall through to the access denied screen.
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
        body: Center(
            child: Icon(Icons.lock,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Developer Console',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).appBarTheme.foregroundColor)),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Theme.of(context).colorScheme.secondary,
          labelColor:
              Theme.of(context).appBarTheme.foregroundColor ?? Colors.white,
          unselectedLabelColor:
              (Theme.of(context).appBarTheme.foregroundColor ?? Colors.white)
                  .withValues(alpha: 0.54),
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
                  title: 'Subscribed Churches',
                  value: data['subscribedChurches']?.toString() ?? '0',
                  color: Colors.teal),
              const SizedBox(height: 12),
              _StatCard(
                  title: 'No Active Subscription',
                  value: data['unsubscribedChurches']?.toString() ?? '0',
                  color: Colors.orange),
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
        if (churches.isEmpty) {
          return const Center(child: Text('No churches found.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: churches.length,
          itemBuilder: (context, index) {
            final church = churches[index];
            final subscriptionActive = church['subscription_active'] == true;
            final churchId =
                (church['placeId'] ?? church['id'] ?? '').toString();
            final activeUntil =
                _formatDate(church['subscription_active_until']);

            return Card(
              child: ListTile(
                leading: Icon(
                  subscriptionActive
                      ? Icons.verified_outlined
                      : Icons.lock_clock_outlined,
                  color: subscriptionActive ? Colors.teal : Colors.orange,
                ),
                title: Text(church['name']?.toString() ?? 'Unknown'),
                subtitle: Text(
                  [
                    church['address']?.toString() ?? 'No address',
                    subscriptionActive
                        ? 'Subscription active until $activeUntil'
                        : 'No active subscription',
                  ].join('\n'),
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: churchId.isEmpty
                      ? null
                      : (value) async {
                          if (value == 'free_1') {
                            await _updateSubscription(churchId, months: 1);
                          }
                          if (value == 'free_3') {
                            await _updateSubscription(churchId, months: 3);
                          }
                          if (value == 'disable') {
                            await _disableSubscription(churchId);
                          }
                        },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'free_1', child: Text('Free 1 month')),
                    PopupMenuItem(
                        value: 'free_3', child: Text('Free 3 months')),
                    PopupMenuItem(
                      value: 'disable',
                      child: Text('Turn subscription off'),
                    ),
                  ],
                ),
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

  Future<void> _updateSubscription(String churchId,
      {required int months}) async {
    try {
      await _devService.grantFreeSubscription(
        churchId: churchId,
        months: months,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Free subscription granted for $months month(s).')),
      );
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update subscription: $error')),
      );
    }
  }

  Future<void> _disableSubscription(String churchId) async {
    try {
      await _devService.clearSubscription(churchId: churchId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subscription turned off.')),
      );
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not disable subscription: $error')),
      );
    }
  }

  String _formatDate(dynamic value) {
    if (value == null) return 'not set';
    final date = DateTime.tryParse(value.toString());
    if (date == null) return 'not set';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 14)),
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
