import { handlePreflight, json, methodNotAllowed, requireJSON } from "../_shared/http.ts";
import { sha256Hex } from "../_shared/security.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { feedbackEmailHTML, feedbackEmailSubject, sendEmail } from "../_shared/email.ts";

const notifyEmail = Deno.env.get("FEEDBACK_NOTIFY_EMAIL") ?? "info@control-v.info";
const dailyLimitPerInstall = Number(Deno.env.get("FEEDBACK_DAILY_LIMIT") ?? "10");
const maxMessageLength = 2000;
const categories = new Set(["bug", "idea", "praise", "other"]);

type FeedbackRequest = {
  rating: number | null;
  category: string;
  message: string;
  contactEmail: string | null;
  installID: string;
  sessionToken: string | null;
  appVersion: string | null;
  platform: string;
};

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed(req);
  const notJSON = requireJSON(req);
  if (notJSON) return notJSON;

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400, req);
  }

  const parsed = parseRequest(body);
  if (!parsed.ok) {
    return json({ error: parsed.error }, 400, req);
  }
  const input = parsed.value;

  const client = createServiceClient();
  const installIDHash = await sha256Hex(input.installID);

  // Rate limit per install to keep the mailbox and table sane.
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count, error: countError } = await client
    .from("app_feedback")
    .select("*", { count: "exact", head: true })
    .eq("install_id_hash", installIDHash)
    .gte("created_at", since);
  if (countError) {
    return json({ error: "Could not submit feedback" }, 500, req);
  }
  if (count !== null && count >= dailyLimitPerInstall) {
    return json({ error: "Too much feedback for today. Thank you, we got it!" }, 429, req);
  }

  const account = await resolveAccount(client, input.sessionToken);

  const { data: row, error: insertError } = await client
    .from("app_feedback")
    .insert({
      rating: input.rating,
      category: input.category,
      message: input.message,
      contact_email: input.contactEmail,
      account_id: account?.id ?? null,
      install_id_hash: installIDHash,
      app_version: input.appVersion,
      platform: input.platform,
    })
    .select("id")
    .single();

  if (insertError || !row?.id) {
    return json({ error: "Could not save feedback" }, 500, req);
  }

  const emailInput = {
    rating: input.rating,
    category: input.category,
    message: input.message,
    contactEmail: input.contactEmail,
    accountEmail: account?.email ?? null,
    appVersion: input.appVersion,
    platform: input.platform,
    installIDHash,
  };
  const sent = await sendEmail({
    to: notifyEmail,
    subject: feedbackEmailSubject(emailInput),
    html: feedbackEmailHTML(emailInput),
  });
  if (sent) {
    await client.from("app_feedback").update({ email_sent: true }).eq("id", row.id);
  }

  // Saving is the contract; the email is best-effort and never fails the request.
  return json({ ok: true, emailed: sent }, 200, req);
});

function parseRequest(body: unknown): { ok: true; value: FeedbackRequest } | { ok: false; error: string } {
  if (!body || typeof body !== "object") return { ok: false, error: "Invalid request body" };
  const b = body as Record<string, unknown>;

  const installID = typeof b.installID === "string" ? b.installID.trim() : "";
  if (!installID) return { ok: false, error: "Missing installID" };

  const category = typeof b.category === "string" ? b.category.trim().toLowerCase() : "other";
  if (!categories.has(category)) return { ok: false, error: "Invalid category" };

  let rating: number | null = null;
  if (typeof b.rating === "number" && Number.isInteger(b.rating)) {
    if (b.rating < 1 || b.rating > 5) return { ok: false, error: "Rating must be 1–5" };
    rating = b.rating;
  }

  const message = typeof b.message === "string" ? b.message.trim() : "";
  if (message.length > maxMessageLength) return { ok: false, error: `Message is too long (max ${maxMessageLength} characters)` };
  if (rating === null && message.length === 0) return { ok: false, error: "Add a rating or a message" };

  const contactEmailRaw = typeof b.contactEmail === "string" ? b.contactEmail.trim().toLowerCase() : "";
  const contactEmail = contactEmailRaw.includes("@") ? contactEmailRaw.slice(0, 254) : null;

  const sessionToken = typeof b.sessionToken === "string" && b.sessionToken.trim() ? b.sessionToken.trim() : null;
  const appVersion = typeof b.appVersion === "string" && b.appVersion.trim() ? b.appVersion.trim().slice(0, 40) : null;
  const platformRaw = typeof b.platform === "string" ? b.platform.trim().toLowerCase() : "";
  const platform = platformRaw ? platformRaw.slice(0, 20) : "macos";

  return { ok: true, value: { rating, category, message, contactEmail, installID, sessionToken, appVersion, platform } };
}

async function resolveAccount(
  client: ReturnType<typeof createServiceClient>,
  sessionToken: string | null,
): Promise<{ id: string; email: string | null } | null> {
  if (!sessionToken) return null;
  const pepper = Deno.env.get("MAGIC_CODE_PEPPER");
  if (!pepper) return null;

  const tokenHash = await sha256Hex(`${sessionToken}:${pepper}`);
  const { data: session } = await client
    .from("app_sessions")
    .select("account_id")
    .eq("token_hash", tokenHash)
    .gt("expires_at", new Date().toISOString())
    .maybeSingle();
  if (!session?.account_id) return null;

  const { data: account } = await client
    .from("subscription_accounts")
    .select("id, email")
    .eq("id", session.account_id)
    .maybeSingle();
  if (!account?.id) return null;
  return { id: account.id as string, email: (account.email as string | null) ?? null };
}
