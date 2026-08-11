import 'package:flutter/material.dart';

import '../../../access/app_access_context.dart';

class UnconnectedDashboard extends StatelessWidget {
  const UnconnectedDashboard({
    super.key,
    required this.access,
  });

  final AppAccessContext access;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membership = access.membership;
    final hasInactiveSubscription = access.hasKnownInactiveSubscription;
    final churchName = membership.churchName?.trim().isNotEmpty == true
        ? membership.churchName!.trim()
        : 'your church';

    final title = hasInactiveSubscription
        ? '$churchName is in public mode'
        : membership.hasPendingMembership ||
                membership.hasPendingChurchApplication
            ? 'Your church connection is pending'
            : 'Connect with a church';
    final message = hasInactiveSubscription
        ? 'Community, public events, Bible, Grace Rooms, Saved, notifications, profile, and church transfer remain available. Church workspace tools unlock when the subscription is active.'
        : membership.hasPendingMembership ||
                membership.hasPendingChurchApplication
            ? 'You can keep using the Grace Connect Community while leaders review your request. Private church workspace tools unlock after approval.'
            : 'Grace Connect works best when you are connected to a local church. You can still use Community, Bible, public events, Grace Rooms, Saved, and discovery now.';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          Text(
            'Home',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          _DashboardPanel(
            icon: hasInactiveSubscription
                ? Icons.pause_circle_outline
                : Icons.church_outlined,
            title: title,
            message: message,
            primaryLabel: hasInactiveSubscription
                ? 'Transfer or support'
                : 'Find a Church',
            primaryIcon: hasInactiveSubscription
                ? Icons.compare_arrows_outlined
                : Icons.church_outlined,
            onPrimary: () => Navigator.of(context).pushNamed(
              hasInactiveSubscription ? '/church_transfer' : '/find_church',
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Available Now',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          _QuickGrid(
            items: const [
              _QuickAction(
                  'Community', '/community', Icons.dynamic_feed_outlined),
              _QuickAction(
                  'Public Events', '/events', Icons.calendar_month_outlined),
              _QuickAction('Bible', '/bible', Icons.menu_book_outlined),
              _QuickAction('Grace Rooms', '/grace_rooms', Icons.forum_outlined),
              _QuickAction('Saved', '/saved', Icons.bookmarks_outlined),
            ],
          ),
          const SizedBox(height: 18),
          _InfoList(
            title: 'Church membership unlocks',
            items: const [
              'Member directory and private church updates',
              'Attendance, ministries, schedules, and role-based tools',
              'Private prayer, counseling, care, finance, and analytics where permitted',
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 34, color: theme.colorScheme.primary),
            const SizedBox(height: 14),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onPrimary,
              icon: Icon(primaryIcon),
              label: Text(primaryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.items});

  final List<_QuickAction> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.6,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pushNamed(item.route),
          icon: Icon(item.icon, size: 18),
          label: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}

class _InfoList extends StatelessWidget {
  const _InfoList({
    required this.title,
    required this.items,
  });

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction {
  const _QuickAction(this.label, this.route, this.icon);

  final String label;
  final String route;
  final IconData icon;
}
