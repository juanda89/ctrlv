import { json, handlePreflight, methodNotAllowed } from "../_shared/http.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { sha256Hex } from "../_shared/security.ts";
import { createPortalSession, StripeError } from "../_shared/stripe.ts";

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed(req);

  const authHeader = req.headers.get("Authorization");
  const token = bearerToken(authHeader);
  if (!token) {
    return json({ error: "Missing bearer token" }, 401, req);
  }

  const pepper = Deno.env.get("MAGIC_CODE_PEPPER");
  const appBaseURL = Deno.env.get("APP_BASE_URL") ?? "https://control-v.info";

  if (!pepper) {
    return json({ error: "Server configuration error" }, 500, req);
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
    return json({ error: "Failed to verify session" }, 500, req);
  }
  if (!session?.account_id) {
    return json({ error: "Invalid session" }, 401, req);
  }

  const { data: account, error: accountError } = await client
    .from("subscription_accounts")
    .select("stripe_customer_id")
    .eq("id", session.account_id)
    .single();

  if (accountError || !account?.stripe_customer_id) {
    return json({ error: "No subscription found for this account" }, 404, req);
  }

  try {
    const portal = await createPortalSession({
      customerID: account.stripe_customer_id as string,
      returnURL: `${appBaseURL}/`,
    });

    return json({ url: portal.url }, 200, req);
  } catch (error) {
    if (error instanceof StripeError) {
      return json({ error: "Could not create portal session" }, error.statusCode, req);
    }
    return json({ error: "Could not create portal session" }, 500, req);
  }
});

function bearerToken(header: string | null): string | null {
  if (!header) return null;
  const [scheme, token] = header.split(" ");
  if (scheme?.toLowerCase() !== "bearer" || !token) {
    return null;
  }
  return token.trim();
}
