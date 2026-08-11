import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/developer_service.dart';
import 'developer_email_test_screen.dart';

const _scheduledQuizMutationRoles = <String>{
  'super_developer',
  'support_developer',
  'content_moderator',
  'security_admin',
};

class DeveloperConsoleScreen extends StatefulWidget {
  const DeveloperConsoleScreen({super.key});

  @override
  State<DeveloperConsoleScreen> createState() => _DeveloperConsoleScreenState();
}

class _DeveloperConsoleScreenState extends State<DeveloperConsoleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DeveloperService _devService = DeveloperService();
  late Future<Map<String, dynamic>> _scheduledContentFuture;
  bool _isChecking = true;
  bool _isAuthorized = false;
  String? _developerRole;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _scheduledContentFuture = _devService.getScheduledContent();
    _verifyAccess();
  }

  Future<void> _verifyAccess() async {
    try {
      final session = await _devService.getDeveloperSession();
      if (mounted) {
        setState(() {
          _isAuthorized = session != null;
          _developerRole = session?['developer_role']?.toString().toLowerCase();
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
        _developerRole = null;
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
            Tab(icon: Icon(Icons.report_outlined), text: 'Reports'),
            Tab(icon: Icon(Icons.event_note_outlined), text: 'Content'),
            Tab(icon: Icon(Icons.dns), text: 'System'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildChurchesTab(),
          _buildReportsTab(),
          _buildScheduledContentTab(),
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

  Widget _buildReportsTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _devService.getReportedUsers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Could not load reports: ${snapshot.error}'));
        }

        final users = snapshot.data ?? const [];
        if (users.isEmpty) {
          return const Center(child: Text('No reported users.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final user = users[index];
            final reports = _mapList(user['reports']);
            final posts = _mapList(user['posts']);
            final displayName =
                user['reported_name']?.toString().trim().isNotEmpty == true
                    ? user['reported_name'].toString()
                    : user['reported_user_id']?.toString() ?? 'Unknown user';

            return Card(
              child: ExpansionTile(
                leading: const Icon(Icons.person_search_outlined),
                title: Text(displayName),
                subtitle: Text(
                  '${user['report_count'] ?? reports.length} report(s) • latest ${_formatDate(user['latest_reported_at'])}',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Reports',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final report in reports)
                    _ReportTile(
                      report: report,
                      onStatusChanged: (status) async {
                        await _devService.updateContentReportStatus(
                          reportId: report['id']?.toString() ?? '',
                          status: status,
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Report marked $status.')),
                        );
                        setState(() {});
                      },
                    ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Posts by this user',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (posts.isEmpty)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('No posts found for this user.'),
                    )
                  else
                    for (final post in posts)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.article_outlined),
                        title: Text(
                          post['content']?.toString().trim().isEmpty == false
                              ? post['content'].toString()
                              : 'Post',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(_formatDate(post['created_at'])),
                      ),
                ],
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

  Widget _buildScheduledContentTab() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _scheduledContentFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Could not load scheduled content: ${snapshot.error}'),
          );
        }
        final data = snapshot.data ?? const {};
        final dailyWords = _mapList(data['daily_words']);
        final quizzes = _mapList(data['quizzes']);
        return RefreshIndicator(
          onRefresh: _refreshScheduledContent,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Upcoming Daily Content',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reload schedule',
                    onPressed: _refreshScheduledContent,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const Text(
                'Release dates and times stay fixed. Quiz answers are never shown here.',
              ),
              const SizedBox(height: 18),
              Text('Daily Word',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              if (dailyWords.isEmpty)
                const Card(
                  child:
                      ListTile(title: Text('No Daily Word is scheduled yet.')),
                )
              else
                for (final word in dailyWords)
                  Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.wb_sunny_outlined),
                      title: Text(word['title']?.toString() ?? 'Daily Word'),
                      subtitle: Text(
                        '${_formatReleaseDate(word['release_at'])} • ${word['status'] ?? 'scheduled'}',
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(word['message']?.toString() ?? ''),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            word['scripture_reference']?.toString() ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 20),
              Text('Daily Bible Quiz',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              if (quizzes.isEmpty)
                const Card(
                  child:
                      ListTile(title: Text('No Bible Quiz is scheduled yet.')),
                )
              else
                for (final quiz in quizzes) _scheduledQuizCard(quiz),
            ],
          ),
        );
      },
    );
  }

  Widget _scheduledQuizCard(Map<String, dynamic> quiz) {
    final questions = _mapList(quiz['questions']);
    final canReplace = _canReplaceScheduledQuiz(quiz);
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.quiz_outlined),
        title: Text('Quiz • ${quiz['church_id'] ?? 'Global'}'),
        subtitle: Text(
          '${_formatReleaseDate(quiz['release_at'])} • ${quiz['status'] ?? 'unknown'} • ${questions.length} questions',
        ),
        trailing: canReplace
            ? IconButton(
                tooltip:
                    'Generate different questions for this same release slot',
                onPressed: () => _regenerateScheduledQuiz(quiz),
                icon: const Icon(Icons.autorenew),
              )
            : null,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (final question in questions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 15,
                child: Text('${question['order'] ?? ''}'),
              ),
              title: Text(question['question']?.toString() ?? ''),
              subtitle: Text(
                (question['options'] as List? ?? const [])
                    .map((option) => option.toString())
                    .join(' • '),
              ),
            ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Answer key hidden',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshScheduledContent() async {
    final next = _devService.getScheduledContent();
    if (mounted) setState(() => _scheduledContentFuture = next);
    await next;
  }

  Future<void> _regenerateScheduledQuiz(Map<String, dynamic> quiz) async {
    final id = quiz['id']?.toString() ?? '';
    if (id.isEmpty) return;
    if (!_canReplaceScheduledQuiz(quiz)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This quiz is no longer eligible for replacement, or your developer role has preview-only access.',
          ),
        ),
      );
      await _refreshScheduledContent();
      return;
    }
    try {
      await _devService.regenerateScheduledQuiz(id);
      await _refreshScheduledContent();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Questions replaced. The original release date and time were kept.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not refresh quiz: $error')),
      );
    }
  }

  bool _canReplaceScheduledQuiz(Map<String, dynamic> quiz) {
    if (!_scheduledQuizMutationRoles.contains(_developerRole)) return false;
    if (quiz['status']?.toString().toLowerCase() != 'scheduled') return false;
    final releaseAt = DateTime.tryParse(quiz['release_at']?.toString() ?? '');
    return releaseAt != null && releaseAt.isAfter(DateTime.now());
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

  String _formatReleaseDate(dynamic value) {
    if (value == null) return 'release time not set';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return 'release time not set';
    // Jamaica stays on UTC-5 year-round.
    final jamaica = parsed.toUtc().subtract(const Duration(hours: 5));
    final hour = jamaica.hour % 12 == 0 ? 12 : jamaica.hour % 12;
    final minute = jamaica.minute.toString().padLeft(2, '0');
    final period = jamaica.hour < 12 ? 'AM' : 'PM';
    return '${jamaica.year}-${jamaica.month.toString().padLeft(2, '0')}-${jamaica.day.toString().padLeft(2, '0')} $hour:$minute $period Jamaica';
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.report,
    required this.onStatusChanged,
  });

  final Map<String, dynamic> report;
  final Future<void> Function(String status) onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final status = report['status']?.toString() ?? 'pending';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.flag_outlined),
      title: Text('${report['reason'] ?? 'Report'} • $status'),
      subtitle: Text(
        [
          report['content_type']?.toString() ?? 'content',
          _formatReportDate(report['created_at']),
          if (report['description']?.toString().trim().isNotEmpty == true)
            report['description'].toString(),
        ].join('\n'),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Set report status',
        onSelected: onStatusChanged,
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'reviewed', child: Text('Reviewed')),
          PopupMenuItem(value: 'dismissed', child: Text('Dismissed')),
          PopupMenuItem(value: 'action_taken', child: Text('Action taken')),
        ],
      ),
    );
  }
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
  return const [];
}

String _formatReportDate(dynamic value) {
  if (value == null) return 'not set';
  final date = DateTime.tryParse(value.toString());
  if (date == null) return 'not set';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
