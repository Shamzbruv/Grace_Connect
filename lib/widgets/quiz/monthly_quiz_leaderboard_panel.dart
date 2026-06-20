import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';
import '../ui/app_loader.dart';

class MonthlyQuizLeaderboardPanel extends StatelessWidget {
  const MonthlyQuizLeaderboardPanel({
    super.key,
    required this.data,
    required this.loading,
    this.onMonthChanged,
    this.padding = EdgeInsets.zero,
  });

  final Map<String, dynamic> data;
  final bool loading;
  final ValueChanged<String>? onMonthChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (loading && data.isEmpty) {
      return Padding(
        padding: padding,
        child: const _LeaderboardShell(child: AppLoader()),
      );
    }

    final entries = List<dynamic>.from(data['entries'] ?? const []);
    final winners = List<dynamic>.from(data['winners'] ?? const []);
    final monthLabel = data['month_label']?.toString() ?? 'This Month';
    final selectedMonth = data['quiz_month']?.toString();
    final months = _monthOptions(selectedMonth);
    final currentMember = data['current_member'] is Map
        ? Map<String, dynamic>.from(data['current_member'] as Map)
        : null;
    final topThree = winners.isNotEmpty ? winners : entries.take(3).toList();
    final officialWinnersSaved = winners.isNotEmpty;

    return Padding(
      padding: padding,
      child: _LeaderboardShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.emoji_events_outlined,
                    color: AppColors.gold, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$monthLabel Bible Quiz Leaderboard',
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1.08,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Church members only • Jamaica calendar month',
                        style: GoogleFonts.outfit(
                          color: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color
                              ?.withValues(alpha: 0.72),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (months.length > 1) ...[
              const SizedBox(height: 16),
              _MonthSelector(
                selectedMonth: selectedMonth,
                months: months,
                onMonthChanged: onMonthChanged,
              ),
            ],
            const SizedBox(height: 18),
            _CurrentMemberStrip(currentMember: currentMember),
            const SizedBox(height: 18),
            _SectionTitle(
              icon: officialWinnersSaved
                  ? Icons.workspace_premium_outlined
                  : Icons.leaderboard_outlined,
              title: officialWinnersSaved ? 'Monthly Winners' : 'Current Top 3',
              subtitle: officialWinnersSaved
                  ? 'Saved after the month closed.'
                  : 'Official winners save when the month closes.',
            ),
            const SizedBox(height: 10),
            if (topThree.isEmpty)
              const _EmptyLeaderboardMessage(
                message:
                    'No scores yet. Start today’s quiz and begin earning points.',
              )
            else
              for (final raw in topThree)
                _WinnerTile(member: Map<String, dynamic>.from(raw as Map)),
            const SizedBox(height: 18),
            _SectionTitle(
              icon: Icons.format_list_numbered_outlined,
              title: 'Full Ranking',
              subtitle: _monthCountdownText(),
            ),
            const SizedBox(height: 10),
            if (entries.isEmpty)
              const _EmptyLeaderboardMessage(
                message:
                    'A new month has begun. Quiz points will appear here after members play.',
              )
            else
              for (final raw in entries.take(10))
                _RankingTile(member: Map<String, dynamic>.from(raw as Map)),
            if (loading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                minHeight: 4,
                borderRadius: BorderRadius.circular(999),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Map<String, String>> _monthOptions(String? selectedMonth) {
    final seen = <String>{};
    final options = <Map<String, String>>[];
    for (final raw
        in List<dynamic>.from(data['available_months'] ?? const [])) {
      if (raw is! Map) continue;
      final month = raw['quiz_month']?.toString() ?? '';
      if (month.isEmpty || !seen.add(month)) continue;
      options.add({
        'quiz_month': month,
        'label': raw['label']?.toString() ?? month,
      });
    }
    if (selectedMonth != null &&
        selectedMonth.isNotEmpty &&
        seen.add(selectedMonth)) {
      options.insert(0, {
        'quiz_month': selectedMonth,
        'label': data['month_label']?.toString() ?? selectedMonth,
      });
    }
    return options;
  }

  String _monthCountdownText() {
    final raw = data['next_month_at']?.toString();
    final target = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    if (target == null) return 'Scores reset automatically each month.';
    final remaining = target.difference(DateTime.now());
    if (remaining.isNegative) return 'This month is closed.';
    final days = remaining.inDays;
    final hours = remaining.inHours.remainder(24);
    if (days > 0) return '$days days, $hours hours left this month.';
    final minutes = remaining.inMinutes.remainder(60);
    return '$hours hours, $minutes minutes left this month.';
  }
}

class _LeaderboardShell extends StatelessWidget {
  const _LeaderboardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.28),
        ),
      ),
      child: child,
    );
  }
}

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.selectedMonth,
    required this.months,
    required this.onMonthChanged,
  });

  final String? selectedMonth;
  final List<Map<String, String>> months;
  final ValueChanged<String>? onMonthChanged;

  @override
  Widget build(BuildContext context) {
    final values = months.map((month) => month['quiz_month']).toSet();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: values.contains(selectedMonth) ? selectedMonth : null,
          isExpanded: true,
          icon: const Icon(Icons.expand_more),
          hint: const Text('Filter by month'),
          items: months
              .map(
                (month) => DropdownMenuItem<String>(
                  value: month['quiz_month'],
                  child: Text(month['label'] ?? month['quiz_month'] ?? ''),
                ),
              )
              .toList(),
          onChanged: onMonthChanged == null
              ? null
              : (value) {
                  if (value != null && value.isNotEmpty) {
                    onMonthChanged!(value);
                  }
                },
        ),
      ),
    );
  }
}

class _CurrentMemberStrip extends StatelessWidget {
  const _CurrentMemberStrip({required this.currentMember});

  final Map<String, dynamic>? currentMember;

  @override
  Widget build(BuildContext context) {
    final member = currentMember;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_pin_circle_outlined, color: AppColors.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              member == null
                  ? 'Your rank appears after you complete a quiz this month.'
                  : 'You are #${member['rank']} with ${member['total_points']} points.',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.outfit(
                  color: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.color
                      ?.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WinnerTile extends StatelessWidget {
  const _WinnerTile({required this.member});

  final Map<String, dynamic> member;

  @override
  Widget build(BuildContext context) {
    final rank = member['rank'] ?? 0;
    final medalColor = rank == 1
        ? AppColors.gold
        : rank == 2
            ? Colors.blueGrey.shade200
            : Colors.brown.shade300;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: medalColor.withValues(alpha: 0.22),
            child: Text(
              '#$rank',
              style: GoogleFonts.outfit(
                color: medalColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member['display_name']?.toString() ?? 'Member',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${member['perfect_quizzes'] ?? 0} perfect • ${member['correct_answers'] ?? 0} correct',
                  style: GoogleFonts.outfit(
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${member['total_points'] ?? 0}',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingTile extends StatelessWidget {
  const _RankingTile({required this.member});

  final Map<String, dynamic> member;

  @override
  Widget build(BuildContext context) {
    final highlighted = member['is_current_user'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.primary.withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(
              '#${member['rank'] ?? '-'}',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            child: Text(
              member['display_name']?.toString() ?? 'Member',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            '${member['total_points'] ?? 0} pts',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _EmptyLeaderboardMessage extends StatelessWidget {
  const _EmptyLeaderboardMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        message,
        style: GoogleFonts.outfit(fontWeight: FontWeight.w700, height: 1.35),
      ),
    );
  }
}
