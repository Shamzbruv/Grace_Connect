import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/bible_data.dart';
import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/bible_streak_service.dart';
import '../../services/bible_service.dart';
import '../../services/direct_message_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_colors.dart';
import '../messages/message_thread_screen.dart';

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

class _BibleReaderScreenState extends State<BibleReaderScreen>
    with WidgetsBindingObserver {
  late Future<Map<String, dynamic>> _chapterFuture;
  Timer? _readingTimer;
  bool _streakRecorded = false;
  bool _streakRecording = false;
  bool _chapterReady = false;
  bool _readerInForeground = true;
  double _fontSize = 18;
  bool _showVerseNumbers = true;
  String _translation = 'web';
  Set<String> _highlightedVerses = {};
  final Set<int> _selectedVerses = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchChapter();
    _loadReaderSettings();
    unawaited(_loadStreakState());
    _startReadingTimer();
  }

  Future<void> _loadStreakState() async {
    final status = await BibleStreakService().currentStatus();
    if (!mounted) return;
    _streakRecorded = status.completedToday;
    if (_streakRecorded) _readingTimer?.cancel();
  }

  void _fetchChapter() {
    // API expects "John 3", implies we might need to handle spaces or standard names
    // BibleService handles the query formatting
    _chapterReady = false;
    _chapterFuture = BibleService()
        .getChapter(widget.book.name, widget.chapter)
        .then((chapter) {
      _chapterReady = true;
      return chapter;
    });
  }

  void _startReadingTimer() {
    _readingTimer?.cancel();
    _readingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted ||
          _streakRecorded ||
          _streakRecording ||
          !_chapterReady ||
          !_readerInForeground) {
        return;
      }
      _streakRecording = true;
      try {
        final streak = await BibleStreakService()
            .addActiveReadingTime(const Duration(seconds: 5));
        if (streak == null || !mounted) return;
        _streakRecorded = true;
        _readingTimer?.cancel();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Bible streak updated: $streak day${streak == 1 ? '' : 's'}'),
        ));
      } finally {
        _streakRecording = false;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _readerInForeground = state == AppLifecycleState.resumed;
  }

  Future<void> _loadReaderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final translation = prefs.getString('bible_translation') ?? 'web';
    if (!mounted) return;
    setState(() {
      _fontSize = prefs.getDouble('bible_font_size') ?? 18;
      _showVerseNumbers = prefs.getBool('bible_show_verse_numbers') ?? true;
      _translation = translation;
      _highlightedVerses =
          (prefs.getStringList(_highlightKey(translation)) ?? const []).toSet();
    });
    setState(_fetchChapter);
  }

  String _highlightKey(String translation) {
    return 'bible_highlights_${translation}_${widget.book.name}_${widget.chapter}';
  }

  Future<void> _setTranslation(String translation) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bible_translation', translation);
    if (!mounted) return;
    setState(() {
      _translation = translation;
      _selectedVerses.clear();
      _highlightedVerses =
          (prefs.getStringList(_highlightKey(translation)) ?? const []).toSet();
      _fetchChapter();
    });
  }

  Future<void> _saveHighlights() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _highlightKey(_translation),
      _highlightedVerses.toList()..sort(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _readingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.book.name} ${widget.chapter}',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
            Text(
              BibleService.translationName(_translation),
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Bible version',
            icon: const Icon(Icons.translate_outlined),
            initialValue: _translation,
            onSelected: _setTranslation,
            itemBuilder: (context) => [
              for (final entry in BibleService.translations.entries)
                PopupMenuItem(
                  value: entry.key,
                  child: Text(entry.value),
                ),
            ],
          ),
        ],
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
          final translationName = data['translation_name']?.toString() ??
              BibleService.translationName(_translation);

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

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    _selectedVerses.isNotEmpty ? 8 : 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: verses.length,
                        itemBuilder: (context, index) {
                          final verse = verses[index];
                          final verseMap = verse is Map ? verse : const {};
                          final verseNumber =
                              (verseMap['verse'] ?? index + 1).toString();
                          final verseText = (verseMap['text'] ?? '').toString();
                          final textColor =
                              Theme.of(context).textTheme.bodyLarge?.color;
                          final verseInt =
                              int.tryParse(verseNumber) ?? index + 1;
                          final verseKey = verseInt.toString();
                          final isHighlighted =
                              _highlightedVerses.contains(verseKey);
                          final isSelected = _selectedVerses.contains(verseInt);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 18.0),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedVerses.remove(verseInt);
                                  } else {
                                    _selectedVerses.add(verseInt);
                                  }
                                });
                              },
                              onLongPress: () async {
                                setState(() {
                                  if (isHighlighted) {
                                    _highlightedVerses.remove(verseKey);
                                  } else {
                                    _highlightedVerses.add(verseKey);
                                  }
                                  _selectedVerses.add(verseInt);
                                });
                                await _saveHighlights();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.secondary
                                          .withValues(alpha: 0.18)
                                      : isHighlighted
                                          ? AppColors.gold
                                              .withValues(alpha: 0.22)
                                          : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: isSelected
                                      ? Border.all(color: AppColors.secondary)
                                      : null,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_showVerseNumbers) ...[
                                      Container(
                                        width: 30,
                                        height: 30,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: AppColors.secondary
                                              .withValues(alpha: 0.16),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: AppColors.secondary
                                                .withValues(alpha: 0.6),
                                          ),
                                        ),
                                        child: Text(
                                          verseNumber,
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.goldHighlight,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                    ],
                                    Expanded(
                                      child: Text(
                                        verseText,
                                        style: GoogleFonts.lora(
                                          fontSize: _fontSize,
                                          height: 1.62,
                                          color: textColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 18),
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
                                      chapter: widget.chapter - 1,
                                    ),
                                  ),
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
                                      chapter: widget.chapter + 1,
                                    ),
                                  ),
                                );
                              },
                            )
                          else
                            const SizedBox(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_selectedVerses.isNotEmpty)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                    child: _SelectedVerseActions(
                      selectedCount: _selectedVerses.length,
                      onCopy: () => _copySelectedVerses(
                        verses,
                        reference.toString(),
                        translationName,
                      ),
                      onShare: () => _shareSelectedVerses(
                        verses,
                        reference.toString(),
                        translationName,
                      ),
                      onHighlight: () => _toggleHighlightsForSelection(),
                      onSend: () => _sendSelectedVerses(
                        verses,
                        reference.toString(),
                        translationName,
                      ),
                      onClear: () => setState(_selectedVerses.clear),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _selectedPassageText(
    List<dynamic> verses,
    String reference,
    String translationName,
  ) {
    final selected = _selectedVerses.toList()..sort();
    final lines = <String>[];
    for (final verseNumber in selected) {
      final verse = verses.firstWhere(
        (item) {
          if (item is! Map) return false;
          return (int.tryParse((item['verse'] ?? '').toString()) ?? -1) ==
              verseNumber;
        },
        orElse: () => null,
      );
      if (verse is! Map) continue;
      final text = (verse['text'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      lines.add('$reference:$verseNumber $text');
    }

    if (lines.isEmpty) return '';
    return '${lines.join('\n')}\n\n$translationName';
  }

  Future<void> _copySelectedVerses(
    List<dynamic> verses,
    String reference,
    String translationName,
  ) async {
    final text = _selectedPassageText(verses, reference, translationName);
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Verse copied.')),
    );
  }

  Future<void> _shareSelectedVerses(
    List<dynamic> verses,
    String reference,
    String translationName,
  ) async {
    final text = _selectedPassageText(verses, reference, translationName);
    if (text.isEmpty) return;
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _toggleHighlightsForSelection() async {
    setState(() {
      final selectedKeys = _selectedVerses.map((verse) => verse.toString());
      final allHighlighted =
          selectedKeys.every((key) => _highlightedVerses.contains(key));
      if (allHighlighted) {
        _highlightedVerses.removeAll(selectedKeys);
      } else {
        _highlightedVerses.addAll(selectedKeys);
      }
    });
    await _saveHighlights();
  }

  Future<void> _sendSelectedVerses(
    List<dynamic> verses,
    String reference,
    String translationName,
  ) async {
    final currentUser = context.read<UserRoleProvider>().userProfile;
    final text = _selectedPassageText(verses, reference, translationName);
    if (currentUser == null || text.isEmpty) return;

    final searchController = TextEditingController();
    var results = const <UserProfile>[];
    var isSearching = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> search(String value) async {
              final query = value.trim();
              if (query.length < 2) {
                setSheetState(() => results = const <UserProfile>[]);
                return;
              }
              setSheetState(() => isSearching = true);
              try {
                final people = await UserService().searchPeople(query);
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  results = people
                      .where((person) =>
                          person.uid != currentUser.uid && person.allowMessages)
                      .toList();
                  isSearching = false;
                });
              } catch (_) {
                if (sheetContext.mounted) {
                  setSheetState(() => isSearching = false);
                }
              }
            }

            Future<void> sendTo(UserProfile recipient) async {
              try {
                final conversation =
                    await DirectMessageService().getOrCreateConversation(
                  currentUser: currentUser,
                  otherUser: recipient,
                );
                await DirectMessageService().sendMessage(
                  conversationId: conversation.id,
                  text: text,
                  recipientUserId: recipient.uid,
                );
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Verse sent to ${recipient.fullName.isEmpty ? recipient.email : recipient.fullName}.',
                    ),
                  ),
                );
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MessageThreadScreen(
                      conversation: conversation,
                      otherUser: recipient,
                    ),
                  ),
                );
              } catch (error) {
                if (!sheetContext.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not send verse: $error')),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Send Verse',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search people',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: search,
                  ),
                  if (isSearching) const LinearProgressIndicator(),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final person = results[index];
                        final displayName = person.fullName.isNotEmpty
                            ? person.fullName
                            : person.email;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: person.photoUrl.isNotEmpty
                                ? NetworkImage(person.photoUrl)
                                : null,
                            child: person.photoUrl.isEmpty
                                ? Text(displayName.characters.first)
                                : null,
                          ),
                          title: Text(displayName),
                          subtitle: Text(
                            person.placeName.isEmpty
                                ? person.email
                                : '${person.placeName} • ${person.email}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => sendTo(person),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    searchController.dispose();
  }
}

class _SelectedVerseActions extends StatelessWidget {
  const _SelectedVerseActions({
    required this.selectedCount,
    required this.onCopy,
    required this.onShare,
    required this.onHighlight,
    required this.onSend,
    required this.onClear,
  });

  final int selectedCount;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onHighlight;
  final VoidCallback onSend;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$selectedCount selected',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy_outlined),
              onPressed: onCopy,
            ),
            IconButton(
              tooltip: 'Share outside app',
              icon: const Icon(Icons.ios_share_outlined),
              onPressed: onShare,
            ),
            IconButton(
              tooltip: 'Highlight',
              icon: const Icon(Icons.border_color_outlined),
              onPressed: onHighlight,
            ),
            IconButton(
              tooltip: 'Send in app',
              icon: const Icon(Icons.send_outlined),
              onPressed: onSend,
            ),
            IconButton(
              tooltip: 'Clear selection',
              icon: const Icon(Icons.close),
              onPressed: onClear,
            ),
          ],
        ),
      ),
    );
  }
}
