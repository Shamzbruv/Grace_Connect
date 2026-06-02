import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/user_role_provider.dart';
import '../../services/user_service.dart';
import '../../services/email_service.dart';
import '../../models/user_profile.dart';
import '../../widgets/ui/app_loader.dart';
import '../../services/church_service.dart';

class MemberManagementScreen extends StatefulWidget {
  const MemberManagementScreen({super.key});

  @override
  State<MemberManagementScreen> createState() => _MemberManagementScreenState();
}

class _MemberManagementScreenState extends State<MemberManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedRoleFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final churchId =
        Provider.of<UserRoleProvider>(context).userProfile?.churchId;
    final canManageRoles =
        Provider.of<UserRoleProvider>(context).userProfile?.canManageRoles ==
            true;

    if (churchId == null) {
      return const Scaffold(
          body: Center(child: Text('Error: No Church ID found')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Member Management',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.email),
            tooltip: 'Send Email Blast',
            onPressed: () => _showEmailBlastDialog(context, churchId),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showInviteDialog(context, churchId),
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.person_add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search members...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildFilterChip(null, 'All'),
                      _buildFilterChip('Admin', 'Admins'),
                      _buildFilterChip('Pastor', 'Pastors'),
                      _buildFilterChip('Ministry Leader', 'Leaders'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<UserProfile>>(
              stream: UserService().getMembers(churchId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const AppLoader();
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final members = snapshot.data ?? [];

                // Filter members based on search and role
                final filteredMembers = members.where((member) {
                  final matchesSearch =
                      member.fullName.toLowerCase().contains(_searchQuery) ||
                          member.email.toLowerCase().contains(_searchQuery);

                  final matchesRole = _selectedRoleFilter == null ||
                      member.roles.contains(_selectedRoleFilter);

                  return matchesSearch && matchesRole;
                }).toList();

                if (filteredMembers.isEmpty) {
                  return const Center(
                      child: Text('No members found matching your criteria'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredMembers.length,
                  itemBuilder: (context, index) {
                    final member = filteredMembers[index];
                    final isAdmin = member.roles.contains('Admin');
                    final isPastor = member.roles.contains('Pastor');

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          backgroundImage: member.photoUrl.isNotEmpty
                              ? NetworkImage(member.photoUrl)
                              : null,
                          child: member.photoUrl.isEmpty
                              ? Text(
                                  member.fullName.isNotEmpty
                                      ? member.fullName[0]
                                      : '?',
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                      fontWeight: FontWeight.bold))
                              : null,
                        ),
                        title: Text(member.fullName,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(member.email),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isAdmin)
                              Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Chip(
                                      label: Text('Admin',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onError)),
                                      backgroundColor:
                                          Theme.of(context).colorScheme.error)),
                            if (isPastor)
                              const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Chip(
                                      label: Text('Pastor',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.white)),
                                      backgroundColor: Colors.orange)),
                            if (canManageRoles)
                              IconButton(
                                icon: Icon(Icons.edit_outlined,
                                    color:
                                        Theme.of(context).colorScheme.primary),
                                onPressed: () =>
                                    _showRoleDialog(context, member),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String? role, String label) {
    final isSelected = _selectedRoleFilter == role;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (bool selected) {
          setState(() {
            _selectedRoleFilter = selected ? role : null;
          });
        },
        selectedColor: Theme.of(context).colorScheme.primaryContainer,
        checkmarkColor: Theme.of(context).colorScheme.onPrimaryContainer,
        labelStyle: TextStyle(
          color: isSelected
              ? Theme.of(context).colorScheme.onPrimaryContainer
              : Theme.of(context).colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  void _showRoleDialog(BuildContext context, UserProfile member) {
    final canManageRoles = Provider.of<UserRoleProvider>(context, listen: false)
            .userProfile
            ?.canManageRoles ==
        true;
    if (!canManageRoles) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only pastors can change member roles.'),
        ),
      );
      return;
    }

    final userService = UserService();
    List<String> selectedRoles = List.from(member.roles);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Manage Roles for ${member.fullName}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    'Pastor',
                    'Admin',
                    'Ministry Leader',
                    'Ministry Worker',
                    'Prayer Warrior',
                    'Musician'
                  ].map((role) {
                    return CheckboxListTile(
                      title: Text(role),
                      value: selectedRoles.contains(role),
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            selectedRoles.add(role);
                          } else {
                            selectedRoles.remove(role);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await userService.updateMemberRole(
                        member.uid, selectedRoles);
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEmailBlastDialog(BuildContext context, String churchId) {
    final subjectController = TextEditingController();
    final bodyController = TextEditingController();
    bool isSending = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Send Email Update'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                        'This will send an email to all members of your church.'),
                    const SizedBox(height: 16),
                    TextField(
                      controller: subjectController,
                      decoration: const InputDecoration(
                          labelText: 'Subject', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bodyController,
                      maxLines: 5,
                      decoration: const InputDecoration(
                          labelText: 'Message Body',
                          border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSending
                      ? null
                      : () async {
                          if (subjectController.text.isEmpty ||
                              bodyController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Please fill all fields')));
                            return;
                          }
                          setState(() => isSending = true);
                          try {
                            final members =
                                await UserService().getMembers(churchId).first;
                            final emails = members
                                .map((m) => m.email)
                                .where((e) => e.isNotEmpty)
                                .toList();

                            if (emails.isNotEmpty) {
                              await EmailService().sendUpdateEmail(
                                toEmails: emails,
                                subject: subjectController.text,
                                htmlBody: bodyController.text
                                    .replaceAll('\n', '<br>'),
                              );
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Email blast sent successfully!')));
                              }
                            } else {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'No members with valid emails found.')));
                              }
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')));
                            }
                          } finally {
                            setState(() => isSending = false);
                          }
                        },
                  child: isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Send'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showInviteDialog(BuildContext context, String churchId) {
    final emailController = TextEditingController();
    bool isInviting = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Invite New Member'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Send an email invitation.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isInviting
                      ? null
                      : () async {
                          if (emailController.text.isEmpty ||
                              !emailController.text.contains('@')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Please enter a valid email')));
                            return;
                          }
                          setState(() => isInviting = true);
                          try {
                            final profile = Provider.of<UserRoleProvider>(
                                    context,
                                    listen: false)
                                .userProfile;
                            final adminName =
                                profile?.fullName ?? 'A Church Admin';

                            final church =
                                await ChurchService().getChurch(churchId);
                            final churchName = church?.name ?? 'Your Church';

                            await EmailService().sendInviteEmail(
                              toEmail: emailController.text.trim(),
                              churchName: churchName,
                              adminName: adminName,
                            );

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Invitation sent successfully!')));
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')));
                            }
                          } finally {
                            if (context.mounted) {
                              setState(() => isInviting = false);
                            }
                          }
                        },
                  child: isInviting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Send Invite'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
