import { handlePreflight, json, methodNotAllowed, requireJSON } from "../_shared/http.ts";
import { randomToken, sha256Hex } from "../_shared/security.ts";
import { createServiceClient } from "../_shared/supabase.ts";

const sessionLifetimeDays = Number(Deno.env.get("SESSION_LIFETIME_DAYS") ?? "30");
const maxAttemptsPerCode = Number(Deno.env.get("MAGIC_CODE_MAX_ATTEMPTS") ?? "5");

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed(req);
  const notJSON = requireJSON(req);
  if (notJSON) return notJSON;

  let payload: { email?: string; code?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400, req);
  }

  const email = normalizeEmail(payload.email);
  const code = payload.code?.trim();
  if (!email || !code) {
    return json({ error: "Email and code are required" }, 400, req);
  }
  // Codes are exactly six digits; anything else cannot match and must not
  // burn an attempt on the real code.
  if (!/^\d{6}$/.test(code)) {
    return json({ error: "Invalid or expired code" }, 401, req);
  }

  const pepper = Deno.env.get("MAGIC_CODE_PEPPER");
  if (!pepper) {
    return json({ error: "Server configuration error" }, 500, req);
  }

  const client = createServiceClient();

  // One atomic statement: locks the newest live code, consumes it on a match,
  // counts a failed attempt otherwise and burns the code after
  // maxAttemptsPerCode. The generic 401 hides whether a code exists at all.
  const candidateHash = await sha256Hex(`${code}:${pepper}`);
  const { data: outcome, error: consumeError } = await client.rpc("consume_magic_code", {
    p_email: email,
    p_code_hash: candidateHash,
    p_max_attempts: maxAttemptsPerCode,
  });
  if (consumeError) {
    return json({ error: "Failed to verify code" }, 500, req);
  }
  if (outcome !== "ok") {
    return json({ error: "Invalid or expired code" }, 401, req);
  }

  // The address has proven it receives mail: create (or find) its account.
  const { data: account, error: accountError } = await client
    .from("subscription_accounts")
    .upsert({ email }, { onConflict: "email" })
    .select("id")
    .single();
  if (accountError || !account?.id) {
    return json({ error: "Failed to create account" }, 500, req);
  }

  const token = randomToken(32);
  const tokenHash = await sha256Hex(`${token}:${pepper}`);
  const expiresAt = new Date(Date.now() + sessionLifetimeDays * 24 * 60 * 60 * 1000).toISOString();

  const { error: sessionError } = await client.from("app_sessions").insert({
    account_id: account.id,
    token_hash: tokenHash,
    expires_at: expiresAt,
  });
  if (sessionError) {
    return json({ error: "Failed to create session" }, 500, req);
  }

  return json({ sessionToken: token }, 200, req);
});

function normalizeEmail(input: string | undefined): string | null {
  if (!input) return null;
  const normalized = input.trim().toLowerCase();
  if (normalized.length > 254) return null;
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized)) return null;
  return normalized;
}
