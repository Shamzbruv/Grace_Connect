import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/daily_bible_quiz_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/quiz/monthly_quiz_leaderboard_panel.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/app_loader.dart';

class BibleQuizScreen extends StatefulWidget {
  const BibleQuizScreen({super.key, this.initialMonth});

  final String? initialMonth;

  @override
  State<BibleQuizScreen> createState() => _BibleQuizScreenState();
}

class _BibleQuizScreenState extends State<BibleQuizScreen>
    with WidgetsBindingObserver {
  final _service = DailyBibleQuizService();
  Future<Map<String, dynamic>>? _statusFuture;
  Map<String, dynamic>? _attempt;
  Map<String, dynamic>? _question;
  Map<String, dynamic>? _lastFeedback;
  Map<String, dynamic>? _completion;
  Map<String, dynamic> _leaderboardData = const {};
  bool _leaderboardLoading = false;
  String? _selectedQuizMonth;
  DateTime? _nextRefreshAt;
  Timer? _questionTimer;
  Timer? _heartbeatTimer;
  Timer? _countdownTimer;
  int _secondsLeft = 30;
  bool _submitting = false;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedQuizMonth = widget.initialMonth;
    _loadStatus();
    unawaited(_loadLeaderboard(quizMonth: _selectedQuizMonth));
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _questionTimer?.cancel();
    _heartbeatTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_active || state == AppLifecycleState.resumed) return;
    final attemptId = _attempt?['id']?.toString();
    if (attemptId != null && attemptId.isNotEmpty) {
      unawaited(_service.abandon(attemptId));
    }
    _failLocally();
  }

  void _loadStatus() {
    _stopQuizTimers();
    setState(() {
      _active = false;
      _attempt = null;
      _question = null;
      _lastFeedback = null;
      _completion = null;
      _statusFuture = _service.status(generateIfMissing: true);
    });
  }

  Future<void> _confirmAndStart() async {
    final shouldStart = await AppFeedback.confirm(
      context,
      title: 'Daily Bible Quiz Rules',
      message: 'You get one attempt each day.\n'
          'You have 30 seconds for every question.\n'
          'Each correct answer earns 20 points, up to 100 points.\n'
          'Keep Grace Connect open while playing.\n'
          'Leaving or backgrounding the app will end your quiz attempt.\n'
          'Your church leaderboard updates after you finish.\n'
          'A new quiz becomes available every day at 7:00 AM.',
      confirmLabel: 'Start Quiz',
      icon: Icons.quiz_outlined,
    );
    if (shouldStart == true) await _startQuiz();
  }

  Future<void> _startQuiz() async {
    try {
      final data = await _service.start();
      setState(() {
        _attempt = Map<String, dynamic>.from(data['attempt'] as Map);
        _question = Map<String, dynamic>.from(data['question'] as Map);
        _nextRefreshAt =
            DateTime.tryParse(data['next_refresh_at']?.toString() ?? '');
        _lastFeedback = null;
        _completion = null;
        _active = true;
      });
      _startQuestionTimers();
    } catch (error) {
      if (mounted) {
        AppFeedback.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          type: AppFeedbackType.warning,
        );
        _loadStatus();
      }
    }
  }

  void _startQuestionTimers() {
    _questionTimer?.cancel();
    _heartbeatTimer?.cancel();
    _secondsLeft = 30;
    _questionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_active) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        timer.cancel();
        unawaited(_submitAnswer(-1));
      }
    });
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final attemptId = _attempt?['id']?.toString();
      if (_active && attemptId != null) {
        unawaited(_service.heartbeat(attemptId));
      }
    });
  }

  Future<void> _submitAnswer(int selectedIndex) async {
    if (_submitting || !_active || _question == null || _attempt == null) {
      return;
    }
    setState(() => _submitting = true);
    _questionTimer?.cancel();
    try {
      final data = await _service.submitAnswer(
        attemptId: _attempt!['id'].toString(),
        questionId: _question!['id'].toString(),
        selectedOptionIndex: selectedIndex,
      );
      final feedback = Map<String, dynamic>.from(data['feedback'] as Map);
      final completed = data['completed'] == true;
      setState(() {
        _lastFeedback = feedback;
        _completion = completed ? feedback : null;
        _question = data['next_question'] == null
            ? null
            : Map<String, dynamic>.from(data['next_question'] as Map);
        _nextRefreshAt =
            DateTime.tryParse(data['next_refresh_at']?.toString() ?? '');
        _active = !completed;
      });
      if (completed) {
        _stopQuizTimers();
        await _loadLeaderboard();
      }
    } catch (error) {
      if (mounted) {
        AppFeedback.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          type: AppFeedbackType.error,
        );
        _loadStatus();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _nextQuestion() async {
    setState(() => _lastFeedback = null);
    _startQuestionTimers();
  }

  Future<void> _loadLeaderboard({String? quizMonth}) async {
    if (mounted) setState(() => _leaderboardLoading = true);
    try {
      final data = await _service.leaderboard(
        quizMonth: quizMonth ?? _selectedQuizMonth,
      );
      if (!mounted) return;
      setState(() {
        _leaderboardData = data;
        _selectedQuizMonth = data['quiz_month']?.toString();
        _leaderboardLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _leaderboardLoading = false;
        _leaderboardData = {
          if (_selectedQuizMonth != null) 'quiz_month': _selectedQuizMonth,
          'entries': const [],
          'winners': const [],
        };
      });
    }
  }

  void _failLocally() {
    _stopQuizTimers();
    setState(() {
      _active = false;
      _question = null;
      _completion = {
        'abandoned': true,
        'total_score': _attempt?['total_score'] ?? 0,
        'correct_answers': _attempt?['correct_answers'] ?? 0,
      };
    });
  }

  void _stopQuizTimers() {
    _questionTimer?.cancel();
    _heartbeatTimer?.cancel();
  }

  String _countdownText() {
    final target = _nextRefreshAt;
    if (target == null) return 'soon';
    final remaining = target.difference(DateTime.now());
    if (remaining.isNegative) return 'now';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    final seconds = remaining.inSeconds.remainder(60);
    return '${hours}h ${minutes}m ${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Daily Bible Quiz',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadStatus,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_question != null && _lastFeedback == null) {
      return _ActiveQuestionView(
        question: _question!,
        secondsLeft: _secondsLeft,
        submitting: _submitting,
        onAnswer: _submitAnswer,
      );
    }
    if (_lastFeedback != null && _completion == null) {
      return _FeedbackView(
        feedback: _lastFeedback!,
        onContinue: _nextQuestion,
      );
    }
    if (_completion != null) {
      return _CompletionView(
        completion: _completion!,
        leaderboardData: _leaderboardData,
        leaderboardLoading: _leaderboardLoading,
        onMonthChanged: (month) => _loadLeaderboard(quizMonth: month),
        countdown: _countdownText(),
      );
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: _statusFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoader();
        }
        if (snapshot.hasError) {
          return _QuizLanding(
            title: 'Quiz unavailable',
            message: 'Please check again soon.',
            countdown: _countdownText(),
            canStart: false,
            onStart: _confirmAndStart,
            leaderboardData: _leaderboardData,
            leaderboardLoading: _leaderboardLoading,
            onMonthChanged: (month) => _loadLeaderboard(quizMonth: month),
          );
        }
        final data = snapshot.data ?? const {};
        _nextRefreshAt ??=
            DateTime.tryParse(data['next_refresh_at']?.toString() ?? '');
        final attempt = data['attempt'];
        if (attempt is Map && attempt.isNotEmpty) {
          return _AttemptStatusView(
            attempt: Map<String, dynamic>.from(attempt),
            leaderboardData: _leaderboardData,
            leaderboardLoading: _leaderboardLoading,
            onMonthChanged: (month) => _loadLeaderboard(quizMonth: month),
            countdown: _countdownText(),
          );
        }
        return _QuizLanding(
          title: data['available'] == true
              ? 'Today’s quiz is ready'
              : 'No quiz yet',
          message: data['available'] == true
              ? 'Five questions. Up to 100 points. Church leaderboard only.'
              : 'The next Daily Bible Quiz refreshes at 7:00 AM.',
          countdown: _countdownText(),
          canStart: data['can_start'] == true,
          onStart: _confirmAndStart,
          leaderboardData: _leaderboardData,
          leaderboardLoading: _leaderboardLoading,
          onMonthChanged: (month) => _loadLeaderboard(quizMonth: month),
        );
      },
    );
  }
}

class _QuizLanding extends StatelessWidget {
  const _QuizLanding({
    required this.title,
    required this.message,
    required this.countdown,
    required this.canStart,
    required this.onStart,
    required this.leaderboardData,
    required this.leaderboardLoading,
    required this.onMonthChanged,
  });

  final String title;
  final String message;
  final String countdown;
  final bool canStart;
  final VoidCallback onStart;
  final Map<String, dynamic> leaderboardData;
  final bool leaderboardLoading;
  final ValueChanged<String> onMonthChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.quiz_outlined, color: AppColors.gold, size: 44),
              const SizedBox(height: 18),
              Text(
                title,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: GoogleFonts.outfit(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  _QuizChip(icon: Icons.help_outline, label: '5 Questions'),
                  _QuizChip(icon: Icons.stars_outlined, label: '100 Points'),
                  _QuizChip(icon: Icons.timer_outlined, label: '30s Each'),
                ],
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: canStart ? onStart : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start Today’s Quiz'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: ListTile(
            leading: const Icon(Icons.hourglass_bottom),
            title: const Text('Next refresh'),
            subtitle: Text(countdown),
          ),
        ),
        const SizedBox(height: 18),
        MonthlyQuizLeaderboardPanel(
          data: leaderboardData,
          loading: leaderboardLoading,
          onMonthChanged: onMonthChanged,
        ),
      ],
    );
  }
}

class _ActiveQuestionView extends StatelessWidget {
  const _ActiveQuestionView({
    required this.question,
    required this.secondsLeft,
    required this.submitting,
    required this.onAnswer,
  });

  final Map<String, dynamic> question;
  final int secondsLeft;
  final bool submitting;
  final ValueChanged<int> onAnswer;

  @override
  Widget build(BuildContext context) {
    final options = List<dynamic>.from(question['options'] ?? const []);
    final order = question['order'] ?? 1;
    final progress = (order as num).toDouble() / 5;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 9,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 12),
            _TimerPill(secondsLeft: secondsLeft),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          'Question $order of 5',
          style: GoogleFonts.outfit(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          question['question']?.toString() ?? '',
          style: GoogleFonts.outfit(
            fontSize: 25,
            fontWeight: FontWeight.w900,
            height: 1.16,
          ),
        ),
        const SizedBox(height: 22),
        for (var i = 0; i < options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.tonal(
              onPressed: submitting ? null : () => onAnswer(i),
              style: FilledButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(
                '${String.fromCharCode(65 + i)}. ${options[i]}',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FeedbackView extends StatelessWidget {
  const _FeedbackView({required this.feedback, required this.onContinue});

  final Map<String, dynamic> feedback;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final correct = feedback['correct'] == true;
    final timedOut = feedback['timed_out'] == true;
    final scriptures =
        List<dynamic>.from(feedback['scripture_references'] ?? const []);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(
          correct ? Icons.check_circle_outline : Icons.cancel_outlined,
          color: correct
              ? Colors.greenAccent.shade400
              : Colors.amberAccent.shade400,
          size: 64,
        ),
        const SizedBox(height: 18),
        Text(
          correct
              ? 'Correct'
              : timedOut
                  ? 'Time expired'
                  : 'Not quite',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(fontSize: 30, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Text(
          correct
              ? '+${feedback['points_awarded']} points'
              : 'Correct answer: ${feedback['correct_answer']}',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feedback['explanation']?.toString() ?? '',
                  style: GoogleFonts.outfit(fontSize: 16, height: 1.4),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: scriptures
                      .map(
                        (ref) => Chip(
                          avatar:
                              const Icon(Icons.menu_book_outlined, size: 16),
                          label: Text(ref.toString()),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: onContinue,
          child: const Text('Next Question'),
        ),
      ],
    );
  }
}

class _CompletionView extends StatelessWidget {
  const _CompletionView({
    required this.completion,
    required this.leaderboardData,
    required this.leaderboardLoading,
    required this.onMonthChanged,
    required this.countdown,
  });

  final Map<String, dynamic> completion;
  final Map<String, dynamic> leaderboardData;
  final bool leaderboardLoading;
  final ValueChanged<String> onMonthChanged;
  final String countdown;

  @override
  Widget build(BuildContext context) {
    final abandoned = completion['abandoned'] == true;
    final score = completion['total_score'] ?? 0;
    final correct = completion['correct_answers'] ?? 0;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              Icon(
                abandoned
                    ? Icons.lock_clock_outlined
                    : Icons.emoji_events_outlined,
                size: 58,
                color: abandoned ? Colors.amber : AppColors.gold,
              ),
              const SizedBox(height: 14),
              Text(
                abandoned ? 'Attempt ended' : '$score / 100',
                style: GoogleFonts.outfit(
                    fontSize: 34, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                abandoned
                    ? 'Your quiz attempt ended because Grace Connect was closed or moved to the background. For fairness, you can take the next Daily Bible Quiz when it refreshes.'
                    : '$correct of 5 answers correct',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 18),
              Chip(
                avatar: const Icon(Icons.hourglass_bottom, size: 18),
                label: Text('Next quiz in $countdown'),
              ),
            ],
          ),
        ),
        if (!abandoned) ...[
          const SizedBox(height: 20),
          MonthlyQuizLeaderboardPanel(
            data: leaderboardData,
            loading: leaderboardLoading,
            onMonthChanged: onMonthChanged,
          ),
        ],
      ],
    );
  }
}

class _AttemptStatusView extends StatelessWidget {
  const _AttemptStatusView({
    required this.attempt,
    required this.leaderboardData,
    required this.leaderboardLoading,
    required this.onMonthChanged,
    required this.countdown,
  });

  final Map<String, dynamic> attempt;
  final Map<String, dynamic> leaderboardData;
  final bool leaderboardLoading;
  final ValueChanged<String> onMonthChanged;
  final String countdown;

  @override
  Widget build(BuildContext context) {
    final status = attempt['status']?.toString() ?? 'completed';
    return _CompletionView(
      completion: {
        'abandoned': status != 'completed',
        'total_score': attempt['total_score'] ?? 0,
        'correct_answers': attempt['correct_answers'] ?? 0,
      },
      leaderboardData: leaderboardData,
      leaderboardLoading: leaderboardLoading,
      onMonthChanged: onMonthChanged,
      countdown: countdown,
    );
  }
}

class _TimerPill extends StatelessWidget {
  const _TimerPill({required this.secondsLeft});

  final int secondsLeft;

  @override
  Widget build(BuildContext context) {
    final urgent = secondsLeft <= 8;
    return Container(
      width: 74,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: urgent
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        '$secondsLeft s',
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _QuizChip extends StatelessWidget {
  const _QuizChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.gold, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
