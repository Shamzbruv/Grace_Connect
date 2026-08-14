import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/daily_bible_quiz_service.dart';
import '../../widgets/quiz/monthly_quiz_leaderboard_panel.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/app_loader.dart';

class DailyBibleQuizAdminScreen extends StatefulWidget {
  const DailyBibleQuizAdminScreen({super.key});

  @override
  State<DailyBibleQuizAdminScreen> createState() =>
      _DailyBibleQuizAdminScreenState();
}

class _DailyBibleQuizAdminScreenState extends State<DailyBibleQuizAdminScreen> {
  final _client = Supabase.instance.client;
  final _quizService = DailyBibleQuizService();
  late Future<List<Map<String, dynamic>>> _future;
  Map<String, dynamic> _leaderboardData = const {};
  bool _leaderboardLoading = false;
  String? _selectedMonth;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _loadLeaderboard();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await _client
        .from('daily_bible_quizzes')
        .select('*, daily_bible_quiz_questions(*)')
        .order('quiz_date', ascending: false)
        .limit(30);
    return rows
        .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  void _refresh() {
    setState(() => _future = _load());
    _loadLeaderboard(quizMonth: _selectedMonth);
  }

  Future<void> _loadLeaderboard({String? quizMonth}) async {
    setState(() => _leaderboardLoading = true);
    try {
      final data = await _quizService.leaderboard(quizMonth: quizMonth);
      if (!mounted) return;
      setState(() {
        _leaderboardData = data;
        _selectedMonth = data['quiz_month']?.toString();
        _leaderboardLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _leaderboardLoading = false);
      AppFeedback.show(
        context,
        'Could not load monthly winners: $error',
        type: AppFeedbackType.warning,
      );
    }
  }

  Future<void> _togglePublished(Map<String, dynamic> quiz) async {
    final published = quiz['status'] == 'published';
    try {
      await _client.rpc(
        'admin_set_daily_bible_quiz_published',
        params: {
          'p_quiz_id': quiz['id'],
          'p_published': !published,
        },
      );
      if (mounted) {
        AppFeedback.show(
          context,
          published ? 'Quiz unpublished.' : 'Quiz published.',
          type: AppFeedbackType.success,
        );
        _refresh();
      }
    } catch (error) {
      if (mounted) {
        AppFeedback.show(
          context,
          'Could not update quiz: $error',
          type: AppFeedbackType.error,
        );
      }
    }
  }

  void _viewQuestions(Map<String, dynamic> quiz) {
    final questions = List<dynamic>.from(
        quiz['daily_bible_quiz_questions'] ?? const [])
      ..sort((a, b) =>
          (a['question_order'] as int).compareTo(b['question_order'] as int));
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(18),
          children: [
            Text(
              'Quiz Questions',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 12),
            for (final raw in questions)
              _QuestionReviewCard(
                  question: Map<String, dynamic>.from(raw as Map)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Daily Quiz Manager',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w900),
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Quizzes'),
              Tab(text: 'Monthly Winners'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _QuizHistoryTab(
              future: _future,
              onViewQuestions: _viewQuestions,
              onTogglePublished: _togglePublished,
            ),
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                MonthlyQuizLeaderboardPanel(
                  data: _leaderboardData,
                  loading: _leaderboardLoading,
                  onMonthChanged: (month) => _loadLeaderboard(quizMonth: month),
                ),
                const SizedBox(height: 14),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.schedule_outlined),
                    title: Text(
                      'Month-end finalization',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w900),
                    ),
                    subtitle: const Text(
                      'Winners are saved automatically at 12:05 AM Jamaica time on the first day of each month.',
                    ),
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

class _QuizHistoryTab extends StatelessWidget {
  const _QuizHistoryTab({
    required this.future,
    required this.onViewQuestions,
    required this.onTogglePublished,
  });

  final Future<List<Map<String, dynamic>>> future;
  final ValueChanged<Map<String, dynamic>> onViewQuestions;
  final ValueChanged<Map<String, dynamic>> onTogglePublished;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoader();
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Could not load quizzes: ${snapshot.error}'));
        }
        final quizzes = snapshot.data ?? const [];
        if (quizzes.isEmpty) {
          return const Center(
              child: Text('No quizzes have been generated yet.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          itemCount: quizzes.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final quiz = quizzes[index];
            final date = DateTime.tryParse(quiz['quiz_date']?.toString() ?? '');
            final questions = List<dynamic>.from(
                quiz['daily_bible_quiz_questions'] ?? const []);
            final published = quiz['status'] == 'published';
            return Card(
              child: ListTile(
                onTap: () => onViewQuestions(quiz),
                leading: CircleAvatar(
                  child: Icon(published ? Icons.check : Icons.edit_note),
                ),
                title: Text(
                  date == null ? 'Daily Quiz' : DateFormat.yMMMd().format(date),
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${quiz['status']} • ${questions.length} questions • ${quiz['generation_source']}',
                ),
                trailing: IconButton(
                  tooltip: published ? 'Unpublish' : 'Publish',
                  onPressed: () => onTogglePublished(quiz),
                  icon: Icon(
                    published
                        ? Icons.visibility_off_outlined
                        : Icons.publish_outlined,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _QuestionReviewCard extends StatelessWidget {
  const _QuestionReviewCard({required this.question});

  final Map<String, dynamic> question;

  @override
  Widget build(BuildContext context) {
    final options = [
      question['option_a'],
      question['option_b'],
      question['option_c'],
      question['option_d'],
    ];
    final correctIndex = question['correct_option_index'] as int? ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${question['question_order']}. ${question['question_text']}',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      i == correctIndex
                          ? Icons.check_circle_outline
                          : Icons.radio_button_unchecked,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(options[i]?.toString() ?? '')),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(question['explanation']?.toString() ?? ''),
          ],
        ),
      ),
    );
  }
}
