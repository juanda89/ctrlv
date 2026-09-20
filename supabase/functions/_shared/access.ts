/**
 * Pure access decision for /translate.
 *
 * The database work happens in one round trip (`translate_begin` RPC, see
 * supabase/migrations/20260919210000_translate_begin_rpc.sql) and returns a
 * snapshot; this module turns that snapshot plus the configured limits into
 * either an access plan or the exact rejection the client already knows how
 * to show. Keeping it pure makes every branch unit-testable without a DB.
 */

export type AccessSnapshot = {
  first_seen_ms: number;
  plan: "trial" | "active";
  account_hash: string | null;
  plan_name: string | null;
  identity_24h: number;
  account_10m: number;
  account_24h: number;
  account_chars_24h: number;
};

export type AccessLimits = {
  trialDays: number;
  trialDailyLimit: number;
  trialMaxCharacters: number;
  paidBurstLimit: number;
  paidDailyLimit: number;
  paidDailyCharacterLimit: number;
  paidMaxCharacters: number;
};

export type AccessPlan = {
  plan: "trial" | "active";
  accountHash: string | null;
  planName: string | null;
  trialDaysRemaining: number;
};

export type Rejection = { status: number; body: Record<string, unknown> };

export type AccessDecision =
  | { ok: true; plan: AccessPlan }
  | { ok: false; rejection: Rejection };

/// Validates the RPC payload; a malformed row is a server bug, never a
/// reason to let a request through or to block it silently.
export function parseAccessSnapshot(data: unknown): AccessSnapshot {
  if (!data || typeof data !== "object") throw new Error("translate_begin returned no row");
  const row = data as Record<string, unknown>;
  const plan = row.plan;
  if (plan !== "trial" && plan !== "active") throw new Error("translate_begin returned an unknown plan");
  const number = (key: string): number => {
    const value = Number(row[key]);
    if (!Number.isFinite(value)) throw new Error(`translate_begin returned a non-numeric ${key}`);
    return value;
  };
  const text = (key: string): string | null => (typeof row[key] === "string" ? (row[key] as string) : null);
  return {
    first_seen_ms: number("first_seen_ms"),
    plan,
    account_hash: text("account_hash"),
    plan_name: text("plan_name"),
    identity_24h: number("identity_24h"),
    account_10m: number("account_10m"),
    account_24h: number("account_24h"),
    account_chars_24h: number("account_chars_24h"),
  };
}

/**
 * `enforceLimits: false` is the passthrough path (bare URL / email): it still
 * refuses an expired trial, but never counts against a quota because no model
 * call happens.
 */
export function decideAccess(
  snapshot: AccessSnapshot,
  textLength: number,
  limits: AccessLimits,
  options: { enforceLimits: boolean; now?: number },
): AccessDecision {
  const now = options.now ?? Date.now();
  const trialDaysRemaining = calculateTrialDaysRemaining(snapshot.first_seen_ms, limits.trialDays, now);
  const plan: AccessPlan = {
    plan: snapshot.plan,
    accountHash: snapshot.plan === "active" ? snapshot.account_hash : null,
    planName: snapshot.plan === "active" ? snapshot.plan_name : null,
    trialDaysRemaining,
  };

  if (plan.plan === "trial" && trialDaysRemaining <= 0) {
    return { ok: false, rejection: { status: 403, body: { error: "Trial expired" } } };
  }
  if (!options.enforceLimits) return { ok: true, plan };

  const rejection = plan.plan === "trial"
    ? trialRejection(snapshot, textLength, limits, now)
    : paidRejection(snapshot, textLength, limits, now);
  return rejection ? { ok: false, rejection } : { ok: true, plan };
}

function trialRejection(snapshot: AccessSnapshot, textLength: number, limits: AccessLimits, now: number): Rejection | null {
  if (textLength > limits.trialMaxCharacters) {
    return { status: 429, body: { error: `Trial text exceeds ${limits.trialMaxCharacters} characters.` } };
  }
  if (snapshot.identity_24h >= limits.trialDailyLimit) {
    return { status: 429, body: { error: "Trial daily limit reached.", retry_after_seconds: secondsUntilTomorrowUTC(now) } };
  }
  return null;
}

function paidRejection(snapshot: AccessSnapshot, textLength: number, limits: AccessLimits, now: number): Rejection | null {
  if (textLength > limits.paidMaxCharacters) {
    return { status: 429, body: { error: `Request exceeds ${limits.paidMaxCharacters} characters.` } };
  }
  if (snapshot.account_10m >= limits.paidBurstLimit) {
    return { status: 429, body: { error: "Too many requests in a short period.", retry_after_seconds: 600 } };
  }
  if (snapshot.account_24h >= limits.paidDailyLimit || snapshot.account_chars_24h >= limits.paidDailyCharacterLimit) {
    return { status: 429, body: { error: "Daily fair-use limit reached.", retry_after_seconds: secondsUntilTomorrowUTC(now) } };
  }
  return null;
}

export function calculateTrialDaysRemaining(firstSeenMs: number, trialDays: number, now: number): number {
  const elapsedDays = Math.floor((now - firstSeenMs) / (1000 * 60 * 60 * 24));
  return Math.max(0, trialDays - elapsedDays);
}

export function secondsUntilTomorrowUTC(now: number): number {
  const date = new Date(now);
  const tomorrow = Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() + 1);
  return Math.max(60, Math.floor((tomorrow - now) / 1000));
}
