import { json, handlePreflight, methodNotAllowed } from "../_shared/http.ts";
import { randomDigits, sha256Hex } from "../_shared/security.ts";
import { createServiceClient } from "../_shared/supabase.ts";

const codeLifetimeMinutes = Number(Deno.env.get("MAGIC_CODE_LIFETIME_MINUTES") ?? "10");

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed(req);

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

  // Rate limit: max 3 codes per email per 10 minutes
  const rateLimitSince = new Date(Date.now() - 10 * 60_000).toISOString();
  const { count, error: countError } = await client
    .from("magic_codes")
    .select("*", { count: "exact", head: true })
    .eq("email", email)
    .gte("created_at", rateLimitSince);

  if (!countError && count !== null && count >= 3) {
    return json({ error: "Too many requests. Try again in a few minutes." }, 429, req);
  }

  const code = randomDigits(6);
  const codeHash = await sha256Hex(`${code}:${pepper}`);
  const expiresAt = new Date(Date.now() + codeLifetimeMinutes * 60_000).toISOString();

  const { error: accountError } = await client
    .from("subscription_accounts")
    .upsert({ email }, { onConflict: "email" });
  if (accountError) {
    return json({ error: "Failed to process request" }, 500, req);
  }

  const { error: codeError } = await client
    .from("magic_codes")
    .insert({
      email,
      code_hash: codeHash,
      expires_at: expiresAt,
    });
  if (codeError) {
    return json({ error: "Failed to generate code" }, 500, req);
  }

  const sent = await maybeSendByResend(email, code);
  if (!sent) {
    // Only expose dev code on local Supabase instances
    const isLocal = (Deno.env.get("SUPABASE_URL") ?? "").includes("localhost") ||
                    (Deno.env.get("SUPABASE_URL") ?? "").includes("127.0.0.1");
    const exposeDevCode = Deno.env.get("ALLOW_DEV_MAGIC_CODE") === "true" && isLocal;
    if (exposeDevCode) {
      return json({ ok: true, code }, 200, req);
    }
    return json({ error: "Email provider not configured" }, 500, req);
  }

  return json({ ok: true }, 200, req);
});

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

function normalizeEmail(input: string | undefined): string | null {
  if (!input) return null;
  const normalized = input.trim().toLowerCase();
  if (!normalized.includes("@")) return null;
  return normalized;
}
