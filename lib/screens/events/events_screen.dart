import 'package:grace_connect/widgets/ui/app_skeleton_list_item.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/user_role_provider.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_button.dart';
import '../../widgets/ui/app_text_field.dart';
import '../../widgets/ui/app_loader.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../services/church_service.dart';
import '../../services/event_service.dart';
import '../../services/ministry_service.dart';
import '../../models/event_model.dart';
import '../../models/ministry.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({
    super.key,
    this.showBottomMenu = true,
  });

  final bool showBottomMenu;

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final EventService _eventService = EventService();
  final MinistryService _ministryService = MinistryService();
  final ChurchService _churchService = ChurchService();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  String? _churchId;
  User? _currentUser;
  bool _isLoading = true;
  bool _isAddingEvent = false;
  bool _canAddMinistryEvent = false;
  List<MinistryManager> _managedMinistries = [];
  final Map<String, String> _churchNamesById = {};
  final Set<String> _loadingChurchNameIds = {};
  String? _selectedMinistryId;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _showSharedEvents = false;
  bool _eventVisibleToAllChurches = false;

  @override
  void initState() {
    super.initState();
    _initUser();
  }

  Future<void> _initUser() async {
    _currentUser = Supabase.instance.client.auth.currentUser;
    if (_currentUser != null) {
      try {
        final userData = await Supabase.instance.client
            .from('users')
            .select('placeId')
            .eq('uid', _currentUser!.id)
            .single();

        if (mounted) {
          setState(() {
            _churchId = userData['placeId'];
            _isLoading = false;
          });
        }
        await _loadMinistryAccess();
      } catch (e) {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMinistryAccess() async {
    final managedMinistries = await _ministryService.fetchMyManagedMinistries();
    if (!mounted) return;
    setState(() {
      _managedMinistries = managedMinistries;
      _canAddMinistryEvent =
          managedMinistries.any((manager) => manager.canCreateEvents);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _handleRSVP(EventModel event) async {
    if (_currentUser == null) return;

    final isGoing = event.attendees.contains(_currentUser!.id);
    await _eventService.rsvpToEvent(event.id, _currentUser!.id, !isGoing);

    if (mounted) {
      AppFeedback.show(
        context,
        isGoing ? 'RSVP cancelled.' : 'RSVP confirmed.',
        type: isGoing ? AppFeedbackType.info : AppFeedbackType.success,
      );
    }
  }

  MinistryManager? _selectedMinistryForEvent() {
    final selectedId = _selectedMinistryId;
    if (selectedId == null) return null;

    for (final manager in _managedMinistries) {
      if (manager.ministryId == selectedId) {
        return manager;
      }
    }
    return null;
  }

  String _sourceLabelForEvent(
    UserRoleProvider roleProvider,
    MinistryManager? selectedMinistry,
  ) {
    if (selectedMinistry != null) {
      return 'From ${selectedMinistry.ministryName}';
    }

    return roleProvider.hasRole('Pastor') ||
            roleProvider.hasRole('Senior Pastor') ||
            roleProvider.hasRole('Assistant Pastor') ||
            roleProvider.hasRole('Acting Pastor')
        ? "From the Pastor's Desk"
        : 'Church Event';
  }

  Future<void> _saveEvent([EventModel? existingEvent]) async {
    if (_isAddingEvent) return;

    if (_titleController.text.trim().isEmpty ||
        _descriptionController.text.trim().isEmpty) {
      AppFeedback.show(
        context,
        'Please add a title and event details.',
        type: AppFeedbackType.warning,
      );
      return;
    }

    if (_churchId == null || _currentUser == null) return;

    setState(() => _isAddingEvent = true);
    final roleProvider = Provider.of<UserRoleProvider>(context, listen: false);
    final selectedMinistry = _selectedMinistryForEvent();
    final selectedMinistryId = selectedMinistry?.ministryId ??
        (existingEvent?.ministryId == _selectedMinistryId
            ? existingEvent?.ministryId
            : null);
    final selectedMinistryName = selectedMinistry?.ministryName ??
        (existingEvent?.ministryId == _selectedMinistryId
            ? existingEvent?.ministryName
            : null);

    if (!roleProvider.canManageEvents && selectedMinistryId == null) {
      setState(() => _isAddingEvent = false);
      AppFeedback.show(
        context,
        'Choose a ministry for this event.',
        type: AppFeedbackType.warning,
      );
      return;
    }

    final event = EventModel(
      id: existingEvent?.id ?? '',
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      date: DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      ),
      time: _selectedTime.format(context),
      location: _locationController.text.trim(),
      churchId: _churchId!,
      organizerId: existingEvent?.organizerId ?? _currentUser!.id,
      sourceLabel: selectedMinistryId != null
          ? 'From ${selectedMinistryName?.trim().isNotEmpty == true ? selectedMinistryName!.trim() : 'Ministry'}'
          : _sourceLabelForEvent(roleProvider, selectedMinistry),
      ministryId: selectedMinistryId,
      ministryName: selectedMinistryName ?? '',
      visibleToAllChurches: _eventVisibleToAllChurches,
      createdAt: existingEvent?.createdAt,
      attendees: existingEvent?.attendees ?? const [],
    );

    try {
      if (existingEvent == null) {
        await _eventService.addEvent(event);
      } else {
        await _eventService.updateEvent(event);
      }

      _titleController.clear();
      _descriptionController.clear();
      _locationController.clear();
      _selectedMinistryId = null;
      _eventVisibleToAllChurches = false;

      if (mounted) {
        Navigator.pop(context);
        AppFeedback.show(
          context,
          existingEvent == null
              ? 'Event added successfully.'
              : 'Event updated successfully.',
          type: AppFeedbackType.success,
        );
      }
    } catch (e) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        existingEvent == null
            ? 'Could not add event: $e'
            : 'Could not update event: $e',
        type: AppFeedbackType.error,
      );
    } finally {
      if (mounted) setState(() => _isAddingEvent = false);
    }
  }

  void _showAddEventDialog() {
    _showEventDialog();
  }

  void _showEditEventDialog(EventModel event) {
    _showEventDialog(existingEvent: event);
  }

  void _showEventDialog({EventModel? existingEvent}) {
    final isEditing = existingEvent != null;
    _titleController.text = existingEvent?.title ?? '';
    _descriptionController.text = existingEvent?.description ?? '';
    _locationController.text = existingEvent?.location ?? '';
    _selectedDate = existingEvent?.date ?? DateTime.now();
    _selectedTime = existingEvent != null
        ? TimeOfDay.fromDateTime(existingEvent.date)
        : TimeOfDay.now();
    _eventVisibleToAllChurches = existingEvent?.visibleToAllChurches ?? false;
    final roleProvider = Provider.of<UserRoleProvider>(context, listen: false);
    final ministryEventAccess =
        _managedMinistries.where((manager) => manager.canCreateEvents).toList();
    _selectedMinistryId = existingEvent?.ministryId ??
        (roleProvider.canManageEvents
            ? null
            : ministryEventAccess.isNotEmpty
                ? ministryEventAccess.first.ministryId
                : null);

    final selectedEventMinistryId = existingEvent?.ministryId;
    final hasSelectedEventMinistry = selectedEventMinistryId != null &&
        selectedEventMinistryId.isNotEmpty &&
        !ministryEventAccess
            .any((manager) => manager.ministryId == selectedEventMinistryId);

    final sourceOptions = <DropdownMenuItem<String>>[
      if (roleProvider.canManageEvents)
        const DropdownMenuItem(
          value: 'church',
          child: Text('Church-wide event'),
        ),
      ...ministryEventAccess.map(
        (manager) => DropdownMenuItem(
          value: manager.ministryId,
          child: Text(manager.ministryName),
        ),
      ),
      if (hasSelectedEventMinistry)
        DropdownMenuItem(
          value: selectedEventMinistryId,
          child: Text(
            existingEvent?.ministryName.trim().isNotEmpty == true
                ? existingEvent!.ministryName.trim()
                : 'Assigned ministry',
          ),
        ),
    ];
    final showSourcePicker = sourceOptions.length > 1;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(dialogContext).cardTheme.color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          isEditing ? 'Edit Event' : 'Add New Event',
          style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        content: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setDialogState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  controller: _titleController,
                  label: 'Title',
                  hint: 'e.g. Youth Revival Night',
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _descriptionController,
                  label: 'Event Details',
                  hint: 'What will be happening?',
                  maxLines: 4,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _locationController,
                  label: 'Location',
                  hint: 'Main sanctuary, online, etc.',
                ),
                if (showSourcePicker) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedMinistryId ?? 'church',
                    decoration: const InputDecoration(
                      labelText: 'Hosted by',
                      prefixIcon: Icon(Icons.groups_outlined),
                    ),
                    items: sourceOptions,
                    onChanged: (value) {
                      setDialogState(() {
                        _selectedMinistryId = value == 'church' ? null : value;
                      });
                    },
                  ),
                ],
                const SizedBox(height: 16),
                _EventAudienceTile(
                  visibleToAllChurches: _eventVisibleToAllChurches,
                  onChanged: (value) {
                    setDialogState(() {
                      _eventVisibleToAllChurches = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _PickerTile(
                        icon: Icons.calendar_month_outlined,
                        label: DateFormat('MMM d, yyyy').format(_selectedDate),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime.now()
                                .subtract(const Duration(days: 1)),
                            lastDate: DateTime.now()
                                .add(const Duration(days: 365 * 2)),
                          );
                          if (picked != null) {
                            setDialogState(() => _selectedDate = picked);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PickerTile(
                        icon: Icons.schedule_outlined,
                        label: _selectedTime.format(context),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _selectedTime,
                          );
                          if (picked != null) {
                            setDialogState(() => _selectedTime = picked);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isAddingEvent ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _isAddingEvent ? null : () => _saveEvent(existingEvent),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.primary,
              foregroundColor: Theme.of(dialogContext).colorScheme.onPrimary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _isAddingEvent
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isEditing ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEvent(EventModel event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          backgroundColor: theme.cardTheme.color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('Delete Event?'),
          content: Text(
            'This will remove "${event.title}" and its RSVP list.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _eventService.deleteEvent(event.id);
      if (!mounted) return;
      AppFeedback.show(
        context,
        'Event deleted.',
        type: AppFeedbackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        'Could not delete event: $e',
        type: AppFeedbackType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleProvider = Provider.of<UserRoleProvider>(context);
    final canAddEvent = roleProvider.canManageEvents || _canAddMinistryEvent;

    return AppScaffold(
      title: 'Events',
      showBottomMenu: widget.showBottomMenu,
      floatingActionButton: canAddEvent
          ? FloatingActionButton(
              backgroundColor: Theme.of(context).colorScheme.primary,
              onPressed: _showAddEventDialog,
              child: Icon(Icons.add,
                  color: Theme.of(context).colorScheme.onPrimary),
            )
          : null,
      body: _isLoading
          ? const Center(child: AppLoader())
          : _churchId == null
              ? const Center(child: Text('Please join a church to see events.'))
              : Column(
                  children: [
                    _EventScopeSelector(
                      showSharedEvents: _showSharedEvents,
                      onChanged: (value) {
                        setState(() => _showSharedEvents = value);
                      },
                    ),
                    Expanded(
                      child: StreamBuilder<List<EventModel>>(
                        stream: _eventService.getEvents(
                          _churchId!,
                          includeSharedEvents: _showSharedEvents,
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: 3,
                              itemBuilder: (_, __) =>
                                  const AppSkeletonListItem(),
                            );
                          }

                          if (snapshot.hasError) {
                            return Center(
                              child: Text('Error: ${snapshot.error}'),
                            );
                          }

                          final events = snapshot.data ?? [];
                          _queueChurchNameLoads(events);

                          if (events.isEmpty) {
                            return Center(
                              child: Text(
                                _showSharedEvents
                                    ? 'No shared upcoming events.'
                                    : 'No upcoming events.',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            );
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.all(16.0),
                            itemCount: events.length,
                            itemBuilder: (context, index) {
                              final event = events[index];
                              final isRsvped = _currentUser != null &&
                                  event.attendees.contains(_currentUser!.id);
                              final canViewRsvps =
                                  _canViewRsvpDetails(event, roleProvider);
                              final canManageEvent =
                                  _canManageEvent(event, roleProvider);

                              return _EventCard(
                                event: event,
                                viewerChurchId: _churchId!,
                                churchName: _churchNamesById[event.churchId],
                                isRsvped: isRsvped,
                                canViewRsvps: canViewRsvps,
                                canManageEvent: canManageEvent,
                                onRsvp: () => _handleRSVP(event),
                                onViewRsvps: canViewRsvps
                                    ? () => _showRsvpDetails(event)
                                    : null,
                                onEdit: canManageEvent
                                    ? () => _showEditEventDialog(event)
                                    : null,
                                onDelete: canManageEvent
                                    ? () => _deleteEvent(event)
                                    : null,
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

  bool _canViewRsvpDetails(EventModel event, UserRoleProvider roleProvider) {
    return _canManageEvent(event, roleProvider);
  }

  bool _canManageEvent(EventModel event, UserRoleProvider roleProvider) {
    if (_churchId == null || event.churchId != _churchId) return false;
    if (roleProvider.canManageEvents) return true;
    if (event.organizerId == _currentUser?.id) return true;
    final ministryId = event.ministryId;
    if (ministryId == null || ministryId.isEmpty) return false;
    return _managedMinistries.any(
      (manager) => manager.ministryId == ministryId && manager.canCreateEvents,
    );
  }

  Future<void> _showRsvpDetails(EventModel event) async {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return FutureBuilder<List<EventRsvpDetail>>(
          future: _eventService.fetchRsvpDetails(event.id),
          builder: (context, snapshot) {
            final theme = Theme.of(context);
            final attendees = snapshot.data ?? const <EventRsvpDetail>[];
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.62,
              minChildSize: 0.36,
              maxChildSize: 0.9,
              builder: (context, scrollController) {
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'RSVPs',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AppCard(
                      margin: EdgeInsets.zero,
                      child: Row(
                        children: [
                          Icon(
                            Icons.how_to_reg_outlined,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${attendees.length} ${attendees.length == 1 ? 'person is' : 'people are'} going',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: AppLoader(),
                        ),
                      )
                    else if (snapshot.hasError)
                      Text(
                        'Could not load RSVPs: ${snapshot.error}',
                        style: TextStyle(color: theme.colorScheme.error),
                      )
                    else if (attendees.isEmpty)
                      Text(
                        'No one has RSVP\'d yet.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      ...attendees.map(
                        (attendee) => _RsvpAttendeeTile(attendee: attendee),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _queueChurchNameLoads(List<EventModel> events) {
    final ownChurchId = _churchId;
    if (ownChurchId == null) return;

    for (final event in events) {
      final eventChurchId = event.churchId.trim();
      if (eventChurchId.isEmpty ||
          eventChurchId == ownChurchId ||
          _churchNamesById.containsKey(eventChurchId) ||
          _loadingChurchNameIds.contains(eventChurchId)) {
        continue;
      }

      _loadingChurchNameIds.add(eventChurchId);
      _churchService.getChurch(eventChurchId).then((church) {
        if (!mounted) return;
        setState(() {
          _churchNamesById[eventChurchId] =
              church?.name.trim().isNotEmpty == true
                  ? church!.name.trim()
                  : _prettifyChurchIdentifier(eventChurchId);
          _loadingChurchNameIds.remove(eventChurchId);
        });
      });
    }
  }
}

class _EventScopeSelector extends StatelessWidget {
  const _EventScopeSelector({
    required this.showSharedEvents,
    required this.onChanged,
  });

  final bool showSharedEvents;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      color: theme.colorScheme.surface,
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: false,
            icon: Icon(Icons.church_outlined),
            label: Text('My Church'),
          ),
          ButtonSegment(
            value: true,
            icon: Icon(Icons.public_outlined),
            label: Text('Shared'),
          ),
        ],
        selected: {showSharedEvents},
        onSelectionChanged: (values) => onChanged(values.first),
      ),
    );
  }
}

class _EventAudienceTile extends StatelessWidget {
  const _EventAudienceTile({
    required this.visibleToAllChurches,
    required this.onChanged,
  });

  final bool visibleToAllChurches;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: SwitchListTile.adaptive(
        value: visibleToAllChurches,
        onChanged: onChanged,
        secondary: Icon(
          visibleToAllChurches ? Icons.public_outlined : Icons.church_outlined,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          visibleToAllChurches ? 'Visible to all churches' : 'My church only',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          visibleToAllChurches
              ? 'Members from other churches can see and RSVP.'
              : 'Only your church can see this event.',
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _EventAction { edit, delete }

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.viewerChurchId,
    this.churchName,
    required this.isRsvped,
    required this.canViewRsvps,
    required this.canManageEvent,
    required this.onRsvp,
    this.onViewRsvps,
    this.onEdit,
    this.onDelete,
  });

  final EventModel event;
  final String viewerChurchId;
  final String? churchName;
  final bool isRsvped;
  final bool canViewRsvps;
  final bool canManageEvent;
  final VoidCallback onRsvp;
  final VoidCallback? onViewRsvps;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateFormat('EEEE, MMMM d, yyyy').format(event.date);
    final isOtherChurch = event.churchId.trim().isNotEmpty &&
        event.churchId.trim() != viewerChurchId.trim();
    final displayChurchName = churchName?.trim().isNotEmpty == true
        ? churchName!.trim()
        : _prettifyChurchIdentifier(event.churchId);
    final compactChurch = _compactChurchLabel(displayChurchName);
    final sourceChipLabel = event.ministryName.trim().isNotEmpty
        ? event.ministryName.trim()
        : event.sourceLabel.trim();
    final showSourceChip = sourceChipLabel.isNotEmpty &&
        (event.ministryId?.trim().isNotEmpty ?? false);

    return AppCard(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (showSourceChip)
                      Chip(
                        label: Text(sourceChipLabel),
                        avatar: const Icon(Icons.groups_outlined, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (event.visibleToAllChurches)
                      const Chip(
                        label: Text('Shared'),
                        avatar: Icon(Icons.public_outlined, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (isOtherChurch)
                      Tooltip(
                        message: displayChurchName,
                        child: Chip(
                          label: Text(compactChurch),
                          avatar: const Icon(Icons.church_outlined, size: 18),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    if (isRsvped)
                      const Chip(
                        label: Text('Going'),
                        avatar: Icon(Icons.check_circle_outline, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
              if (canManageEvent)
                PopupMenuButton<_EventAction>(
                  tooltip: 'Event actions',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (action) {
                    if (action == _EventAction.edit) {
                      onEdit?.call();
                    } else {
                      onDelete?.call();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _EventAction.edit,
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _EventAction.delete,
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Delete'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            event.title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(event.description),
          const SizedBox(height: 14),
          _EventMeta(icon: Icons.calendar_today_outlined, label: date),
          const SizedBox(height: 6),
          _EventMeta(icon: Icons.access_time_outlined, label: event.time),
          if (event.location.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            _EventMeta(
              icon: Icons.place_outlined,
              label: event.location.trim(),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  text: isRsvped ? 'Cancel RSVP' : 'RSVP Now',
                  isSecondary: isRsvped,
                  isFullWidth: true,
                  onPressed: onRsvp,
                  backgroundColor:
                      isRsvped ? Colors.transparent : theme.colorScheme.primary,
                  textColor: isRsvped
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onPrimary,
                ),
              ),
              if (canViewRsvps && onViewRsvps != null) ...[
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: 'View RSVPs',
                  onPressed: onViewRsvps,
                  icon: Badge.count(
                    count: event.attendees.length,
                    isLabelVisible: event.attendees.isNotEmpty,
                    child: const Icon(Icons.groups_2_outlined),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RsvpAttendeeTile extends StatelessWidget {
  const _RsvpAttendeeTile({required this.attendee});

  final EventRsvpDetail attendee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final churchName = attendee.churchName.trim().isNotEmpty
        ? attendee.churchName.trim()
        : _prettifyChurchIdentifier(attendee.churchId);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.16),
        child: Text(
          _initialFor(attendee.fullName),
          style: TextStyle(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      title: Text(
        attendee.fullName,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: attendee.isOtherChurch
          ? Text(churchName)
          : attendee.email.trim().isEmpty
              ? const Text('Your church')
              : Text(attendee.email),
      trailing: attendee.isOtherChurch
          ? Tooltip(
              message: churchName,
              child: Chip(
                label: Text(_compactChurchLabel(churchName)),
                visualDensity: VisualDensity.compact,
              ),
            )
          : null,
    );
  }
}

class _EventMeta extends StatelessWidget {
  const _EventMeta({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

String _compactChurchLabel(String churchName) {
  final clean = _prettifyChurchIdentifier(churchName);
  if (clean.length <= 24) return clean;
  final words = clean
      .replaceAll(RegExp(r'[^A-Za-z0-9 ]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) =>
          word.length > 2 &&
          !{'the', 'and', 'of', 'for', 'church'}.contains(
            word.toLowerCase(),
          ))
      .toList();
  final acronym = words.take(5).map((word) => word[0].toUpperCase()).join();
  return acronym.length >= 2 ? acronym : clean.substring(0, 24);
}

String _prettifyChurchIdentifier(String value) {
  var clean = value.trim();
  if (clean.isEmpty) return 'Church';
  clean = clean.replaceFirst(RegExp(r'^(local|manual)_'), '');
  clean = clean.replaceAll(RegExp(r'[_-]+'), ' ');
  clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.startsWith('church ') || clean.length > 48) return 'Other Church';

  final uppercaseWords = {'ntcog', 'cog', 'cogop', 'ja', 'jm'};
  return clean.split(' ').map((word) {
    final lower = word.toLowerCase();
    if (uppercaseWords.contains(lower)) return lower.toUpperCase();
    if (word.length <= 2) return lower;
    return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
  }).join(' ');
}

String _initialFor(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.characters.first.toUpperCase();
}
