import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/app_bottom_menu.dart';
import '../../models/study_request.dart';
import '../../services/study_service.dart';

class StudyPartnerScreen extends StatefulWidget {
  const StudyPartnerScreen({super.key});

  @override
  State<StudyPartnerScreen> createState() => _StudyPartnerScreenState();
}

class _StudyPartnerScreenState extends State<StudyPartnerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final StudyService _studyService = StudyService();
  final GoTrueClient _auth = Supabase.instance.client.auth;
  String? _currentUserPlaceId;
  String? _currentUserName;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchUserInfo();
  }

  Future<void> _fetchUserInfo() async {
    final user = _auth.currentUser;
    if (user != null) {
      final userData = await Supabase.instance.client
          .from('users')
          .select('placeId, fullName')
          .eq('uid', user.id)
          .maybeSingle();
      if (mounted && userData != null) {
        setState(() {
          _currentUserPlaceId = userData['placeId'];
          _currentUserName = userData['fullName'];
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showCreateRequestDialog() {
    final topicController = TextEditingController();
    final timeController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Find a Study Partner'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: topicController,
              decoration: const InputDecoration(
                  labelText: 'Topic (e.g., Romans 8)',
                  hintText: 'What do you want to study?'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: timeController,
              decoration: const InputDecoration(
                  labelText: 'Preferred Time',
                  hintText: 'e.g., Tuesdays at 7 PM'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (topicController.text.isEmpty || timeController.text.isEmpty) {
                return;
              }

              final user = _auth.currentUser;
              if (user == null || _currentUserPlaceId == null) return;

              final req = StudyRequest(
                id: '',
                requesterId: user.id,
                requesterName: _currentUserName ?? 'Member',
                topic: topicController.text,
                description: '',
                preferredTime: timeController.text,
                placeId: _currentUserPlaceId!,
                createdAt: DateTime.now(),
              );

              await _studyService.createRequest(req);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Request Posted!')));
            },
            child: const Text('Post Request'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please login')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Study Partners',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Find Partner'),
            Tab(text: 'My Sessions'),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomMenu(),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFindPartnerTab(user.id),
          _buildMySessionsTab(user.id),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateRequestDialog,
        icon: const Icon(Icons.add),
        label: const Text('Find Partner'),
        backgroundColor: Colors.indigo,
      ),
    );
  }

  Widget _buildFindPartnerTab(String currentUserId) {
    if (_currentUserPlaceId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<List<StudyRequest>>(
      stream:
          _studyService.getOpenRequests(_currentUserPlaceId!, currentUserId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final requests = snapshot.data ?? [];
        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 60, color: Colors.grey[300]),
                const SizedBox(height: 10),
                const Text('No open requests. Be the first to post!'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final req = requests[index];
            return Card(
              elevation: 3,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(child: Text(req.requesterName[0])),
                title: Text(req.topic,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${req.requesterName} • ${req.preferredTime}'),
                trailing: ElevatedButton(
                  onPressed: () async {
                    await _studyService.acceptRequest(req.id, currentUserId);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('You matched! Check My Sessions.')));
                  },
                  child: const Text('Accept'),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMySessionsTab(String currentUserId) {
    return StreamBuilder<List<StudyRequest>>(
      stream: _studyService.getMySessions(currentUserId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final requests = snapshot.data ?? [];
        if (requests.isEmpty) {
          return const Center(child: Text('No active sessions.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final req = requests[index];
            final isMatched = req.status == 'matched';

            return Card(
              color: isMatched
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : Theme.of(context).colorScheme.surface,
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text(req.topic,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Time: ${req.preferredTime}'),
                    Text('Status: ${req.status.toUpperCase()}',
                        style: TextStyle(
                            color: isMatched ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                trailing: isMatched
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : const Icon(Icons.hourglass_empty, color: Colors.orange),
              ),
            );
          },
        );
      },
    );
  }
}
