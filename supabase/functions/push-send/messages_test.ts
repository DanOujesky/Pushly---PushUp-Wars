import nodeAssert from "node:assert/strict";
import { render } from "./messages.ts";

const assertEquals = (a: unknown, b: unknown, msg?: string) => nodeAssert.deepStrictEqual(a, b, msg);
const assertStringIncludes = (s: string, part: string) => nodeAssert.ok(s.includes(part), `${s} ⊉ ${part}`);

Deno.test("battle invites, clan requests and mentions have copy (they were silently dropped before)", () => {
  for (const type of ["battle_invite", "clan_join_request", "clan_mention"]) {
    const r = render(type, { username: "tom", inviteId: "x", clanId: "c" });
    assertEquals(r !== null, true, type);
  }
});

Deno.test("rally copy follows the score", () => {
  assertStringIncludes(render("clan_rally", { username: "ana", gap: -120, warId: "w" })?.body ?? "", "120 behind");
  assertStringIncludes(render("clan_rally", { username: "ana", gap: 40, warId: "w" })?.body ?? "", "lead by 40");
  assertEquals(render("clan_rally", { username: "ana", gap: 0, warId: "w" })?.link, "pushly://clan/war/w");
});
