import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import '../../models/announcement.dart';
import '../../providers/user_role_provider.dart';
import '../../services/announcement_service.dart';
import '../../services/google_places_service.dart';
import '../../services/ministry_service.dart';
import '../../widgets/ui/app_button.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_text_field.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final AnnouncementService _service = AnnouncementService();
  bool _markedNotificationsRead = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_markedNotificationsRead) return;

    final user = context.read<UserRoleProvider>().userProfile;
    if (user != null) {
      _markedNotificationsRead = true;
      unawaited(_service.markAnnouncementNotificationsRead(user.uid));
    }
  }

  Future<void> _showCreateAnnouncementSheet() async {
    final provider = context.read<UserRoleProvider>();
    final user = provider.userProfile;
    if (user == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    final linkController = TextEditingController();
    final locationController = TextEditingController();
    final managedMinistries =
        (await MinistryService().fetchMyManagedMinistries())
            .where((manager) => manager.canPublishAnnouncements)
            .toList();
    if (!mounted) {
      titleController.dispose();
      bodyController.dispose();
      return;
    }

    final canPublishChurchWide = user.capabilities.canPublishAnnouncements;
    if (!canPublishChurchWide && managedMinistries.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('You do not have announcement access yet.'),
        ),
      );
      titleController.dispose();
      bodyController.dispose();
      return;
    }

    var selectedSource =
        canPublishChurchWide ? 'church' : managedMinistries.first.ministryId;
    var priority = 'normal';
    int? expiresInDays;
    DateTime? scheduledAt;
    GooglePlaceResult? selectedPlace;
    var placeResults = const <GooglePlaceResult>[];
    var isSearchingPlaces = false;
    var isSubmitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final sheetPadding = MediaQuery.viewInsetsOf(sheetContext);
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              final title = titleController.text.trim();
              final body = bodyController.text.trim();

              if (title.isEmpty || body.isEmpty) {
                messenger.showSnackBar(
                  const SnackBar(
                      content: Text('Add a title and announcement body.')),
                );
                return;
              }

              setSheetState(() => isSubmitting = true);
              try {
                final selectedMinistry = selectedSource == 'church'
                    ? null
                    : managedMinistries.firstWhere(
                        (manager) => manager.ministryId == selectedSource,
                      );
                await _service.createAnnouncement(
                  author: user,
                  title: title,
                  body: body,
                  priority: priority,
                  ministryId: selectedMinistry?.ministryId,
                  ministryName: selectedMinistry?.ministryName ?? '',
                  expiresAt: expiresInDays == null
                      ? null
                      : DateTime.now().add(Duration(days: expiresInDays!)),
                  scheduledAt: scheduledAt,
                  linkUrl: linkController.text.trim().isEmpty
                      ? null
                      : linkController.text.trim(),
                  locationName: selectedPlace?.name,
                  locationAddress: selectedPlace?.address,
                  locationLatitude: selectedPlace?.latitude,
                  locationLongitude: selectedPlace?.longitude,
                  googlePlaceId: selectedPlace?.id,
                );

                if (!context.mounted) return;
                Navigator.pop(context);
                messenger.showSnackBar(
                  const SnackBar(content: Text('Announcement sent.')),
                );
              } catch (error) {
                messenger.showSnackBar(
                  SnackBar(
                      content: Text('Could not send announcement: $error')),
                );
              } finally {
                if (context.mounted) {
                  setSheetState(() => isSubmitting = false);
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(bottom: sheetPadding.bottom),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.campaign_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Create Announcement',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (canPublishChurchWide || managedMinistries.isNotEmpty)
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: selectedSource,
                        decoration: const InputDecoration(
                          labelText: 'Post From',
                          prefixIcon: Icon(Icons.groups_outlined),
                        ),
                        items: [
                          if (canPublishChurchWide)
                            const DropdownMenuItem(
                              value: 'church',
                              child: Text('Church-wide announcement'),
                            ),
                          ...managedMinistries.map(
                            (manager) => DropdownMenuItem(
                              value: manager.ministryId,
                              child: Text(manager.ministryName),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setSheetState(() => selectedSource = value);
                        },
                      ),
                    if (canPublishChurchWide || managedMinistries.isNotEmpty)
                      const SizedBox(height: 14),
                    AppTextField(
                      controller: titleController,
                      label: 'Title',
                      hint: 'Example: Sunday service update',
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: bodyController,
                      label: 'Message',
                      hint: 'Write the update members need to know',
                      maxLines: 6,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: linkController,
                      label: 'Link',
                      hint: 'https://example.com/details',
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: locationController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: selectedPlace == null
                            ? 'Location'
                            : selectedPlace!.name,
                        hintText: 'Search Google Maps',
                        prefixIcon: const Icon(Icons.place_outlined),
                        suffixIcon: IconButton(
                          tooltip: 'Search location',
                          icon: isSearchingPlaces
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.search),
                          onPressed: isSearchingPlaces
                              ? null
                              : () async {
                                  setSheetState(() => isSearchingPlaces = true);
                                  final results = await GooglePlacesService
                                      .searchChurchLocations(
                                    locationController.text,
                                  );
                                  setSheetState(() {
                                    placeResults = results;
                                    isSearchingPlaces = false;
                                  });
                                },
                        ),
                      ),
                      onSubmitted: (_) async {
                        setSheetState(() => isSearchingPlaces = true);
                        final results =
                            await GooglePlacesService.searchChurchLocations(
                          locationController.text,
                        );
                        setSheetState(() {
                          placeResults = results;
                          isSearchingPlaces = false;
                        });
                      },
                    ),
                    if (placeResults.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      AppCard(
                        child: Column(
                          children: [
                            for (final place in placeResults.take(4))
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.place_outlined),
                                title: Text(place.name),
                                subtitle: Text(place.address),
                                onTap: () {
                                  setSheetState(() {
                                    selectedPlace = place;
                                    locationController.text = place.name;
                                    placeResults = const [];
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      'Priority',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _ChoiceChip(
                          label: 'Normal',
                          selected: priority == 'normal',
                          onSelected: () =>
                              setSheetState(() => priority = 'normal'),
                        ),
                        _ChoiceChip(
                          label: 'Important',
                          selected: priority == 'important',
                          onSelected: () =>
                              setSheetState(() => priority = 'important'),
                        ),
                        _ChoiceChip(
                          label: 'Urgent',
                          selected: priority == 'urgent',
                          onSelected: () =>
                              setSheetState(() => priority = 'urgent'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Schedule',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.schedule_outlined),
                            label: Text(
                              scheduledAt == null
                                  ? 'Send now'
                                  : timeago.format(scheduledAt!),
                            ),
                            onPressed: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: scheduledAt ?? DateTime.now(),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 365)),
                              );
                              if (date == null || !context.mounted) return;
                              final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(
                                  scheduledAt ??
                                      DateTime.now()
                                          .add(const Duration(hours: 1)),
                                ),
                              );
                              if (time == null) return;
                              setSheetState(() {
                                scheduledAt = DateTime(
                                  date.year,
                                  date.month,
                                  date.day,
                                  time.hour,
                                  time.minute,
                                );
                              });
                            },
                          ),
                        ),
                        if (scheduledAt != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Send now',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setSheetState(() => scheduledAt = null);
                            },
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Expiry',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _ChoiceChip(
                          label: 'No expiry',
                          selected: expiresInDays == null,
                          onSelected: () =>
                              setSheetState(() => expiresInDays = null),
                        ),
                        _ChoiceChip(
                          label: '7 days',
                          selected: expiresInDays == 7,
                          onSelected: () =>
                              setSheetState(() => expiresInDays = 7),
                        ),
                        _ChoiceChip(
                          label: '30 days',
                          selected: expiresInDays == 30,
                          onSelected: () =>
                              setSheetState(() => expiresInDays = 30),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    AppButton(
                      text: 'Send Announcement',
                      icon: Icons.send_outlined,
                      isLoading: isSubmitting,
                      onPressed: submit,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    titleController.dispose();
    bodyController.dispose();
    linkController.dispose();
    locationController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserRoleProvider>().userProfile;

    return FutureBuilder<bool>(
      future: user == null
          ? Future<bool>.value(false)
          : _service.canPublishForUser(user),
      builder: (context, permissionSnapshot) {
        final canPublish = permissionSnapshot.data ?? _service.canPublish(user);

        return AppScaffold(
          title: 'Announcements',
          actions: [
            if (canPublish)
              IconButton(
                tooltip: 'Create announcement',
                onPressed: _showCreateAnnouncementSheet,
                icon: const Icon(Icons.add_circle_outline),
              ),
          ],
          floatingActionButton: canPublish
              ? FloatingActionButton.extended(
                  onPressed: _showCreateAnnouncementSheet,
                  icon: const Icon(Icons.campaign_outlined),
                  label: const Text('Create'),
                )
              : null,
          body: user == null
              ? const Center(child: CircularProgressIndicator())
              : _AnnouncementsList(
                  churchId: user.churchId,
                  service: _service,
                ),
        );
      },
    );
  }
}

class _AnnouncementsList extends StatelessWidget {
  const _AnnouncementsList({
    required this.churchId,
    required this.service,
  });

  final String churchId;
  final AnnouncementService service;

  @override
  Widget build(BuildContext context) {
    if (churchId.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Join a church to view announcements.'),
        ),
      );
    }

    return StreamBuilder<List<Announcement>>(
      stream: service.watchAnnouncements(churchId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load announcements: ${snapshot.error}'),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final announcements = snapshot.data ?? const [];
        if (announcements.isEmpty) {
          return const _EmptyAnnouncements();
        }

        return RefreshIndicator(
          onRefresh: () async {
            await service.fetchAnnouncements(churchId);
          },
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: announcements.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return _AnnouncementCard(announcement: announcements[index]);
            },
          ),
        );
      },
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.announcement});

  final Announcement announcement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priorityColor = _priorityColor(theme);
    final expiresAt = announcement.expiresAt;
    final ministryName = announcement.ministryName.trim();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: priorityColor.withValues(alpha: 0.16),
                child: Icon(_priorityIcon(), color: priorityColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            announcement.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _PriorityBadge(
                          label: _priorityLabel(),
                          color: priorityColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (ministryName.isNotEmpty) ministryName,
                        announcement.authorName,
                        timeago.format(announcement.createdAt),
                      ].join(' • '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            announcement.body,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
          ),
          if (expiresAt != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.schedule_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Expires ${timeago.format(expiresAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          if (announcement.linkUrl?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.link_outlined),
              label: const Text('Open Link'),
              onPressed: () => _openUrl(announcement.linkUrl!),
            ),
          ],
          if (announcement.locationName?.trim().isNotEmpty == true ||
              announcement.locationAddress?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.place_outlined),
              title: Text(
                announcement.locationName?.trim().isNotEmpty == true
                    ? announcement.locationName!
                    : 'Location',
              ),
              subtitle: announcement.locationAddress?.trim().isNotEmpty == true
                  ? Text(announcement.locationAddress!)
                  : null,
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _openMap(announcement),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openUrl(String value) async {
    final raw = value.trim();
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openMap(Announcement announcement) async {
    final lat = announcement.locationLatitude;
    final lng = announcement.locationLongitude;
    final query = Uri.encodeComponent(
      announcement.locationAddress?.trim().isNotEmpty == true
          ? announcement.locationAddress!
          : announcement.locationName ?? '',
    );
    final uri = lat != null && lng != null
        ? Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng')
        : Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Color _priorityColor(ThemeData theme) {
    return switch (announcement.priority) {
      'urgent' => theme.colorScheme.error,
      'important' => Colors.orange,
      _ => theme.colorScheme.primary,
    };
  }

  IconData _priorityIcon() {
    return switch (announcement.priority) {
      'urgent' => Icons.priority_high,
      'important' => Icons.campaign_outlined,
      _ => Icons.notifications_active_outlined,
    };
  }

  String _priorityLabel() {
    return switch (announcement.priority) {
      'urgent' => 'Urgent',
      'important' => 'Important',
      _ => 'Update',
    };
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

class _EmptyAnnouncements extends StatelessWidget {
  const _EmptyAnnouncements();

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
              Icons.campaign_outlined,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 14),
            Text(
              'No announcements yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Church-wide updates will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
