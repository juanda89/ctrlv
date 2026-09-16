import { json, handlePreflight, methodNotAllowed } from "../_shared/http.ts";
import { sha256Hex } from "../_shared/security.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { isoOrNull, statusFromTransaction, VerificationException, verifyTransaction } from "../_shared/appstore.ts";

/// Called by the iOS app after a purchase/renewal with the signed StoreKit 2
/// transaction. Verifies Apple's signature chain and links the subscription
/// to the signed-in account so Mac and iOS share one subscription state.
Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed(req);

  const token = bearerToken(req.headers.get("Authorization"));
  if (!token) return json({ error: "Missing bearer token" }, 401, req);

  let body: { signedTransaction?: unknown };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON body" }, 400, req); }
  const jws = typeof body.signedTransaction === "string" ? body.signedTransaction.trim() : "";
  if (!jws) return json({ error: "Missing signedTransaction" }, 400, req);

  const pepper = Deno.env.get("MAGIC_CODE_PEPPER");
  if (!pepper) return json({ error: "Server configuration error" }, 500, req);

  const client = createServiceClient();
  const tokenHash = await sha256Hex(`${token}:${pepper}`);
  const { data: session } = await client
    .from("app_sessions").select("account_id").eq("token_hash", tokenHash)
    .gt("expires_at", new Date().toISOString()).maybeSingle();
  if (!session?.account_id) return json({ error: "Invalid session" }, 401, req);

  let tx;
  try {
    tx = await verifyTransaction(jws);
  } catch (error) {
    if (error instanceof VerificationException) return json({ error: "Transaction failed verification" }, 400, req);
    return json({ error: "Verification unavailable" }, 500, req);
  }
  if (!tx.originalTransactionId || !tx.productId) return json({ error: "Malformed transaction" }, 400, req);

  const status = statusFromTransaction(tx);
  const { error } = await client.from("account_subscriptions").upsert({
    account_id: session.account_id,
    appstore_original_transaction_id: tx.originalTransactionId,
    provider: "appstore",
    status,
    plan_name: tx.productId,
    current_period_ends_at: isoOrNull(tx.expiresDate),
    raw_payload: tx,
    updated_at: new Date().toISOString(),
  }, { onConflict: "appstore_original_transaction_id" });
  if (error) return json({ error: "Could not save subscription" }, 500, req);

  return json({ ok: true, status, expiresAt: isoOrNull(tx.expiresDate), environment: tx.environment ?? null }, 200, req);
});

function bearerToken(header: string | null): string | null {
  if (!header) return null;
  const [scheme, token] = header.split(" ");
  return scheme?.toLowerCase() === "bearer" && token ? token.trim() : null;
}
