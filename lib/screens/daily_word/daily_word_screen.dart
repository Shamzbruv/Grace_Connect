import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/daily_motivation.dart';
import '../../services/daily_motivation_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/app_loader.dart';

class DailyWordScreen extends StatefulWidget {
  const DailyWordScreen({super.key, this.motivationId});

  final String? motivationId;

  @override
  State<DailyWordScreen> createState() => _DailyWordScreenState();
}

class _DailyWordScreenState extends State<DailyWordScreen> {
  final _service = DailyMotivationService();
  final _dailyWordShareKey = GlobalKey();
  late Future<_DailyWordData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DailyWordData> _load({bool forceRegenerate = false}) async {
    final selected = widget.motivationId?.isNotEmpty == true
        ? await _service.fetchById(widget.motivationId!)
        : await _service.fetchToday(
            generateIfMissing: true,
            forceRegenerate: forceRegenerate,
          );
    final recent = await _service.fetchRecent();
    return _DailyWordData(selected: selected, recent: recent);
  }

  void _refresh() {
    setState(() {
      _future = _load(forceRegenerate: widget.motivationId?.isNotEmpty != true);
    });
  }

  Future<void> _shareDailyWordImage(DailyMotivation motivation) async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _dailyWordShareKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Daily Word card is not ready yet.');
      }

      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData?.buffer.asUint8List();
      if (pngBytes == null || pngBytes.isEmpty) {
        throw Exception('Could not prepare Daily Word image.');
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              pngBytes,
              mimeType: 'image/png',
              name:
                  'grace_daily_word_${DateFormat('yyyyMMdd').format(motivation.publishDate.toLocal())}.png',
            ),
          ],
          text: 'Grace Connect Daily Word • ${motivation.scriptureReference}',
          subject: motivation.title,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        'Could not share Daily Word image: $error',
        type: AppFeedbackType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Daily Word',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_DailyWordData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoader();
          }
          if (snapshot.hasError) {
            return _EmptyDailyWord(
              title: 'Daily Word unavailable',
              message: 'Please check again soon.',
              onRetry: _refresh,
            );
          }
          final data = snapshot.data;
          if (data?.selected == null) {
            return _EmptyDailyWord(
              title: 'No Daily Word yet',
              message:
                  'Today’s encouragement will appear here after it is published.',
              onRetry: _refresh,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
              children: [
                RepaintBoundary(
                  key: _dailyWordShareKey,
                  child: _DailyWordHero(motivation: data!.selected!),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _shareDailyWordImage(data.selected!),
                  icon: const Icon(Icons.ios_share_outlined),
                  label: const Text('Share Daily Word'),
                ),
                const SizedBox(height: 22),
                Text(
                  'Recent Daily Words',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                ...data.recent.map(
                  (motivation) => _RecentDailyWordTile(
                    motivation: motivation,
                    selected: motivation.id == data.selected!.id,
                    onTap: () {
                      setState(() {
                        _future = Future.value(
                          _DailyWordData(
                            selected: motivation,
                            recent: data.recent,
                          ),
                        );
                      });
                      AppFeedback.show(
                        context,
                        DateFormat.yMMMMd().format(motivation.publishDate),
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
}

class _DailyWordHero extends StatelessWidget {
  const _DailyWordHero({required this.motivation});

  final DailyMotivation motivation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient:
            isDark ? AppColors.darkSurfaceGradient : AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.16),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child:
                    const Icon(Icons.wb_sunny_outlined, color: AppColors.gold),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  DateFormat.yMMMMEEEEd().format(motivation.publishDate),
                  style: GoogleFonts.outfit(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            motivation.title,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            motivation.message,
            style: GoogleFonts.outfit(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 18,
              height: 1.42,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.menu_book_outlined,
                    color: AppColors.gold, size: 18),
                const SizedBox(width: 8),
                Text(
                  motivation.scriptureReference,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentDailyWordTile extends StatelessWidget {
  const _RecentDailyWordTile({
    required this.motivation,
    required this.selected,
    required this.onTap,
  });

  final DailyMotivation motivation;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.14)
            : theme.cardTheme.color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.4)
              : Colors.transparent,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: AppColors.gold.withValues(alpha: 0.18),
          foregroundColor: AppColors.gold,
          child: const Icon(Icons.auto_awesome, size: 18),
        ),
        title: Text(
          motivation.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${DateFormat.MMMd().format(motivation.publishDate)} • ${motivation.scriptureReference}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _EmptyDailyWord extends StatelessWidget {
  const _EmptyDailyWord({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

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
              Icons.wb_sunny_outlined,
              size: 54,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyWordData {
  const _DailyWordData({
    required this.selected,
    required this.recent,
  });

  final DailyMotivation? selected;
  final List<DailyMotivation> recent;
}
