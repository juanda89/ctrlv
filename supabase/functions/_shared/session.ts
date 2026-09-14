import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

/// Server-side session lifetime. Must match verify-magic-code, which stamps
/// the initial expires_at at creation time.
export const sessionLifetimeDays = Number(Deno.env.get("SESSION_LIFETIME_DAYS") ?? "30");

/// Only write a renewal when it would move expires_at by at least this much.
/// Bounds DB writes to ~once per day per active session instead of one write
/// per request (the popover refreshes on every open).
const renewalThresholdMs = 24 * 60 * 60 * 1000;

/// Sliding-window session renewal.
///
/// Sessions are created with a fixed `expires_at` and were never extended on
/// use, so every signed-in user — paying subscribers included — got a 401 and
/// was forced to sign in again exactly `sessionLifetimeDays` after login,
/// regardless of activity. Calling this after a successful session validation
/// pushes `expires_at` forward so active users stay signed in indefinitely.
///
/// Best-effort: a failed renewal is swallowed. The request that triggered it
/// already validated against the *current* expiry, so a missed extension only
/// means we try again on the next call — never a spurious logout.
export async function renewSessionExpiry(
  client: SupabaseClient,
  tokenHash: string,
  currentExpiresAt: string | null | undefined,
): Promise<void> {
  const newExpiryMs = Date.now() + sessionLifetimeDays * 24 * 60 * 60 * 1000;

  if (currentExpiresAt) {
    const currentMs = new Date(currentExpiresAt).getTime();
    if (Number.isFinite(currentMs) && newExpiryMs - currentMs < renewalThresholdMs) {
      return; // Still fresh — skip the write.
    }
  }

  try {
    await client
      .from("app_sessions")
      .update({ expires_at: new Date(newExpiryMs).toISOString() })
      .eq("token_hash", tokenHash);
  } catch (_error) {
    // Non-fatal: validation already succeeded against the current expiry.
  }
}
