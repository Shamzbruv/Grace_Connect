export type BibleChapter = {
  book: string;
  chapter: number;
  key: string;
};

export type BibleVerse = {
  verse: number;
  text: string;
};

export type BibleChapterText = BibleChapter & {
  reference: string;
  verses: BibleVerse[];
  text: string;
};

const bibleBookChapterCounts: ReadonlyArray<readonly [string, number]> = [
  ["Genesis", 50],
  ["Exodus", 40],
  ["Leviticus", 27],
  ["Numbers", 36],
  ["Deuteronomy", 34],
  ["Joshua", 24],
  ["Judges", 21],
  ["Ruth", 4],
  ["1 Samuel", 31],
  ["2 Samuel", 24],
  ["1 Kings", 22],
  ["2 Kings", 25],
  ["1 Chronicles", 29],
  ["2 Chronicles", 36],
  ["Ezra", 10],
  ["Nehemiah", 13],
  ["Esther", 10],
  ["Job", 42],
  ["Psalms", 150],
  ["Proverbs", 31],
  ["Ecclesiastes", 12],
  ["Song of Solomon", 8],
  ["Isaiah", 66],
  ["Jeremiah", 52],
  ["Lamentations", 5],
  ["Ezekiel", 48],
  ["Daniel", 12],
  ["Hosea", 14],
  ["Joel", 3],
  ["Amos", 9],
  ["Obadiah", 1],
  ["Jonah", 4],
  ["Micah", 7],
  ["Nahum", 3],
  ["Habakkuk", 3],
  ["Zephaniah", 3],
  ["Haggai", 2],
  ["Zechariah", 14],
  ["Malachi", 4],
  ["Matthew", 28],
  ["Mark", 16],
  ["Luke", 24],
  ["John", 21],
  ["Acts", 28],
  ["Romans", 16],
  ["1 Corinthians", 16],
  ["2 Corinthians", 13],
  ["Galatians", 6],
  ["Ephesians", 6],
  ["Philippians", 4],
  ["Colossians", 4],
  ["1 Thessalonians", 5],
  ["2 Thessalonians", 3],
  ["1 Timothy", 6],
  ["2 Timothy", 4],
  ["Titus", 3],
  ["Philemon", 1],
  ["Hebrews", 13],
  ["James", 5],
  ["1 Peter", 5],
  ["2 Peter", 3],
  ["1 John", 5],
  ["2 John", 1],
  ["3 John", 1],
  ["Jude", 1],
  ["Revelation", 22],
];

function normalizedBookName(value: string): string {
  const normalized = value.toLowerCase().replace(/\s+/g, " ").trim();
  switch (normalized) {
    case "psalm":
    case "psalms":
      return "psalms";
    case "song of songs":
    case "canticles":
      return "song of solomon";
    case "revelations":
      return "revelation";
    default:
      return normalized;
  }
}

const canonicalBooks = new Map(
  bibleBookChapterCounts.map(([book, chapters]) => [
    normalizedBookName(book),
    { book, chapters },
  ]),
);

export function bibleChapterKey(book: string, chapter: number): string | null {
  const canonical = canonicalBooks.get(normalizedBookName(book));
  if (
    !canonical || !Number.isInteger(chapter) || chapter < 1 ||
    chapter > canonical.chapters
  ) {
    return null;
  }
  return `${normalizedBookName(canonical.book)} ${chapter}`;
}

export function bibleChapterFromKey(value: string): BibleChapter | null {
  const match = /^\s*([1-3]?\s*[A-Za-z]+(?:\s+[A-Za-z]+)*)\s+(\d{1,3})\s*$/
    .exec(value);
  if (!match) return null;
  const canonical = canonicalBooks.get(normalizedBookName(match[1]));
  const chapter = Number(match[2]);
  if (
    !canonical || !Number.isInteger(chapter) || chapter < 1 ||
    chapter > canonical.chapters
  ) {
    return null;
  }
  return {
    book: canonical.book,
    chapter,
    key: `${normalizedBookName(canonical.book)} ${chapter}`,
  };
}

export function bibleChapterFromReference(value: string): BibleChapter | null {
  const match = /^\s*([1-3]?\s*[A-Za-z]+(?:\s+[A-Za-z]+)*)\s+(\d{1,3}):\d{1,3}/
    .exec(value);
  if (!match) return null;
  return bibleChapterFromKey(`${match[1]} ${match[2]}`);
}

export const allBibleChapters: ReadonlyArray<BibleChapter> =
  bibleBookChapterCounts.flatMap(
    ([book, count]) =>
      Array.from({ length: count }, (_, index) => ({
        book,
        chapter: index + 1,
        key: `${normalizedBookName(book)} ${index + 1}`,
      })),
  );

export function shuffledBibleChapters(
  excludedKeys: ReadonlySet<string>,
): BibleChapter[] {
  const values = allBibleChapters.filter((chapter) =>
    !excludedKeys.has(chapter.key)
  );
  for (let index = values.length - 1; index > 0; index--) {
    const random = new Uint32Array(1);
    crypto.getRandomValues(random);
    const target = random[0] % (index + 1);
    [values[index], values[target]] = [values[target], values[index]];
  }
  return values;
}

export async function fetchBibleChapter(
  chapter: BibleChapter,
  timeoutMs = 12_000,
): Promise<BibleChapterText> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const query = encodeURIComponent(`${chapter.book} ${chapter.chapter}`);
    const response = await fetch(
      `https://bible-api.com/${query}?translation=web`,
      {
        headers: { Accept: "application/json" },
        signal: controller.signal,
      },
    );
    if (!response.ok) {
      throw new Error(
        `Bible chapter provider returned HTTP ${response.status}.`,
      );
    }
    const body = await response.json() as {
      reference?: unknown;
      verses?: Array<{ verse?: unknown; text?: unknown }>;
    };
    const verses = Array.isArray(body.verses)
      ? body.verses.map((verse) => ({
        verse: Number(verse.verse),
        text: String(verse.text ?? "").replace(/\s+/g, " ").trim(),
      })).filter((verse) =>
        Number.isInteger(verse.verse) && verse.verse > 0 &&
        verse.text.length > 0
      )
      : [];
    if (verses.length === 0) {
      throw new Error("Bible chapter provider returned no usable verses.");
    }
    return {
      ...chapter,
      reference: String(body.reference ?? `${chapter.book} ${chapter.chapter}`)
        .trim(),
      verses,
      text: verses.map((verse) => `${verse.verse}. ${verse.text}`).join("\n"),
    };
  } finally {
    clearTimeout(timeout);
  }
}

export function isChapterStudyDate(dateKey: string): boolean {
  const date = new Date(`${dateKey}T12:00:00.000Z`);
  const weekday = date.getUTCDay();
  return weekday === 1 || weekday === 3 || weekday === 6;
}
