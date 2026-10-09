import 'package:grace_connect/tutorial/tutorial_anchor.dart';
import 'package:flutter/material.dart';

import '../../services/saved_items_service.dart';
import '../../services/reel_service.dart';
import '../../widgets/profile/profile_reels_grid.dart' show openReel;
import '../../widgets/ui/app_scaffold.dart';

class SavedItemsScreen extends StatefulWidget {
  const SavedItemsScreen({super.key});

  @override
  State<SavedItemsScreen> createState() => _SavedItemsScreenState();
}

class _SavedItemsScreenState extends State<SavedItemsScreen> {
  final SavedItemsService _service = SavedItemsService();
  final ReelService _reels = ReelService();
  late Future<List<SavedItem>> _savedFuture;

  @override
  void initState() {
    super.initState();
    _savedFuture = _load();
  }

  Future<List<SavedItem>> _load() async {
    final items = await _service.fetchSavedItems();
    final ids = items
        .where((i) => i.entityType == 'reel' && i.isAvailable)
        .map((i) => i.entityId)
        .toList();
    for (var start = 0; start < ids.length; start += 20) {
      try {
        await _reels.ensureMedia(ids.skip(start).take(20));
      } catch (_) {
        // A poster outage must not hide the member's saved collection.
      }
    }
    return items;
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _savedFuture = next);
    try {
      await next;
    } catch (_) {
      // The FutureBuilder owns the error and retry UI.
    }
  }

  Future<void> _openSavedItem(SavedItem item) async {
    if (!item.isAvailable) return;
    if (item.entityType == 'reel') {
      await openReel(context, item.entityId);
      if (mounted) await _refresh();
      return;
    }
    final route = switch (item.entityType) {
      'community_post' || 'community_posts' => '/community_post'
          '?entityTable=community_posts&entityId=${Uri.encodeComponent(item.entityId)}',
      'event' || 'events' => '/events',
      'grace_room' ||
      'grace_rooms' =>
        '/grace_rooms/room?id=${Uri.encodeComponent(item.entityId)}',
      _ => '',
    };
    if (route.isEmpty) return;
    await Navigator.of(context).pushNamed(route);
    if (mounted) await _refresh();
  }

  Future<void> _removeSavedItem(SavedItem item) async {
    try {
      await _service.unsave(
        entityType: item.entityType,
        entityId: item.entityId,
        localOnly: item.id.startsWith('local_'),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not remove this save. Please try again.')));
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Removed from Saved.')),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      tutorialId: 'saved_items',
      title: 'Saved',
      showBottomMenu: true,
      body: FutureBuilder<List<SavedItem>>(
        future: _savedFuture,
        builder: (context, snapshot) => TutorialReadiness(
          ready: snapshot.connectionState != ConnectionState.waiting &&
              !snapshot.hasError,
          child: Builder(builder: (context) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Your saved items could not be loaded.'),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: _refresh, child: const Text('Try again')),
              ]));
            }

            final items = snapshot.data ?? const [];
            if (items.isEmpty) {
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView(
                  padding: const EdgeInsets.all(32),
                  children: const [
                    SizedBox(height: 100),
                    Icon(Icons.bookmarks_outlined, size: 56),
                    SizedBox(height: 12),
                    Center(
                        child:
                            Text('Saved reels, posts and events appear here.')),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Dismissible(
                    key: ValueKey('${item.entityType}:${item.entityId}'),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) async {
                      await _removeSavedItem(item);
                      // Refresh replaces the collection. Never leave a dismissed
                      // element in a still-mounted FutureBuilder snapshot.
                      return false;
                    },
                    background: const ColoredBox(
                      color: Colors.red,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: EdgeInsets.only(right: 18),
                          child:
                              Icon(Icons.delete_outline, color: Colors.white),
                        ),
                      ),
                    ),
                    child: ListTile(
                      leading: _SavedItemPreview(
                        item: item,
                        posterUrl: item.entityType == 'reel'
                            ? _reels.cachedMedia(item.entityId)?.posterUrl
                            : null,
                        fallbackIcon: _iconFor(item.entityType),
                      ),
                      title: Text(
                        item.title.trim().isEmpty ? 'Saved item' : item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        item.subtitle.trim().isEmpty
                            ? item.entityType.replaceAll('_', ' ')
                            : item.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Remove from Saved',
                            icon: const Icon(Icons.bookmark_remove_outlined),
                            onPressed: () => _removeSavedItem(item),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: Theme.of(context)
                              .dividerColor
                              .withValues(alpha: 0.2),
                        ),
                      ),
                      onTap:
                          item.isAvailable ? () => _openSavedItem(item) : null,
                    ).tutorial('saved_items.tools', enabled: index == 0),
                  );
                },
              ),
            );
          }),
        ),
      ),
    );
  }

  IconData _iconFor(String entityType) {
    return switch (entityType) {
      'community_post' || 'community_posts' => Icons.dynamic_feed_outlined,
      'event' || 'events' => Icons.calendar_month_outlined,
      'grace_room' || 'grace_rooms' => Icons.forum_outlined,
      'reel' => Icons.video_library_outlined,
      _ => Icons.bookmark_outline,
    };
  }
}

class _SavedItemPreview extends StatelessWidget {
  const _SavedItemPreview({
    required this.item,
    required this.fallbackIcon,
    this.posterUrl,
  });

  final SavedItem item;
  final IconData fallbackIcon;
  final String? posterUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaUrl = item.mediaUrl.trim();
    final mediaType = item.mediaType.toLowerCase();
    final isVideo = mediaType.startsWith('video') || item.entityType == 'reel';

    Widget child;
    if (posterUrl?.isNotEmpty == true) {
      child = Image.network(posterUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(fallbackIcon, color: theme.colorScheme.primary));
    } else if (mediaUrl.isEmpty) {
      child = Icon(fallbackIcon, color: theme.colorScheme.primary);
    } else if (isVideo) {
      child = Icon(
        Icons.play_circle_outline,
        color: theme.colorScheme.onPrimaryContainer,
      );
    } else {
      child = Image.network(
        mediaUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(fallbackIcon, color: theme.colorScheme.primary),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: isVideo
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(child: child),
              if (isVideo)
                Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.videocam_outlined,
                      size: 14,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
