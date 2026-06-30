import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../models/church_model.dart';
import '../../models/church_transfer_request.dart';
import '../../providers/user_role_provider.dart';
import '../../services/church_service.dart';
import '../../services/church_transfer_service.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/app_scaffold.dart';

class ChurchTransferScreen extends StatefulWidget {
  const ChurchTransferScreen({super.key});

  @override
  State<ChurchTransferScreen> createState() => _ChurchTransferScreenState();
}

class _ChurchTransferScreenState extends State<ChurchTransferScreen> {
  final ChurchTransferService _transferService = ChurchTransferService();
  final ChurchService _churchService = ChurchService();

  Future<void> _showCreateSheet() async {
    final user = context.read<UserRoleProvider>().userProfile;
    if (user == null) return;

    final searchController = TextEditingController();
    final reasonController = TextEditingController();
    final phoneController = TextEditingController(text: user.phone);
    Church? selectedChurch;
    var results = const <Church>[];
    var isSearching = false;
    var isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> search() async {
              setSheetState(() => isSearching = true);
              results = await _churchService.fetchChurches(
                query: searchController.text,
                limit: 20,
              );
              if (sheetContext.mounted) {
                setSheetState(() => isSearching = false);
              }
            }

            Future<void> submit() async {
              if (selectedChurch == null) {
                AppFeedback.show(
                  context,
                  'Choose the receiving church.',
                  type: AppFeedbackType.warning,
                );
                return;
              }
              if (reasonController.text.trim().length < 10) {
                AppFeedback.show(
                  context,
                  'Add a little more context for the pastors.',
                  type: AppFeedbackType.warning,
                );
                return;
              }
              setSheetState(() => isSaving = true);
              try {
                await _transferService.createRequest(
                  user: user,
                  targetChurch: selectedChurch!,
                  reason: reasonController.text,
                  contactPhone: phoneController.text,
                );
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
                AppFeedback.show(
                  context,
                  'Transfer request submitted.',
                  type: AppFeedbackType.success,
                );
              } catch (error) {
                if (!context.mounted) return;
                AppFeedback.show(
                  context,
                  'Could not submit request: $error',
                  type: AppFeedbackType.error,
                );
              } finally {
                if (sheetContext.mounted) {
                  setSheetState(() => isSaving = false);
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Transfer to Another Church',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your pastor receives this first, then sends it to the receiving pastor and keeps the status updated.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => search(),
                      decoration: InputDecoration(
                        labelText: selectedChurch == null
                            ? 'Search receiving church'
                            : selectedChurch!.name,
                        prefixIcon: const Icon(Icons.church_outlined),
                        suffixIcon: IconButton(
                          tooltip: 'Search',
                          onPressed: isSearching ? null : search,
                          icon: isSearching
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.search),
                        ),
                      ),
                    ),
                    if (results.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      AppCard(
                        child: Column(
                          children: [
                            for (final church in results.take(6))
                              ListTile(
                                leading: const Icon(Icons.church_outlined),
                                title: Text(church.name),
                                subtitle: Text(church.address),
                                onTap: () {
                                  setSheetState(() {
                                    selectedChurch = church;
                                    searchController.text = church.name;
                                    results = const [];
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Best contact number',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: reasonController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Reason / context',
                        hintText:
                            'Moving, family change, school, work, pastoral care need...',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: isSaving ? null : submit,
                        icon: isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_outlined),
                        label: const Text('Submit Request'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    searchController.dispose();
    reasonController.dispose();
    phoneController.dispose();
  }

  Future<void> _showPastorUpdateSheet(
    ChurchTransferRequest request,
    bool isTargetChurch,
  ) async {
    final notesController = TextEditingController(
      text: isTargetChurch ? request.targetPastorNotes : request.pastorNotes,
    );
    var status = request.status;
    var isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> save() async {
              setSheetState(() => isSaving = true);
              try {
                await _transferService.updateRequest(
                  request: request,
                  status: status,
                  notes: notesController.text,
                  targetPastorNote: isTargetChurch,
                );
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
                AppFeedback.show(
                  context,
                  'Transfer status updated.',
                  type: AppFeedbackType.success,
                );
              } catch (error) {
                if (!context.mounted) return;
                AppFeedback.show(
                  context,
                  'Could not update request: $error',
                  type: AppFeedbackType.error,
                );
              } finally {
                if (sheetContext.mounted) {
                  setSheetState(() => isSaving = false);
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.userName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                        '${request.currentChurchName} -> ${request.targetChurchName}'),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        prefixIcon: Icon(Icons.timeline_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'submitted',
                          child: Text('Submitted to pastor'),
                        ),
                        DropdownMenuItem(
                          value: 'pastor_review',
                          child: Text('Pastor reviewing'),
                        ),
                        DropdownMenuItem(
                          value: 'sent_to_target_pastor',
                          child: Text('Sent to receiving pastor'),
                        ),
                        DropdownMenuItem(
                          value: 'approved',
                          child: Text('Approved'),
                        ),
                        DropdownMenuItem(
                          value: 'declined',
                          child: Text('Declined'),
                        ),
                        DropdownMenuItem(
                          value: 'completed',
                          child: Text('Completed'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) setSheetState(() => status = value);
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: notesController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Pastoral notes / context',
                        prefixIcon: Icon(Icons.edit_note_outlined),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: isSaving ? null : save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save Status'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    notesController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserRoleProvider>().userProfile;
    final canManage = _transferService.canManageTransfers(user);

    return AppScaffold(
      title: 'Church Transfer',
      floatingActionButton: user == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _showCreateSheet,
              icon: const Icon(Icons.compare_arrows_outlined),
              label: const Text('Request'),
            ),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: canManage ? 2 : 1,
              child: Column(
                children: [
                  TabBar(
                    tabs: [
                      const Tab(text: 'My Request'),
                      if (canManage) const Tab(text: 'Pastor Queue'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _TransferList(
                          stream: _transferService.watchMyRequests(user.uid),
                          emptyText:
                              'No transfer requests yet. Tap Request to begin.',
                          onTap: null,
                          currentChurchId: user.churchId,
                        ),
                        if (canManage)
                          _TransferList(
                            stream: _transferService
                                .watchPastorQueue(user.churchId),
                            emptyText: 'No transfer requests for your church.',
                            currentChurchId: user.churchId,
                            onTap: (request) => _showPastorUpdateSheet(
                              request,
                              request.targetChurchId == user.churchId,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _TransferList extends StatelessWidget {
  const _TransferList({
    required this.stream,
    required this.emptyText,
    required this.currentChurchId,
    this.onTap,
  });

  final Stream<List<ChurchTransferRequest>> stream;
  final String emptyText;
  final String currentChurchId;
  final ValueChanged<ChurchTransferRequest>? onTap;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChurchTransferRequest>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
              child: Text('Could not load requests: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final requests = snapshot.data ?? const <ChurchTransferRequest>[];
        if (requests.isEmpty) {
          return Center(child: Text(emptyText));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: requests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final request = requests[index];
            final incoming = request.targetChurchId == currentChurchId;
            return AppCard(
              onTap: onTap == null ? null : () => onTap!(request),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        incoming
                            ? Icons.call_received_outlined
                            : Icons.call_made_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          request.userName,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                      Chip(label: Text(request.statusLabel)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                      '${request.currentChurchName} -> ${request.targetChurchName}'),
                  const SizedBox(height: 6),
                  Text(
                    request.reason,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (request.pastorNotes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Pastor: ${request.pastorNotes}'),
                  ],
                  if (request.targetPastorNotes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Receiving pastor: ${request.targetPastorNotes}'),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    timeago.format(request.updatedAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
