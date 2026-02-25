import { json, handlePreflight, methodNotAllowed } from "../_shared/http.ts";
import { randomDigits, sha256Hex } from "../_shared/security.ts";
import { createServiceClient } from "../_shared/supabase.ts";

const codeLifetimeMinutes = Number(Deno.env.get("MAGIC_CODE_LIFETIME_MINUTES") ?? "10");

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed();

  let payload: { email?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const email = normalizeEmail(payload.email);
  if (!email) {
    return json({ error: "Invalid email" }, 400);
  }

  const pepper = Deno.env.get("MAGIC_CODE_PEPPER");
  if (!pepper) {
    return json({ error: "Missing MAGIC_CODE_PEPPER" }, 500);
  }

  const code = randomDigits(6);
  const codeHash = await sha256Hex(`${code}:${pepper}`);
  const expiresAt = new Date(Date.now() + codeLifetimeMinutes * 60_000).toISOString();

  const client = createServiceClient();

  const { error: accountError } = await client
    .from("subscription_accounts")
    .upsert({ email }, { onConflict: "email" });
  if (accountError) {
    return json({ error: accountError.message }, 500);
  }

  const { error: codeError } = await client
    .from("magic_codes")
    .insert({
      email,
      code_hash: codeHash,
      expires_at: expiresAt,
    });
  if (codeError) {
    return json({ error: codeError.message }, 500);
  }

  const sent = await maybeSendByResend(email, code);
  if (!sent) {
    const exposeDevCode = Deno.env.get("ALLOW_DEV_MAGIC_CODE") === "true";
    if (exposeDevCode) {
      return json({ ok: true, code });
    }
    return json({ error: "Email provider not configured" }, 500);
  }

  return json({ ok: true });
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
