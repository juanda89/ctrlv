import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { type AccessLimits, type AccessSnapshot, decideAccess, parseAccessSnapshot } from "./access.ts";

const limits: AccessLimits = {
  trialDays: 14,
  trialDailyLimit: 50,
  trialMaxCharacters: 3000,
  paidBurstLimit: 80,
  paidDailyLimit: 1500,
  paidDailyCharacterLimit: 1_200_000,
  paidMaxCharacters: 12000,
};
const now = Date.UTC(2026, 8, 19, 20, 0, 0);
const day = 24 * 60 * 60 * 1000;

function trial(overrides: Partial<AccessSnapshot> = {}): AccessSnapshot {
  return { first_seen_ms: now - 3 * day, plan: "trial", account_hash: null, plan_name: null, identity_24h: 0, account_10m: 0, account_24h: 0, account_chars_24h: 0, ...overrides };
}
function paid(overrides: Partial<AccessSnapshot> = {}): AccessSnapshot {
  return { ...trial(), plan: "active", account_hash: "abc", plan_name: "Pro", ...overrides };
}
const enforce = { enforceLimits: true, now };

Deno.test("fresh trial passes with the remaining days", () => {
  const decision = decideAccess(trial(), 100, limits, enforce);
  assertEquals(decision, { ok: true, plan: { plan: "trial", accountHash: null, planName: null, trialDaysRemaining: 11 } });
});

Deno.test("trial older than trialDays is 403 even on passthrough", () => {
  const snapshot = trial({ first_seen_ms: now - 14 * day });
  assertEquals(decideAccess(snapshot, 100, limits, enforce).ok, false);
  const passthrough = decideAccess(snapshot, 100, limits, { enforceLimits: false, now });
  assertEquals(passthrough, { ok: false, rejection: { status: 403, body: { error: "Trial expired" } } });
});

Deno.test("trial text over the character cap is rejected before the daily count", () => {
  const decision = decideAccess(trial({ identity_24h: 50 }), 3001, limits, enforce);
  assertEquals(decision, { ok: false, rejection: { status: 429, body: { error: "Trial text exceeds 3000 characters." } } });
});

Deno.test("trial daily limit carries seconds until midnight UTC", () => {
  const decision = decideAccess(trial({ identity_24h: 50 }), 100, limits, enforce);
  assertEquals(decision.ok, false);
  if (!decision.ok) {
    assertEquals(decision.rejection.body.error, "Trial daily limit reached.");
    assertEquals(decision.rejection.body.retry_after_seconds, 4 * 60 * 60);
  }
});

Deno.test("passthrough skips quotas but keeps the plan", () => {
  const decision = decideAccess(trial({ identity_24h: 50 }), 100, limits, { enforceLimits: false, now });
  assertEquals(decision.ok, true);
});

Deno.test("paid account passes and exposes its hash", () => {
  const decision = decideAccess(paid({ account_10m: 79, account_24h: 1499 }), 5000, limits, enforce);
  assertEquals(decision, { ok: true, plan: { plan: "active", accountHash: "abc", planName: "Pro", trialDaysRemaining: 11 } });
});

Deno.test("paid limits: characters, burst, daily count, daily characters", () => {
  const tooLong = decideAccess(paid(), 12001, limits, enforce);
  assertEquals(tooLong.ok ? null : tooLong.rejection.body.error, "Request exceeds 12000 characters.");
  const burst = decideAccess(paid({ account_10m: 80 }), 100, limits, enforce);
  assertEquals(burst.ok ? null : burst.rejection.body, { error: "Too many requests in a short period.", retry_after_seconds: 600 });
  const daily = decideAccess(paid({ account_24h: 1500 }), 100, limits, enforce);
  assertEquals(daily.ok ? null : daily.rejection.body.error, "Daily fair-use limit reached.");
  const chars = decideAccess(paid({ account_chars_24h: 1_200_000 }), 100, limits, enforce);
  assertEquals(chars.ok ? null : chars.rejection.body.error, "Daily fair-use limit reached.");
});

Deno.test("an active plan never expires as a trial", () => {
  const decision = decideAccess(paid({ first_seen_ms: now - 400 * day }), 100, limits, enforce);
  assertEquals(decision.ok, true);
});

Deno.test("parseAccessSnapshot accepts the RPC row and rejects garbage", () => {
  const row = { first_seen_ms: 1, plan: "active", account_hash: "h", plan_name: null, identity_24h: 0, account_10m: "2", account_24h: 3, account_chars_24h: 4 };
  assertEquals(parseAccessSnapshot(row).account_10m, 2);
  assertThrows(() => parseAccessSnapshot(null));
  assertThrows(() => parseAccessSnapshot({ ...row, plan: "gold" }));
  assertThrows(() => parseAccessSnapshot({ ...row, identity_24h: "many" }));
});
