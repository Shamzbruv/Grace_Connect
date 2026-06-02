import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';

class PrayerAssignmentSheet extends StatefulWidget {
  final String requestId;
  final String churchId;
  final String requesterUid;

  const PrayerAssignmentSheet(
      {super.key,
      required this.requestId,
      required this.churchId,
      required this.requesterUid});

  @override
  State<PrayerAssignmentSheet> createState() => _PrayerAssignmentSheetState();
}

class _PrayerAssignmentSheetState extends State<PrayerAssignmentSheet> {
  bool _isLoading = false;
  String? _selectedWarriorId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      // Half-screen height
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Assign Prayer Request",
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          const Text("Select a Prayer Warrior to assign this request to:"),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('users')
                  .stream(primaryKey: ['uid']).eq('placeId', widget.churchId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final warriors = snapshot.data!
                    .map(UserProfile.fromMap)
                    .where((profile) =>
                        profile.canAssignPrayers || profile.isPrayerWarrior)
                    .toList();

                if (warriors.isEmpty) {
                  return const Center(
                      child: Text("No Prayer Warriors found in this church."));
                }

                return ListView.builder(
                  itemCount: warriors.length,
                  itemBuilder: (context, index) {
                    final warrior = warriors[index];
                    final isSelected = _selectedWarriorId == warrior.uid;
                    return ListTile(
                      leading: CircleAvatar(
                          backgroundImage: NetworkImage(
                              warrior.photoUrl.isNotEmpty
                                  ? warrior.photoUrl
                                  : 'https://via.placeholder.com/150')),
                      title: Text(warrior.fullName),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedWarriorId = warrior.uid;
                        });
                      },
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_selectedWarriorId == null || _isLoading)
                  ? null
                  : _assignTask,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text("Assign Task"),
            ),
          )
        ],
      ),
    );
  }

  Future<void> _assignTask() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final userProvider =
          Provider.of<UserRoleProvider>(context, listen: false);
      final currentUser = userProvider.userProfile;

      if (currentUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Error: ID not found. Please login again.")));
        }
        return;
      }

      // Create Prayer Task
      await Supabase.instance.client.from('prayer_tasks').insert({
        'churchId': widget.churchId,
        'requestId': widget.requestId,
        'assignedToId': _selectedWarriorId,
        'assignedById': currentUser.uid,
        'status': 'assigned',
        'assignedAt': DateTime.now().toIso8601String(),
        'priority': 'normal',
      });

      // Close sheet
      if (mounted) {
        Navigator.pop(context, true); // Return success
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Prayer assigned successfully")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
