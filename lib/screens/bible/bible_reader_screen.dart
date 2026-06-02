import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/bible_data.dart';
import '../../services/bible_streak_service.dart';
import '../../services/bible_service.dart';
import '../../theme/app_colors.dart';

class BibleReaderScreen extends StatefulWidget {
  final BibleBook book;
  final int chapter;

  const BibleReaderScreen({
    super.key,
    required this.book,
    required this.chapter,
  });

  @override
  State<BibleReaderScreen> createState() => _BibleReaderScreenState();
}

class _BibleReaderScreenState extends State<BibleReaderScreen> {
  late Future<Map<String, dynamic>> _chapterFuture;
  Timer? _readingTimer;
  bool _streakRecorded = false;
  double _fontSize = 18;
  bool _showVerseNumbers = true;

  @override
  void initState() {
    super.initState();
    _fetchChapter();
    _loadReaderSettings();
    _startReadingTimer();
  }

  void _fetchChapter() {
    // API expects "John 3", implies we might need to handle spaces or standard names
    // BibleService handles the query formatting
    _chapterFuture =
        BibleService().getChapter(widget.book.name, widget.chapter);
  }

  void _startReadingTimer() {
    _readingTimer?.cancel();
    _readingTimer = Timer(const Duration(minutes: 5), () async {
      if (!mounted || _streakRecorded) return;

      final streak = await BibleStreakService().recordFiveMinuteRead();
      _streakRecorded = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Bible streak updated: $streak day${streak == 1 ? '' : 's'}'),
        ),
      );
    });
  }

  Future<void> _loadReaderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _fontSize = prefs.getDouble('bible_font_size') ?? 18;
      _showVerseNumbers = prefs.getBool('bible_show_verse_numbers') ?? true;
    });
  }

  @override
  void dispose() {
    _readingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.book.name} ${widget.chapter}',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _chapterFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading chapter',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _fetchChapter();
                        });
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: Text('No content found.'));
          }

          final data = snapshot.data!;
          final verses = data['verses'] is List
              ? List<dynamic>.from(data['verses'] as List)
              : <dynamic>[];
          final reference =
              data['reference'] ?? '${widget.book.name} ${widget.chapter}';

          if (verses.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No verses were returned for $reference. Please try another translation or chapter.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    reference,
                    style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.titleLarge?.color),
                  ),
                ),
                const SizedBox(height: 24),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: verses.length,
                  itemBuilder: (context, index) {
                    final verse = verses[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: _fontSize,
                            height: 1.6,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                          children: [
                            if (_showVerseNumbers)
                              TextSpan(
                                text: '${verse['verse']} ',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                  fontSize:
                                      (_fontSize - 4).clamp(10, 18).toDouble(),
                                ),
                              ),
                            TextSpan(
                              text: verse['text'],
                              style: GoogleFonts
                                  .lora(), // Serif font good for reading
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 40),
                // Simple Navigation Controls (Optional but nice)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (widget.chapter > 1)
                      TextButton.icon(
                        icon: const Icon(Icons.arrow_back),
                        label: const Text("Prev Chapter"),
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (_) => BibleReaderScreen(
                                    book: widget.book,
                                    chapter: widget.chapter - 1)),
                          );
                        },
                      )
                    else
                      const SizedBox(),
                    if (widget.chapter < widget.book.chapters)
                      TextButton.icon(
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text("Next Chapter"),
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (_) => BibleReaderScreen(
                                    book: widget.book,
                                    chapter: widget.chapter + 1)),
                          );
                        },
                      )
                    else
                      const SizedBox(),
                  ],
                )
              ],
            ),
          );
        },
      ),
    );
  }
}
