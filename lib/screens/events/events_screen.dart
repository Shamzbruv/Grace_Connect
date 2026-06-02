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
import '../../services/event_service.dart';
import '../../models/event_model.dart';

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
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  String? _churchId;
  User? _currentUser;
  bool _isLoading = true;
  bool _isAddingEvent = false;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();

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
      } catch (e) {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isGoing ? 'RSVP Cancelled' : 'RSVP Confirmed!')),
      );
    }
  }

  Future<void> _addEvent() async {
    if (_isAddingEvent) return;

    if (_titleController.text.trim().isEmpty ||
        _descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a title and event details.')),
      );
      return;
    }

    if (_churchId == null || _currentUser == null) return;

    setState(() => _isAddingEvent = true);
    final roleProvider = Provider.of<UserRoleProvider>(context, listen: false);
    final sourceLabel = roleProvider.hasRole('Pastor') ||
            roleProvider.hasRole('Senior Pastor') ||
            roleProvider.hasRole('Assistant Pastor') ||
            roleProvider.hasRole('Acting Pastor')
        ? "From the Pastor's Desk"
        : 'Church Event';

    final newEvent = EventModel(
      id: '', // Service handles ID
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
      organizerId: _currentUser!.id,
      sourceLabel: sourceLabel,
      attendees: [],
    );

    try {
      await _eventService.addEvent(newEvent);

      _titleController.clear();
      _descriptionController.clear();
      _locationController.clear();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event added successfully!')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add event: $e')),
      );
    } finally {
      if (mounted) setState(() => _isAddingEvent = false);
    }
  }

  void _showAddEventDialog() {
    _selectedDate = DateTime.now();
    _selectedTime = TimeOfDay.now();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(dialogContext).cardTheme.color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Add New Event',
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
            onPressed: _isAddingEvent ? null : _addEvent,
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
                : const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roleProvider = Provider.of<UserRoleProvider>(context);
    final canAddEvent = roleProvider.canManageEvents;

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
              : StreamBuilder<List<EventModel>>(
                  stream: _eventService.getEvents(_churchId!),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return ListView.builder(
                          itemCount: 3,
                          itemBuilder: (_, __) => const AppSkeletonListItem());
                    }

                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }

                    final events = snapshot.data ?? [];

                    if (events.isEmpty) {
                      return Center(
                          child: Text('No upcoming events.',
                              style: TextStyle(color: Colors.grey[600])));
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16.0),
                      itemCount: events.length,
                      itemBuilder: (context, index) {
                        final event = events[index];
                        final isRsvped = _currentUser != null &&
                            event.attendees.contains(_currentUser!.id);

                        return _EventCard(
                          event: event,
                          isRsvped: isRsvped,
                          onRsvp: () => _handleRSVP(event),
                        );
                      },
                    );
                  },
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

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.isRsvped,
    required this.onRsvp,
  });

  final EventModel event;
  final bool isRsvped;
  final VoidCallback onRsvp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateFormat('EEEE, MMMM d, yyyy').format(event.date);

    return AppCard(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                label: Text(event.sourceLabel),
                avatar: const Icon(Icons.campaign_outlined, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              if (isRsvped)
                const Chip(
                  label: Text('Going'),
                  avatar: Icon(Icons.check_circle_outline, size: 18),
                  visualDensity: VisualDensity.compact,
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
          AppButton(
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
        ],
      ),
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
