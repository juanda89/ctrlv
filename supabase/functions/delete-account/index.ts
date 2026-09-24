import { handlePreflight, json, methodNotAllowed, requireJSON } from "../_shared/http.ts";
import { sha256Hex } from "../_shared/security.ts";
import { cancelStripeSubscription } from "../_shared/stripe.ts";
import { createServiceClient } from "../_shared/supabase.ts";

/// In-app account deletion (App Review guideline 5.1.1(v)), authenticated by
/// the app's session token.
///
/// Order matters: Stripe subscriptions are cancelled first, because we bill
/// them and a deleted account must not keep paying; if Stripe fails nothing is
/// deleted and the user can simply retry. App Store subscriptions are billed
/// by Apple and only the user can cancel them (the app says so before
/// deleting). Then the account row goes: sessions and subscription rows
/// cascade, feedback keeps its text but loses the link and the contact email,
/// and pending sign-in codes for the address are purged.
Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed(req);
  const notJSON = requireJSON(req);
  if (notJSON) return notJSON;

  const token = bearerToken(req.headers.get("Authorization"));
  if (!token) return json({ error: "Missing bearer token" }, 401, req);
  const pepper = Deno.env.get("MAGIC_CODE_PEPPER");
  if (!pepper) return json({ error: "Server configuration error" }, 500, req);

  const client = createServiceClient();
  const tokenHash = await sha256Hex(`${token}:${pepper}`);
  const { data: session, error: sessionError } = await client
    .from("app_sessions").select("account_id").eq("token_hash", tokenHash)
    .gt("expires_at", new Date().toISOString()).maybeSingle();
  if (sessionError) return json({ error: "Failed to verify session" }, 500, req);
  if (!session?.account_id) return json({ error: "Invalid session" }, 401, req);
  const accountID = session.account_id as string;

  const { data: account, error: accountError } = await client
    .from("subscription_accounts").select("email").eq("id", accountID).maybeSingle();
  if (accountError || !account) return json({ error: "Failed to load account" }, 500, req);

  const { data: stripeSubscriptions, error: subscriptionsError } = await client
    .from("account_subscriptions").select("stripe_subscription_id, status")
    .eq("account_id", accountID).not("stripe_subscription_id", "is", null);
  if (subscriptionsError) return json({ error: "Failed to load subscriptions" }, 500, req);

  let cancelled = 0;
  for (const subscription of stripeSubscriptions ?? []) {
    if (subscription.status === "canceled" || subscription.status === "expired") continue;
    try {
      await cancelStripeSubscription(subscription.stripe_subscription_id as string);
      cancelled += 1;
    } catch (_error) {
      return json({
        error: "Your subscription could not be cancelled, so the account was not deleted. Try again in a minute.",
      }, 502, req);
    }
  }

  const { error: feedbackError } = await client
    .from("app_feedback").update({ contact_email: null }).eq("account_id", accountID);
  const { error: codesError } = await client
    .from("magic_codes").delete().eq("email", account.email as string);
  if (feedbackError || codesError) return json({ error: "Failed to delete account data" }, 500, req);

  const { error: deleteError } = await client.from("subscription_accounts").delete().eq("id", accountID);
  if (deleteError) return json({ error: "Failed to delete account" }, 500, req);

  return json({ deleted: true, cancelledSubscriptions: cancelled }, 200, req);
});

function bearerToken(header: string | null): string | null {
  if (!header) return null;
  const [scheme, token] = header.split(" ");
  return scheme?.toLowerCase() === "bearer" && token ? token.trim() : null;
}
