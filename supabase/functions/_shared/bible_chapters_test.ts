import {
  allBibleChapters,
  bibleChapterFromKey,
  bibleChapterFromReference,
  bibleChapterKey,
  isChapterStudyDate,
  shuffledBibleChapters,
} from "./bible_chapters.ts";

Deno.test("Bible chapter catalog contains every canonical chapter once", () => {
  if (allBibleChapters.length !== 1189) {
    throw new Error(`Expected 1189 chapters, got ${allBibleChapters.length}.`);
  }
  if (new Set(allBibleChapters.map((chapter) => chapter.key)).size !== 1189) {
    throw new Error("Bible chapter keys are not unique.");
  }
});

Deno.test("chapter parsing canonicalizes supported aliases and validates ranges", () => {
  if (bibleChapterKey("Psalm", 119) !== "psalms 119") {
    throw new Error("Psalm alias failed.");
  }
  if (
    bibleChapterFromReference("Song of Songs 2:4-7")?.key !==
      "song of solomon 2"
  ) {
    throw new Error("Song of Songs alias failed.");
  }
  if (bibleChapterFromKey("Revelations 23") !== null) {
    throw new Error("Invalid chapter accepted.");
  }
});

Deno.test("study dates are Monday Wednesday and Saturday in Jamaica date space", () => {
  if (!isChapterStudyDate("2026-08-15")) {
    throw new Error("Saturday was not a study day.");
  }
  if (!isChapterStudyDate("2026-08-17")) {
    throw new Error("Monday was not a study day.");
  }
  if (!isChapterStudyDate("2026-08-19")) {
    throw new Error("Wednesday was not a study day.");
  }
  if (isChapterStudyDate("2026-08-18")) {
    throw new Error("Tuesday was marked as a study day.");
  }
});

Deno.test("shuffle excludes every retained chapter without changing the catalog", () => {
  const result = shuffledBibleChapters(new Set(["genesis 1", "john 3"]));
  if (result.length !== 1187) {
    throw new Error("Excluded chapter count is wrong.");
  }
  if (
    result.some((chapter) =>
      chapter.key === "genesis 1" || chapter.key === "john 3"
    )
  ) {
    throw new Error("An excluded chapter returned.");
  }
});
