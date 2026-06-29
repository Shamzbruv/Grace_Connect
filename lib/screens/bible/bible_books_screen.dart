import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/bible_data.dart';
import '../../services/daily_bible_quiz_service.dart';
import '../../services/daily_motivation_service.dart';
import '../../services/bible_streak_service.dart';
import 'bible_chapters_screen.dart';

class BibleBooksScreen extends StatefulWidget {
  const BibleBooksScreen({super.key});

  @override
  State<BibleBooksScreen> createState() => _BibleBooksScreenState();
}

class _BibleBooksScreenState extends State<BibleBooksScreen> {
  late Future<BibleStreakStatus> _streakFuture;
  late Future<_BibleActionAvailability> _actionAvailabilityFuture;

  @override
  void initState() {
    super.initState();
    _streakFuture = BibleStreakService().currentStatus();
    _actionAvailabilityFuture = _loadActionAvailability();
  }

  void _refreshStreak() {
    setState(() {
      _streakFuture = BibleStreakService().currentStatus();
      _actionAvailabilityFuture = _loadActionAvailability();
    });
  }

  Future<_BibleActionAvailability> _loadActionAvailability() async {
    final results = await Future.wait<bool>([
      _hasDailyWord(),
      _hasAvailableQuiz(),
    ]);

    return _BibleActionAvailability(
      dailyWordAvailable: results[0],
      quizAvailable: results[1],
    );
  }

  Future<bool> _hasDailyWord() async {
    try {
      final word = await DailyMotivationService().fetchToday();
      return word != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasAvailableQuiz() async {
    try {
      final status = await DailyBibleQuizService().status();
      return status['can_start'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openDailyQuiz() async {
    await Navigator.pushNamed(context, '/daily_bible_quiz');
    if (!mounted) return;
    setState(() {
      _actionAvailabilityFuture = _loadActionAvailability();
    });
  }

  Future<void> _openDailyWord() async {
    await Navigator.pushNamed(context, '/daily_word');
    if (!mounted) return;
    setState(() {
      _actionAvailabilityFuture = _loadActionAvailability();
    });
  }

  Future<void> _showStreakInfo(BibleStreakStatus status) async {
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.local_fire_department,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  'Bible Streak',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '${status.count} day${status.count == 1 ? '' : 's'}',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            _StreakRequirementRow(
              icon: Icons.timer_outlined,
              title: 'Earn today',
              message: status.requirementText,
            ),
            const SizedBox(height: 12),
            _StreakRequirementRow(
              icon: status.completedToday
                  ? Icons.check_circle_outline
                  : Icons.calendar_today_outlined,
              title:
                  status.completedToday ? 'Completed today' : 'Keep it going',
              message: status.keepGoingText,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLeaderboard() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => FutureBuilder<List<BibleStreakLeaderboardEntry>>(
        future: BibleStreakService().fetchChurchLeaderboard(),
        builder: (context, snapshot) {
          final theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.emoji_events_outlined,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      'Bible Streak Leaderboard',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child:
                        Text('Could not load leaderboard: ${snapshot.error}'),
                  )
                else if ((snapshot.data ?? const []).isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'No streaks have been recorded yet. Read for 5 minutes to appear here.',
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.62,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: snapshot.data!.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = snapshot.data![index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundImage: entry.photoUrl?.isNotEmpty == true
                                ? NetworkImage(entry.photoUrl!)
                                : null,
                            child: entry.photoUrl?.isNotEmpty == true
                                ? null
                                : Text('${index + 1}'),
                          ),
                          title: Text(entry.userName),
                          trailing: Text(
                            '${entry.streakCount} day${entry.streakCount == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final oldTestament =
        BibleData.allBooks.where((b) => b.testament == 'Old').toList();
    final newTestament =
        BibleData.allBooks.where((b) => b.testament == 'New').toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leadingWidth: 52,
          leading: FutureBuilder<_BibleActionAvailability>(
            future: _actionAvailabilityFuture,
            builder: (context, snapshot) {
              return IconButton(
                tooltip: 'Daily Bible Quiz',
                onPressed: _openDailyQuiz,
                icon: _ActionBadgeIcon(
                  icon: Icons.psychology_alt_outlined,
                  showBadge: snapshot.data?.quizAvailable == true,
                ),
              );
            },
          ),
          titleSpacing: 4,
          centerTitle: false,
          title: Text(
            'The Bible',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.indigo,
          actions: [
            FutureBuilder<_BibleActionAvailability>(
              future: _actionAvailabilityFuture,
              builder: (context, snapshot) {
                return IconButton(
                  tooltip: 'Daily Word',
                  onPressed: _openDailyWord,
                  icon: _ActionBadgeIcon(
                    icon: Icons.wb_sunny_outlined,
                    showBadge: snapshot.data?.dailyWordAvailable == true,
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'Bible streak leaderboard',
              onPressed: _showLeaderboard,
              icon: const Icon(Icons.emoji_events_outlined),
            ),
            FutureBuilder<BibleStreakStatus>(
              future: _streakFuture,
              builder: (context, snapshot) {
                final status = snapshot.data ??
                    const BibleStreakStatus(
                      count: 0,
                      completedToday: false,
                    );
                final streak = status.count;
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ActionChip(
                    avatar: const Icon(Icons.local_fire_department, size: 18),
                    label: Text('$streak'),
                    tooltip:
                        'Bible streak: $streak day${streak == 1 ? '' : 's'}',
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showStreakInfo(status),
                  ),
                );
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Old Testament'),
              Tab(text: 'New Testament'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildBookList(context, oldTestament),
            _buildBookList(context, newTestament),
          ],
        ),
      ),
    );
  }

  Widget _buildBookList(BuildContext context, List<BibleBook> books) {
    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (ctx, i) {
        final book = books[i];
        return ListTile(
          title: Text(book.name,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BibleChaptersScreen(book: book),
              ),
            ).then((_) => _refreshStreak());
          },
        );
      },
    );
  }
}

class _StreakRequirementRow extends StatelessWidget {
  const _StreakRequirementRow({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.primary, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BibleActionAvailability {
  const _BibleActionAvailability({
    required this.dailyWordAvailable,
    required this.quizAvailable,
  });

  final bool dailyWordAvailable;
  final bool quizAvailable;
}

class _ActionBadgeIcon extends StatelessWidget {
  const _ActionBadgeIcon({
    required this.icon,
    required this.showBadge,
  });

  final IconData icon;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (showBadge)
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 1.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
