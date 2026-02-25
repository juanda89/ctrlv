import { json, handlePreflight, methodNotAllowed } from "../_shared/http.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { normalizePaddleSubscriptionStatus } from "../_shared/subscription.ts";
import { sha256Hex } from "../_shared/security.ts";

const trialDays = Number(Deno.env.get("TRIAL_DAYS") ?? "14");

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed();

  const authHeader = req.headers.get("Authorization");
  const token = bearerToken(authHeader);
  if (!token) {
    return json({ error: "Missing bearer token" }, 401);
  }

  const pepper = Deno.env.get("MAGIC_CODE_PEPPER");
  if (!pepper) {
    return json({ error: "Missing MAGIC_CODE_PEPPER" }, 500);
  }

  const tokenHash = await sha256Hex(`${token}:${pepper}`);
  const client = createServiceClient();
  const nowISO = new Date().toISOString();

  const { data: session, error: sessionError } = await client
    .from("app_sessions")
    .select("account_id, expires_at")
    .eq("token_hash", tokenHash)
    .gt("expires_at", nowISO)
    .maybeSingle();

  if (sessionError) {
    return json({ error: sessionError.message }, 500);
  }
  if (!session?.account_id) {
    return json({ error: "Invalid session" }, 401);
  }

  const { data: account, error: accountError } = await client
    .from("subscription_accounts")
    .select("created_at")
    .eq("id", session.account_id)
    .single();

  if (accountError || !account?.created_at) {
    return json({ error: accountError?.message ?? "Account not found" }, 500);
  }

  const { data: subscription, error: subscriptionError } = await client
    .from("account_subscriptions")
    .select("status, plan_name")
    .eq("account_id", session.account_id)
    .order("updated_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (subscriptionError) {
    return json({ error: subscriptionError.message }, 500);
  }

  if (subscription?.status) {
    return json({
      status: normalizePaddleSubscriptionStatus(subscription.status as string),
      planName: subscription.plan_name ?? null,
      trialDaysRemaining: null,
    });
  }

  const installedAt = new Date(account.created_at);
  const elapsedDays = Math.floor((Date.now() - installedAt.getTime()) / (1000 * 60 * 60 * 24));
  const remaining = Math.max(0, trialDays - elapsedDays);

  return json({
    status: remaining > 0 ? "trial" : "expired",
    planName: null,
    trialDaysRemaining: remaining,
  });
});

function bearerToken(header: string | null): string | null {
  if (!header) return null;
  const [scheme, token] = header.split(" ");
  if (scheme?.toLowerCase() !== "bearer" || !token) {
    return null;
  }
  return token.trim();
}
