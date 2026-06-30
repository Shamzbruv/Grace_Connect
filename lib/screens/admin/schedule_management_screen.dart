import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../models/service_schedule.dart';
import '../../providers/user_role_provider.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_loader.dart';
import '../../widgets/ui/app_scaffold.dart';

class ScheduleManagementScreen extends StatefulWidget {
  const ScheduleManagementScreen({super.key});

  @override
  State<ScheduleManagementScreen> createState() =>
      _ScheduleManagementScreenState();
}

class _ScheduleManagementScreenState extends State<ScheduleManagementScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _currentUserPlaceId;
  bool _isLoading = true;

  static const List<DropdownMenuItem<int>> _dayItems = [
    DropdownMenuItem(value: 1, child: Text('Monday')),
    DropdownMenuItem(value: 2, child: Text('Tuesday')),
    DropdownMenuItem(value: 3, child: Text('Wednesday')),
    DropdownMenuItem(value: 4, child: Text('Thursday')),
    DropdownMenuItem(value: 5, child: Text('Friday')),
    DropdownMenuItem(value: 6, child: Text('Saturday')),
    DropdownMenuItem(value: 7, child: Text('Sunday')),
  ];

  @override
  void initState() {
    super.initState();
    _fetchCurrentUserPlace();
  }

  Future<void> _fetchCurrentUserPlace() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final userData = await _supabase
        .from('users')
        .select('placeId')
        .eq('uid', user.id)
        .maybeSingle();

    if (!mounted) return;
    setState(() {
      _currentUserPlaceId = userData?['placeId'];
      _isLoading = false;
    });
  }

  Future<void> _showScheduleSheet({ServiceSchedule? schedule}) async {
    final churchId = _currentUserPlaceId;
    if (churchId == null || churchId.isEmpty) return;

    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return _ScheduleEditorSheet(
          churchId: churchId,
          schedule: schedule,
          onSave: (nextSchedule) async {
            if (schedule == null) {
              await _supabase
                  .from('service_schedules')
                  .insert(nextSchedule.toMap());
            } else {
              await _supabase
                  .from('service_schedules')
                  .update(nextSchedule.toMap())
                  .eq('serviceId', schedule.serviceId);
            }
          },
        );
      },
    );

    if (!mounted || message == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _deleteSchedule(ServiceSchedule schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Schedule?'),
          content: Text(
            '${schedule.name} will no longer be used for auto-attendance.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _supabase
          .from('service_schedules')
          .delete()
          .eq('serviceId', schedule.serviceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Service schedule deleted.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete schedule: $e')),
      );
    }
  }

  Stream<List<Map<String, dynamic>>> _scheduleStream(String churchId) {
    return _supabase
        .from('service_schedules')
        .stream(primaryKey: ['serviceId']).eq('churchId', churchId);
  }

  @override
  Widget build(BuildContext context) {
    final roleProvider = context.watch<UserRoleProvider>();

    if (roleProvider.userProfile?.capabilities.canManageSchedules != true) {
      return const AppScaffold(
        title: 'Service Schedules',
        body:
            Center(child: Text('You do not have access to manage schedules.')),
      );
    }

    return AppScaffold(
      title: 'Service Schedules',
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showScheduleSheet(),
        child: const Icon(Icons.add),
      ),
      body: _isLoading || _currentUserPlaceId == null
          ? const Center(child: AppLoader())
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: _scheduleStream(_currentUserPlaceId!),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child:
                          Text('Could not load schedules: ${snapshot.error}'),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: AppLoader());
                }

                final schedules =
                    snapshot.data!.map(ServiceSchedule.fromMap).toList()
                      ..sort((a, b) {
                        final dayCompare = a.dayOfWeek.compareTo(b.dayOfWeek);
                        if (dayCompare != 0) return dayCompare;
                        return a.startTime.compareTo(b.startTime);
                      });

                if (schedules.isEmpty) {
                  return _EmptySchedules(onAdd: () => _showScheduleSheet());
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    AppCard(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      child: Text(
                        'These service windows are used by auto-attendance. Members are only checked in when they are inside the church geofence during one of these times.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...schedules.map(
                      (schedule) => _ScheduleCard(
                        schedule: schedule,
                        onEdit: () => _showScheduleSheet(schedule: schedule),
                        onDelete: () => _deleteSchedule(schedule),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  static TimeOfDay? _parseTimeOfDay(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  static String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
}

String _dayToString(int day) {
  switch (day) {
    case 1:
      return 'Monday';
    case 2:
      return 'Tuesday';
    case 3:
      return 'Wednesday';
    case 4:
      return 'Thursday';
    case 5:
      return 'Friday';
    case 6:
      return 'Saturday';
    case 7:
      return 'Sunday';
    default:
      return 'Unknown';
  }
}

class _ScheduleEditorSheet extends StatefulWidget {
  const _ScheduleEditorSheet({
    required this.churchId,
    required this.schedule,
    required this.onSave,
  });

  final String churchId;
  final ServiceSchedule? schedule;
  final Future<void> Function(ServiceSchedule schedule) onSave;

  @override
  State<_ScheduleEditorSheet> createState() => _ScheduleEditorSheetState();
}

class _ScheduleEditorSheetState extends State<_ScheduleEditorSheet> {
  late final TextEditingController _nameController;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late int _selectedDay;
  late bool _attendanceEnabled;
  late int _opensBefore;
  late int _closesAfter;
  late int _dwellMinutes;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final schedule = widget.schedule;
    _nameController = TextEditingController(text: schedule?.name ?? '');
    _startTime = _ScheduleManagementScreenState._parseTimeOfDay(
          schedule?.startTime,
        ) ??
        const TimeOfDay(hour: 9, minute: 0);
    _endTime = _ScheduleManagementScreenState._parseTimeOfDay(
          schedule?.endTime,
        ) ??
        const TimeOfDay(hour: 11, minute: 0);
    _selectedDay = schedule?.dayOfWeek ?? 7;
    _attendanceEnabled = schedule?.attendanceEnabled ?? true;
    _opensBefore = schedule?.checkInOpensMinutesBefore ?? 30;
    _closesAfter = schedule?.checkInClosesMinutesAfter ?? 30;
    _dwellMinutes = schedule?.minimumDwellMinutes ?? 10;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (!mounted || picked == null) return;
    setState(() => _startTime = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (!mounted || picked == null) return;
    setState(() => _endTime = picked);
  }

  Future<void> _save() async {
    final serviceName = _nameController.text.trim();
    if (serviceName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a service name.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final nextSchedule = ServiceSchedule(
      serviceId: widget.schedule?.serviceId ?? const Uuid().v4(),
      churchId: widget.churchId,
      name: serviceName,
      dayOfWeek: _selectedDay,
      startTime: _ScheduleManagementScreenState._formatTime(_startTime),
      endTime: _ScheduleManagementScreenState._formatTime(_endTime),
      recurrence: 'weekly',
      attendanceEnabled: _attendanceEnabled,
      checkInOpensMinutesBefore: _opensBefore,
      checkInClosesMinutesAfter: _closesAfter,
      minimumDwellMinutes: _dwellMinutes,
    );

    var saved = false;
    try {
      await widget.onSave(nextSchedule);
      saved = true;
      if (!mounted) return;
      Navigator.pop(
        context,
        widget.schedule == null
            ? 'Service schedule added.'
            : 'Service schedule updated.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save schedule: $e')),
      );
    } finally {
      if (mounted && !saved) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final schedule = widget.schedule;

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
              schedule == null
                  ? 'Add Recurring Service'
                  : 'Edit Recurring Service',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Create weekly services like Sunday Service, Prayer Meeting, and Bible Study so members can mark attendance during the correct window.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.repeat_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Repeats every week on the selected day.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameController,
              enabled: !_isSaving,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Service Name',
                hintText: 'Sunday Service, Prayer Meeting, Bible Study',
                prefixIcon: Icon(Icons.church_outlined),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              // ignore: deprecated_member_use
              value: _selectedDay,
              decoration: const InputDecoration(
                labelText: 'Day of Week',
                prefixIcon: Icon(Icons.calendar_month_outlined),
              ),
              items: _ScheduleManagementScreenState._dayItems,
              onChanged: _isSaving
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _selectedDay = value);
                      }
                    },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _TimeButton(
                    label: 'Start',
                    value: _startTime.format(context),
                    onTap: _isSaving ? null : _pickStartTime,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimeButton(
                    label: 'End',
                    value: _endTime.format(context),
                    onTap: _isSaving ? null : _pickEndTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Use for attendance'),
              subtitle: const Text(
                'Members can only mark present during this recurring service window.',
              ),
              value: _attendanceEnabled,
              onChanged: _isSaving
                  ? null
                  : (value) {
                      setState(() => _attendanceEnabled = value);
                    },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _NumberMenu(
                    label: 'Opens Before',
                    value: _opensBefore,
                    values: const [0, 15, 30, 45, 60],
                    suffix: 'min',
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _opensBefore = value);
                            }
                          },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _NumberMenu(
                    label: 'Closes After',
                    value: _closesAfter,
                    values: const [0, 15, 30, 45, 60],
                    suffix: 'min',
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _closesAfter = value);
                            }
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _NumberMenu(
              label: 'On-site time required before Present unlocks',
              value: _dwellMinutes,
              values: const [5, 10, 15, 20, 30],
              suffix: 'min',
              onChanged: _isSaving
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _dwellMinutes = value);
                      }
                    },
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(schedule == null ? 'Add' : 'Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.schedule,
    required this.onEdit,
    required this.onDelete,
  });

  final ServiceSchedule schedule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.event_available_outlined,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schedule.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_dayToString(schedule.dayOfWeek)} '
                  '- ${schedule.startTime} to ${schedule.endTime}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Repeats weekly - ${schedule.minimumDwellMinutes} min on-site before present',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NumberMenu extends StatelessWidget {
  const _NumberMenu({
    required this.label,
    required this.value,
    required this.values,
    required this.suffix,
    required this.onChanged,
  });

  final String label;
  final int value;
  final List<int> values;
  final String suffix;
  final ValueChanged<int?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      // ignore: deprecated_member_use
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final item in values)
          DropdownMenuItem(
            value: item,
            child: Text('$item $suffix'),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySchedules extends StatelessWidget {
  const _EmptySchedules({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_busy_outlined,
              size: 52,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              'No Recurring Services',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add weekly services like Sunday Service, Prayer Meeting, or Bible Study so auto-attendance knows when check-ins should happen.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add Schedule'),
            ),
          ],
        ),
      ),
    );
  }
}
