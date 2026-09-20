import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { displayFirstName, profileDisplayName } from "./grace.ts";

Deno.test("a first name is taken from a full name", () => {
  assertEquals(displayFirstName("Keisha Verona Willaims Hillary"), "Keisha");
  assertEquals(displayFirstName("Marcus Brown"), "Marcus");
  assertEquals(displayFirstName("  Marcus  "), "Marcus");
  assertEquals(displayFirstName("Marcus"), "Marcus");
});

Deno.test("a missing name falls back rather than showing an empty row", () => {
  assertEquals(displayFirstName(""), "Member");
  assertEquals(displayFirstName("   "), "Member");
  assertEquals(displayFirstName(null as unknown as string), "Member");
});

Deno.test("profileDisplayName prefers fullName, then displayName", () => {
  assertEquals(profileDisplayName({ fullName: "Shamar Baker" }), "Shamar Baker");
  assertEquals(profileDisplayName({ displayName: "Shamar" }), "Shamar");
  assertEquals(profileDisplayName({}), "Member");
});

Deno.test("a profile row keyed only by uid still resolves a first name", () => {
  // The exact shape the leaderboard lookup was dropping on the floor.
  const row = { uid: "abc-123", fullName: "Shamar Baker" };
  assertEquals(displayFirstName(profileDisplayName(row)), "Shamar");
});
