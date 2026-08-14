import type { QuizQuestion } from "./quiz_bank.ts";

const answerStopWords = new Set([
  "a",
  "an",
  "and",
  "at",
  "by",
  "for",
  "from",
  "in",
  "of",
  "on",
  "the",
  "to",
  "with",
]);

// These broad titles/nouns do not identify a person or object by themselves.
// We keep them in the full answer key, but never use them as a partial alias.
const nonDistinctiveAnswerTokens = new Set([
  "apostle",
  "brother",
  "christ",
  "city",
  "daughter",
  "disciple",
  "disciples",
  "god",
  "israel",
  "jesus",
  "king",
  "lord",
  "man",
  "people",
  "priest",
  "prophet",
  "queen",
  "sister",
  "son",
  "woman",
]);

// Keep this alias intentionally narrow. Broad title-token aliases would make
// unrelated people or events in the same chapter collide, while these exact
// canonical forms all name the same person.
const jesusAnswerAliases = new Set([
  "christ jesus",
  "christ jesus lord",
  "jesus",
  "jesus lord",
]);

function canonicalBookName(value: string): string {
  const book = value.toLowerCase().replace(/\s+/g, " ").trim();
  switch (book) {
    case "psalm":
    case "psalms":
      return "psalms";
    case "song of songs":
    case "canticles":
      return "song of solomon";
    case "revelations":
      return "revelation";
    default:
      return book;
  }
}

export function canonicalQuizAnswer(value: string): string {
  const normalized = value.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
  const meaningful = normalized
    .split(/\s+/)
    .filter((token) => token.length > 0 && !answerStopWords.has(token));
  const tokens = meaningful.length > 0
    ? meaningful
    : normalized.split(/\s+/).filter(Boolean);
  return Array.from(new Set(tokens)).sort().join(" ");
}

export function canonicalScriptureChapter(reference: string): string | null {
  const normalized = reference.toLowerCase().replace(/\s+/g, " ").trim();
  const match = normalized.match(
    /^([1-3]?\s*[a-z]+(?:\s+[a-z]+)*)\s+(\d{1,3}):\d{1,3}/,
  );
  if (!match) return null;
  return `${canonicalBookName(match[1])} ${Number(match[2])}`;
}

/// A fact has one collision key per referenced Scripture chapter. Combining
/// the canonical passage anchor with normalized answer tokens catches a
/// reworded question (and shifted verse range) without depending on its prose.
export function canonicalQuizFactKeys(
  question: Pick<QuizQuestion, "scripture_references" | "correct_answer">,
): string[] {
  const answer = canonicalQuizAnswer(question.correct_answer);
  if (!answer) return [];
  const answerTokens = answer.split(" ").filter(Boolean);
  return Array.from(
    new Set(
      question.scripture_references
        .map(canonicalScriptureChapter)
        .filter((reference): reference is string => reference != null)
        .flatMap((reference) => {
          const keys = [`${reference}::${answer}`];
          if (jesusAnswerAliases.has(answer)) {
            keys.push(`${reference}::person:jesus`);
          }
          if (answerTokens.length > 1) {
            for (const token of answerTokens) {
              if (!nonDistinctiveAnswerTokens.has(token)) {
                // A longer alias such as "Lazarus of Bethany" must collide
                // with the shorter canonical answer "Lazarus".
                keys.push(`${reference}::${token}`);
              }
            }
          }
          return keys;
        }),
    ),
  ).sort();
}

/// Returns a deterministic rotating prompt window. The database guard always
/// checks the complete retained history; this window makes successive AI
/// variation batches see different exclusions without creating huge prompts.
export function rotatingQuizFactExclusions(
  blockedFactKeys: Set<string>,
  variationBatch: number,
  limit = 120,
): string[] {
  if (limit <= 0 || blockedFactKeys.size === 0) return [];
  const keys = Array.from(blockedFactKeys).sort();
  const count = Math.min(limit, keys.length);
  const batch = Math.max(0, Math.trunc(variationBatch));
  const start = (batch * limit) % keys.length;
  return Array.from(
    { length: count },
    (_, index) => keys[(start + index) % keys.length],
  );
}

export function questionsOverlapByFact(
  left: Pick<QuizQuestion, "scripture_references" | "correct_answer">,
  right: Pick<QuizQuestion, "scripture_references" | "correct_answer">,
): boolean {
  const leftKeys = new Set(canonicalQuizFactKeys(left));
  return canonicalQuizFactKeys(right).some((key) => leftKeys.has(key));
}
