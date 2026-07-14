class StudyReadingAssignment {
  final String id;
  final String planId;
  final int sequenceNumber;
  final DateTime? assignedDate;
  final String book;
  final int? chapterStart;
  final int? chapterEnd;
  final int? verseStart;
  final int? verseEnd;
  final String title;
  final String reflectionPrompt;
  final String discussionQuestion;

  const StudyReadingAssignment({
    required this.id,
    required this.planId,
    this.sequenceNumber = 1,
    this.assignedDate,
    this.book = '',
    this.chapterStart,
    this.chapterEnd,
    this.verseStart,
    this.verseEnd,
    this.title = '',
    this.reflectionPrompt = '',
    this.discussionQuestion = '',
  });

  factory StudyReadingAssignment.fromMap(Map<String, dynamic> data) {
    return StudyReadingAssignment(
      id: _string(data['id']),
      planId: _string(data['plan_id'] ?? data['planId']),
      sequenceNumber: _int(data['sequence_number']) ?? 1,
      assignedDate: _parseDate(data['assigned_date']),
      book: _string(data['book']),
      chapterStart: _int(data['chapter_start']),
      chapterEnd: _int(data['chapter_end']),
      verseStart: _int(data['verse_start']),
      verseEnd: _int(data['verse_end']),
      title: _string(data['title']),
      reflectionPrompt: _string(data['reflection_prompt']),
      discussionQuestion: _string(data['discussion_question']),
    );
  }

  String get passageLabel {
    if (book.isEmpty) return title;
    if (chapterStart == null) return book;
    final chapterText = chapterEnd != null && chapterEnd != chapterStart
        ? '$chapterStart-$chapterEnd'
        : '$chapterStart';
    return '$book $chapterText';
  }

  static String _string(dynamic value) => value?.toString() ?? '';

  static int? _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.trim().isNotEmpty) return int.tryParse(value);
    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
