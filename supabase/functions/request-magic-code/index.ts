import { clientIP, handlePreflight, json, methodNotAllowed, requireJSON } from "../_shared/http.ts";
import { randomDigits, sha256Hex } from "../_shared/security.ts";
import { createServiceClient } from "../_shared/supabase.ts";

const codeLifetimeMinutes = Number(Deno.env.get("MAGIC_CODE_LIFETIME_MINUTES") ?? "10");
const codesPerEmailPer10Min = Number(Deno.env.get("MAGIC_CODES_PER_EMAIL_10M") ?? "3");
const codesPerNetworkPer10Min = Number(Deno.env.get("MAGIC_CODES_PER_IP_10M") ?? "10");

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed(req);
  const notJSON = requireJSON(req);
  if (notJSON) return notJSON;

  let payload: { email?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400, req);
  }

  const email = normalizeEmail(payload.email);
  if (!email) {
    return json({ error: "Invalid email" }, 400, req);
  }

  const pepper = Deno.env.get("MAGIC_CODE_PEPPER");
  if (!pepper) {
    return json({ error: "Server configuration error" }, 500, req);
  }

  const client = createServiceClient();
  const rateLimitSince = new Date(Date.now() - 10 * 60_000).toISOString();
  const ip = clientIP(req);
  const ipHash = ip ? await sha256Hex(`ip:${ip}:${pepper}`) : null;

  // Per-email and per-network caps on issued codes. Both fail CLOSED: a
  // counting error must never disable the throttle.
  const { count: emailCount, error: emailCountError } = await client
    .from("magic_codes")
    .select("*", { count: "exact", head: true })
    .eq("email", email)
    .gte("created_at", rateLimitSince);
  if (emailCountError) {
    return json({ error: "Failed to process request" }, 500, req);
  }
  if ((emailCount ?? 0) >= codesPerEmailPer10Min) {
    return json({ error: "Too many requests. Try again in a few minutes." }, 429, req);
  }

  if (ipHash) {
    const { count: ipCount, error: ipCountError } = await client
      .from("magic_codes")
      .select("*", { count: "exact", head: true })
      .eq("ip_hash", ipHash)
      .gte("created_at", rateLimitSince);
    if (ipCountError) {
      return json({ error: "Failed to process request" }, 500, req);
    }
    if ((ipCount ?? 0) >= codesPerNetworkPer10Min) {
      return json({ error: "Too many requests. Try again in a few minutes." }, 429, req);
    }
  }

  const demoCode = reviewDemoCode(email);
  const code = demoCode ?? randomDigits(6);
  const codeHash = await sha256Hex(`${code}:${pepper}`);
  const expiresAt = new Date(Date.now() + codeLifetimeMinutes * 60_000).toISOString();

  // The account row is created by verify-magic-code once the address has
  // proven it can receive mail; unverified addresses leave no PII behind.
  const { error: codeError } = await client
    .from("magic_codes")
    .insert({ email, code_hash: codeHash, expires_at: expiresAt, ip_hash: ipHash });
  if (codeError) {
    return json({ error: "Failed to generate code" }, 500, req);
  }

  const sent = demoCode !== null || await maybeSendByResend(email, code);
  if (!sent) {
    // Only expose dev code on local Supabase instances
    const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
    const isLocal = supabaseURL.includes("localhost") || supabaseURL.includes("127.0.0.1");
    const exposeDevCode = Deno.env.get("ALLOW_DEV_MAGIC_CODE") === "true" && isLocal;
    if (exposeDevCode) {
      return json({ ok: true, code }, 200, req);
    }
    return json({ error: "Email provider not configured" }, 500, req);
  }

  return json({ ok: true }, 200, req);
});

/// App Review signs in with a demo address that has no inbox. Its code is
/// fixed by two secrets and never emailed; the caps, expiry and the burn after
/// five wrong attempts still apply. Unset secrets disable it.
function reviewDemoCode(email: string): string | null {
  const demoEmail = normalizeEmail(Deno.env.get("REVIEW_DEMO_EMAIL") ?? undefined);
  const demoCode = Deno.env.get("REVIEW_DEMO_CODE")?.trim() ?? "";
  return demoEmail !== null && email === demoEmail && /^\d{6}$/.test(demoCode) ? demoCode : null;
}

async function maybeSendByResend(email: string, code: string): Promise<boolean> {
  const resendAPIKey = Deno.env.get("RESEND_API_KEY");
  const fromEmail = Deno.env.get("RESEND_FROM_EMAIL");
  if (!resendAPIKey || !fromEmail) {
    return false;
  }

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendAPIKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: fromEmail,
      to: [email],
      subject: "Your ctrl+v access code",
      html: `<p>Your ctrl+v code is:</p><p style="font-size:24px;font-weight:bold;letter-spacing:3px">${code}</p><p>This code expires in ${codeLifetimeMinutes} minutes.</p>`,
    }),
  });

  return response.ok;
}

/// Lowercased, trimmed, RFC-5321-length-bounded and shaped like an address.
/// Deliberately loose on the local part; strict on "one @, a dot after it".
export function normalizeEmail(input: string | undefined): string | null {
  if (!input) return null;
  const normalized = input.trim().toLowerCase();
  if (normalized.length > 254) return null;
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized)) return null;
  return normalized;
}
