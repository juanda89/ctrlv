import { json, handlePreflight, methodNotAllowed } from "../_shared/http.ts";
import { randomToken, secureCompare, sha256Hex } from "../_shared/security.ts";
import { createServiceClient } from "../_shared/supabase.ts";

const sessionLifetimeDays = Number(Deno.env.get("SESSION_LIFETIME_DAYS") ?? "30");

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed(req);

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

  const pepper = Deno.env.get("MAGIC_CODE_PEPPER");
  if (!pepper) {
    return json({ error: "Server configuration error" }, 500, req);
  }

  const client = createServiceClient();
  const nowISO = new Date().toISOString();

  const { data: magicCodeRecord, error: lookupError } = await client
    .from("magic_codes")
    .select("id, code_hash, expires_at")
    .eq("email", email)
    .is("consumed_at", null)
    .gt("expires_at", nowISO)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (lookupError) {
    return json({ error: "Failed to verify code" }, 500, req);
  }
  if (!magicCodeRecord) {
    return json({ error: "Code not found or expired" }, 401, req);
  }

  const candidateHash = await sha256Hex(`${code}:${pepper}`);
  if (!secureCompare(candidateHash, magicCodeRecord.code_hash as string)) {
    return json({ error: "Invalid code" }, 401, req);
  }

  const { error: consumeError } = await client
    .from("magic_codes")
    .update({ consumed_at: nowISO })
    .eq("id", magicCodeRecord.id);
  if (consumeError) {
    return json({ error: "Failed to process code" }, 500, req);
  }

  const { data: account, error: accountError } = await client
    .from("subscription_accounts")
    .select("id")
    .eq("email", email)
    .single();
  if (accountError || !account?.id) {
    return json({ error: "Account not found" }, 500, req);
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
  if (!normalized.includes("@")) return null;
  return normalized;
}
