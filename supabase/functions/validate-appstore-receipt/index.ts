import { handlePreflight, json, methodNotAllowed, requireJSON } from "../_shared/http.ts";
import { sha256Hex } from "../_shared/security.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { allowSandbox, isoOrNull, statusFromTransaction, VerificationException, verifyTransaction } from "../_shared/appstore.ts";

/// Installs one purchase can unlock without an account (an iPhone and an iPad,
/// reinstalls). Beyond this the signed transaction is being shared.
const maxInstallsPerPurchase = Number(Deno.env.get("APPSTORE_MAX_INSTALLS_PER_PURCHASE") ?? "10");

/// Called by the iOS app after a purchase, a renewal and on launch with the
/// signed StoreKit 2 transaction. Verifies Apple's signature chain, links the
/// purchase to the forwarding install (translate_begin gives that install the
/// paid plan, signed in or not: App Review forbids requiring an account to
/// buy) and, when a session is present, to the account so Mac and iOS share
/// one subscription state.
Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed(req);
  const notJSON = requireJSON(req);
  if (notJSON) return notJSON;

  let body: { signedTransaction?: unknown; installID?: unknown };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON body" }, 400, req); }
  const jws = typeof body.signedTransaction === "string" ? body.signedTransaction.trim() : "";
  if (!jws) return json({ error: "Missing signedTransaction" }, 400, req);
  const installID = typeof body.installID === "string" ? body.installID.trim() : "";
  if (installID.length > 128) return json({ error: "Invalid installID" }, 400, req);

  const token = bearerToken(req.headers.get("Authorization"));
  if (!token && !installID) return json({ error: "Missing bearer token or installID" }, 401, req);

  const pepper = Deno.env.get("MAGIC_CODE_PEPPER");
  if (!pepper) return json({ error: "Server configuration error" }, 500, req);

  const client = createServiceClient();
  let accountID: string | null = null;
  if (token) {
    const tokenHash = await sha256Hex(`${token}:${pepper}`);
    const { data: session } = await client
      .from("app_sessions").select("account_id").eq("token_hash", tokenHash)
      .gt("expires_at", new Date().toISOString()).maybeSingle();
    if (!session?.account_id) return json({ error: "Invalid session" }, 401, req);
    accountID = session.account_id as string;
  }

  let tx;
  try {
    tx = await verifyTransaction(jws);
  } catch (error) {
    if (error instanceof VerificationException) return json({ error: "Transaction failed verification" }, 400, req);
    return json({ error: "Verification unavailable" }, 500, req);
  }
  if (!tx.originalTransactionId || !tx.productId) return json({ error: "Malformed transaction" }, 400, req);
  if (tx.environment !== "Production" && !allowSandbox) {
    return json({ error: "Sandbox transactions are not accepted" }, 403, req);
  }

  // A signed transaction is not a secret (any device with the purchase can
  // export it). Once linked, a subscription never changes owner through this
  // endpoint; a second account gets 409 instead of silently taking it over.
  const { data: existing, error: existingError } = await client
    .from("account_subscriptions")
    .select("account_id")
    .eq("appstore_original_transaction_id", tx.originalTransactionId)
    .maybeSingle();
  if (existingError) return json({ error: "Could not save subscription" }, 500, req);
  if (accountID && existing?.account_id && existing.account_id !== accountID) {
    return json({ error: "This subscription is linked to another account" }, 409, req);
  }

  const status = statusFromTransaction(tx);
  const { error } = await client.from("account_subscriptions").upsert({
    // Without a session, keep whatever account the purchase already has.
    account_id: accountID ?? existing?.account_id ?? null,
    appstore_original_transaction_id: tx.originalTransactionId,
    provider: "appstore",
    status,
    plan_name: tx.productId,
    current_period_ends_at: isoOrNull(tx.expiresDate),
    raw_payload: tx,
    updated_at: new Date().toISOString(),
  }, { onConflict: "appstore_original_transaction_id" });
  if (error) return json({ error: "Could not save subscription" }, 500, req);

  if (installID) {
    const linked = await linkInstall(client, tx.originalTransactionId, await sha256Hex(installID));
    if (!linked.ok) return json({ error: linked.error }, linked.status, req);
  }

  return json({ ok: true, status, expiresAt: isoOrNull(tx.expiresDate), environment: tx.environment ?? null }, 200, req);
});

/// Same hash translate uses for the install (`sha256Hex(installID)`).
async function linkInstall(
  client: ReturnType<typeof createServiceClient>,
  originalTransactionID: string,
  identityHash: string,
): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  const { data: current, error: readError } = await client
    .from("appstore_install_links").select("identity_hash")
    .eq("original_transaction_id", originalTransactionID);
  if (readError) return { ok: false, status: 500, error: "Could not link this device" };
  const hashes = (current ?? []).map((row) => row.identity_hash as string);
  if (hashes.includes(identityHash)) return { ok: true };
  if (hashes.length >= maxInstallsPerPurchase) {
    return { ok: false, status: 409, error: "This purchase is already in use on too many devices" };
  }
  const { error } = await client.from("appstore_install_links").upsert(
    { original_transaction_id: originalTransactionID, identity_hash: identityHash },
    { onConflict: "original_transaction_id,identity_hash", ignoreDuplicates: true },
  );
  return error ? { ok: false, status: 500, error: "Could not link this device" } : { ok: true };
}

function bearerToken(header: string | null): string | null {
  if (!header) return null;
  const [scheme, token] = header.split(" ");
  return scheme?.toLowerCase() === "bearer" && token ? token.trim() : null;
}
