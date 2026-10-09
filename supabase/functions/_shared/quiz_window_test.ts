import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  isQuizPlayable,
  quizClosesAt,
  quizDateForPlay,
} from "./quiz_window.ts";

Deno.test("the same quiz survives midnight until exactly 6 AM Jamaica", () => {
  for (
    const time of [
      "2026-10-09T04:59:59.999Z",
      "2026-10-09T05:00:00Z",
      "2026-10-09T10:59:59.999Z",
    ]
  ) {
    assertEquals(quizDateForPlay(new Date(time)), "2026-10-08");
  }
  assertEquals(quizDateForPlay(new Date("2026-10-09T11:00:00Z")), "2026-10-09");
});
Deno.test("close times advance across months, leap days and year boundaries", () => {
  for (
    const [date, next] of [["2026-10-31", "2026-11-01"], [
      "2026-12-31",
      "2027-01-01",
    ], ["2024-02-29", "2024-03-01"]]
  ) {
    assertEquals(quizClosesAt(date).toISOString(), `${next}T11:00:00.000Z`);
    assertEquals(quizDateForPlay(new Date(`${next}T10:59:59Z`)), date);
  }
  assertThrows(() => quizClosesAt("2026-02-30"));
});
Deno.test("opening is inclusive, closing exclusive, and unpublished sets stay hidden", () => {
  const quiz = {
    status: "published",
    available_at: "2026-10-08T12:00:00Z",
    expires_at: "2026-10-09T11:00:00Z",
  };
  assertEquals(isQuizPlayable(quiz, new Date("2026-10-08T11:59:59Z")), false);
  assertEquals(isQuizPlayable(quiz, new Date(quiz.available_at)), true);
  assertEquals(isQuizPlayable(quiz, new Date("2026-10-09T10:59:59Z")), true);
  assertEquals(isQuizPlayable(quiz, new Date(quiz.expires_at)), false);
  assertEquals(
    isQuizPlayable(
      { ...quiz, status: "scheduled" },
      new Date(quiz.available_at),
    ),
    false,
  );
  assertEquals(isQuizPlayable(null), false);
});
