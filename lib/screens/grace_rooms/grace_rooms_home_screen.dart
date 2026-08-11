import 'package:flutter/material.dart';

import '../../services/grace_rooms_service.dart';
import '../../widgets/ui/app_scaffold.dart';

class GraceRoomsHomeScreen extends StatefulWidget {
  const GraceRoomsHomeScreen({super.key});

  @override
  State<GraceRoomsHomeScreen> createState() => _GraceRoomsHomeScreenState();
}

class _GraceRoomsHomeScreenState extends State<GraceRoomsHomeScreen> {
  final GraceRoomsService _service = GraceRoomsService();
  late Stream<List<GraceRoom>> _roomsStream;

  @override
  void initState() {
    super.initState();
    _roomsStream = _service.watchRooms();
  }

  void _refresh() {
    setState(() => _roomsStream = _service.watchRooms());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppScaffold(
      title: 'Grace Rooms',
      showBottomMenu: true,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.primaryContainer.withValues(alpha: 0.16),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: StreamBuilder<List<GraceRoom>>(
          stream: _roomsStream,
          initialData: GraceRoomsService.permanentRooms,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState == ConnectionState.waiting;
            final rooms = (snapshot.data?.isNotEmpty == true
                    ? snapshot.data!
                    : GraceRoomsService.permanentRooms)
                .toList()
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

            return RefreshIndicator(
              onRefresh: () async {
                _refresh();
                await _service.fetchRooms();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  _GraceRoomsHeader(
                    roomCount: rooms.length,
                    loading: loading,
                  ),
                  const SizedBox(height: 16),
                  for (final room in rooms) ...[
                    _GraceRoomCard(
                      room: room,
                      onTap: () => Navigator.of(context).pushNamed(
                        '/grace_rooms/room?id=${Uri.encodeComponent(room.id)}',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GraceRoomsHeader extends StatelessWidget {
  const _GraceRoomsHeader({
    required this.roomCount,
    required this.loading,
  });

  final int roomCount;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.volunteer_activism_outlined,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$roomCount permanent rooms',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  loading
                      ? 'Refreshing room presence'
                      : 'Always open for anonymous support',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (loading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

class _GraceRoomCard extends StatelessWidget {
  const _GraceRoomCard({
    required this.room,
    required this.onTap,
  });

  final GraceRoom room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _parseColor(room.accentHex, theme.colorScheme.primary);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.18 : 0.08,
                ),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(_iconForRoom(room.iconKey), color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        room.subtitle.isEmpty
                            ? room.description
                            : room.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _RoomPill(
                            icon: Icons.schedule_outlined,
                            label: '24/7',
                            color: accent,
                          ),
                          _RoomPill(
                            icon: Icons.visibility_off_outlined,
                            label: 'Anonymous',
                            color: accent,
                          ),
                          _RoomPill(
                            icon: Icons.auto_delete_outlined,
                            label: '24h messages',
                            color: accent,
                          ),
                          _RoomPill(
                            icon: Icons.people_outline,
                            label: room.liveParticipantCount == 1
                                ? '1 live now'
                                : '${room.liveParticipantCount} live now',
                            color: room.liveParticipantCount > 0
                                ? Colors.green
                                : accent,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomPill extends StatelessWidget {
  const _RoomPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconForRoom(String iconKey) {
  return switch (iconKey) {
    'heart' => Icons.favorite_border,
    'peace' => Icons.spa_outlined,
    'leaf' => Icons.eco_outlined,
    'people' => Icons.diversity_3_outlined,
    'flame' => Icons.local_fire_department_outlined,
    'shield' => Icons.shield_outlined,
    'rings' => Icons.favorite_outline,
    'home' => Icons.home_outlined,
    'path' => Icons.route_outlined,
    'sunrise' => Icons.wb_twilight_outlined,
    _ => Icons.forum_outlined,
  };
}

Color _parseColor(String value, Color fallback) {
  final normalized = value.trim().replaceFirst('#', '');
  final parsed = int.tryParse(
    normalized.length == 6 ? 'FF$normalized' : normalized,
    radix: 16,
  );
  return parsed == null ? fallback : Color(parsed);
}
