import { json, handlePreflight, methodNotAllowed } from "../_shared/http.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { sha256Hex } from "../_shared/security.ts";
import { createCheckoutSession, StripeError } from "../_shared/stripe.ts";

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
  const priceID = Deno.env.get("STRIPE_PRICE_ID");
  const appBaseURL = Deno.env.get("APP_BASE_URL") ?? "https://control-v.info";

  if (!pepper) {
    return json({ error: "Server configuration error" }, 500, req);
  }
  if (!priceID) {
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
    .select("id, email, stripe_customer_id")
    .eq("id", session.account_id)
    .single();

  if (accountError || !account?.email) {
    return json({ error: "Account not found" }, 500, req);
  }

  try {
    const checkout = await createCheckoutSession({
      priceID,
      customerEmail: account.email as string,
      successURL: `${appBaseURL}/success?session_id={CHECKOUT_SESSION_ID}`,
      cancelURL: `${appBaseURL}/cancel`,
      clientReferenceID: account.id as string,
      existingCustomerID: (account.stripe_customer_id as string | null) ?? null,
    });

    return json({ url: checkout.url, sessionId: checkout.id }, 200, req);
  } catch (error) {
    if (error instanceof StripeError) {
      return json({ error: "Could not create checkout session" }, error.statusCode, req);
    }
    return json({ error: "Could not create checkout session" }, 500, req);
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
