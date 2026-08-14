import {
  canonicalQuizAnswer,
  canonicalQuizFactKeys,
  canonicalScriptureChapter,
  questionsOverlapByFact,
  rotatingQuizFactExclusions,
} from "./quiz_uniqueness.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

Deno.test("canonical quiz keys ignore wording-level answer differences", () => {
  assert(
    canonicalQuizAnswer("A sling and stone") === "sling stone",
    "first answer key",
  );
  assert(
    canonicalQuizAnswer("The stone from a sling") === "sling stone",
    "second answer key",
  );
  assert(
    canonicalScriptureChapter("Psalm 119:105") === "psalms 119",
    "Psalm alias",
  );

  const first = {
    scripture_references: ["1 Samuel 17:49"],
    correct_answer: "A sling and stone",
  };
  const paraphrase = {
    scripture_references: ["1 Samuel 17:48-50"],
    correct_answer: "The stone from a sling",
  };
  assert(
    questionsOverlapByFact(first, paraphrase),
    "paraphrase should collide",
  );
  assert(
    canonicalQuizFactKeys(first).includes("1 samuel 17::sling stone"),
    "stable fact key",
  );
});

Deno.test("different Scripture facts do not collide", () => {
  const first = {
    scripture_references: ["John 11:38-44"],
    correct_answer: "Lazarus",
  };
  const second = {
    scripture_references: ["Acts 9:36-42"],
    correct_answer: "Tabitha",
  };
  assert(
    !questionsOverlapByFact(first, second),
    "different facts should remain available",
  );
});

Deno.test("distinctive and narrow Jesus aliases collide without broad title aliases", () => {
  const lazarus = {
    scripture_references: ["John 11:38-44"],
    correct_answer: "Lazarus",
  };
  const lazarusOfBethany = {
    scripture_references: ["John 11:39-44"],
    correct_answer: "Lazarus of Bethany",
  };
  assert(
    questionsOverlapByFact(lazarus, lazarusOfBethany),
    "distinctive short and long aliases should collide",
  );

  const jesus = {
    scripture_references: ["John 6:1-14"],
    correct_answer: "Jesus",
  };
  const jesusChrist = {
    scripture_references: ["John 6:15"],
    correct_answer: "Jesus Christ",
  };
  assert(
    questionsOverlapByFact(jesus, jesusChrist),
    "Jesus and Jesus Christ must identify the same person",
  );
  const lordJesus = {
    scripture_references: ["John 6:16"],
    correct_answer: "Lord Jesus",
  };
  assert(
    questionsOverlapByFact(jesus, lordJesus),
    "Jesus and Lord Jesus must identify the same person",
  );
  const genericLord = {
    scripture_references: ["John 6:17"],
    correct_answer: "Lord",
  };
  assert(
    !questionsOverlapByFact(jesus, genericLord),
    "a generic title alone must not receive a person alias",
  );
});

Deno.test("large prompt exclusions rotate between variation batches", () => {
  const blocked = new Set(
    Array.from({ length: 360 }, (_, index) => `fact-${index}`),
  );
  const first = rotatingQuizFactExclusions(blocked, 0);
  const second = rotatingQuizFactExclusions(blocked, 1);
  const third = rotatingQuizFactExclusions(blocked, 2);
  assert(first.length === 120, "first window size");
  assert(second.length === 120, "second window size");
  assert(third.length === 120, "third window size");
  assert(first.every((key) => !second.includes(key)), "first/second rotate");
  assert(second.every((key) => !third.includes(key)), "second/third rotate");
  assert(
    new Set([...first, ...second, ...third]).size === 360,
    "three batches cover all retained keys",
  );
});
