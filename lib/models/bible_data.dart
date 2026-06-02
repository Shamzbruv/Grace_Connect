class BibleBook {
  final String name;
  final int chapters;
  final String testament; // 'Old' or 'New'
  final String
      category; // 'Law', 'History', 'Wisdom', 'Prophets', 'Gospels', 'Epistles'

  const BibleBook(this.name, this.chapters, this.testament, this.category);
}

class BibleData {
  static const List<BibleBook> allBooks = [
    // --- OLD TESTAMENT ---
    // Law (Pentateuch)
    BibleBook('Genesis', 50, 'Old', 'Law'),
    BibleBook('Exodus', 40, 'Old', 'Law'),
    BibleBook('Leviticus', 27, 'Old', 'Law'),
    BibleBook('Numbers', 36, 'Old', 'Law'),
    BibleBook('Deuteronomy', 34, 'Old', 'Law'),

    // History
    BibleBook('Joshua', 24, 'Old', 'History'),
    BibleBook('Judges', 21, 'Old', 'History'),
    BibleBook('Ruth', 4, 'Old', 'History'),
    BibleBook('1 Samuel', 31, 'Old', 'History'),
    BibleBook('2 Samuel', 24, 'Old', 'History'),
    BibleBook('1 Kings', 22, 'Old', 'History'),
    BibleBook('2 Kings', 25, 'Old', 'History'),
    BibleBook('1 Chronicles', 29, 'Old', 'History'),
    BibleBook('2 Chronicles', 36, 'Old', 'History'),
    BibleBook('Ezra', 10, 'Old', 'History'),
    BibleBook('Nehemiah', 13, 'Old', 'History'),
    BibleBook('Esther', 10, 'Old', 'History'),

    // Wisdom / Poetry
    BibleBook('Job', 42, 'Old', 'Wisdom'),
    BibleBook('Psalms', 150, 'Old', 'Wisdom'),
    BibleBook('Proverbs', 31, 'Old', 'Wisdom'),
    BibleBook('Ecclesiastes', 12, 'Old', 'Wisdom'),
    BibleBook('Song of Solomon', 8, 'Old', 'Wisdom'),

    // Major Prophets
    BibleBook('Isaiah', 66, 'Old', 'Prophets'),
    BibleBook('Jeremiah', 52, 'Old', 'Prophets'),
    BibleBook('Lamentations', 5, 'Old', 'Prophets'),
    BibleBook('Ezekiel', 48, 'Old', 'Prophets'),
    BibleBook('Daniel', 12, 'Old', 'Prophets'),

    // Minor Prophets
    BibleBook('Hosea', 14, 'Old', 'Prophets'),
    BibleBook('Joel', 3, 'Old', 'Prophets'),
    BibleBook('Amos', 9, 'Old', 'Prophets'),
    BibleBook('Obadiah', 1, 'Old', 'Prophets'),
    BibleBook('Jonah', 4, 'Old', 'Prophets'),
    BibleBook('Micah', 7, 'Old', 'Prophets'),
    BibleBook('Nahum', 3, 'Old', 'Prophets'),
    BibleBook('Habakkuk', 3, 'Old', 'Prophets'),
    BibleBook('Zephaniah', 3, 'Old', 'Prophets'),
    BibleBook('Haggai', 2, 'Old', 'Prophets'),
    BibleBook('Zechariah', 14, 'Old', 'Prophets'),
    BibleBook('Malachi', 4, 'Old', 'Prophets'),

    // --- NEW TESTAMENT ---
    // Gospels
    BibleBook('Matthew', 28, 'New', 'Gospels'),
    BibleBook('Mark', 16, 'New', 'Gospels'),
    BibleBook('Luke', 24, 'New', 'Gospels'),
    BibleBook('John', 21, 'New', 'Gospels'),

    // History
    BibleBook('Acts', 28, 'New', 'History'),

    // Paul\'s Epistles
    BibleBook('Romans', 16, 'New', 'Epistles'),
    BibleBook('1 Corinthians', 16, 'New', 'Epistles'),
    BibleBook('2 Corinthians', 13, 'New', 'Epistles'),
    BibleBook('Galatians', 6, 'New', 'Epistles'),
    BibleBook('Ephesians', 6, 'New', 'Epistles'),
    BibleBook('Philippians', 4, 'New', 'Epistles'),
    BibleBook('Colossians', 4, 'New', 'Epistles'),
    BibleBook('1 Thessalonians', 5, 'New', 'Epistles'),
    BibleBook('2 Thessalonians', 3, 'New', 'Epistles'),
    BibleBook('1 Timothy', 6, 'New', 'Epistles'),
    BibleBook('2 Timothy', 4, 'New', 'Epistles'),
    BibleBook('Titus', 3, 'New', 'Epistles'),
    BibleBook('Philemon', 1, 'New', 'Epistles'),

    // General Epistles
    BibleBook('Hebrews', 13, 'New', 'Epistles'),
    BibleBook('James', 5, 'New', 'Epistles'),
    BibleBook('1 Peter', 5, 'New', 'Epistles'),
    BibleBook('2 Peter', 3, 'New', 'Epistles'),
    BibleBook('1 John', 5, 'New', 'Epistles'),
    BibleBook('2 John', 1, 'New', 'Epistles'),
    BibleBook('3 John', 1, 'New', 'Epistles'),
    BibleBook('Jude', 1, 'New', 'Epistles'),

    // Prophecy
    BibleBook('Revelation', 22, 'New', 'Prophecy'),
  ];
}
