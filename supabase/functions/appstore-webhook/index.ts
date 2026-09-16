import { json, handlePreflight, methodNotAllowed } from "../_shared/http.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { isoOrNull, statusFromTransaction, VerificationException, verifyNotification, verifyRenewalInfo, verifyTransaction } from "../_shared/appstore.ts";

/// App Store Server Notifications V2. Apple retries on non-2xx, so anything
/// we cannot act on (unknown subscription, unlinked account) is acknowledged
/// with 200 after logging; only bad signatures are rejected.
Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed(req);

  let body: { signedPayload?: unknown };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON body" }, 400, req); }
  const signedPayload = typeof body.signedPayload === "string" ? body.signedPayload : "";
  if (!signedPayload) return json({ error: "Missing signedPayload" }, 400, req);

  let notification;
  try {
    notification = await verifyNotification(signedPayload);
  } catch (error) {
    if (error instanceof VerificationException) return json({ error: "Notification failed verification" }, 401, req);
    return json({ error: "Verification unavailable" }, 500, req);
  }

  const client = createServiceClient();
  const eventId = `appstore_${notification.notificationUUID ?? crypto.randomUUID()}`;
  const { data: seen } = await client.from("paddle_webhook_events").select("event_id").eq("event_id", eventId).maybeSingle();
  if (seen) return json({ ok: true, duplicate: true }, 200, req);
  await client.from("paddle_webhook_events").insert({ event_id: eventId, event_type: `appstore.${notification.notificationType}`, payload: notification });

  const signedTx = notification.data?.signedTransactionInfo;
  if (!signedTx) return json({ ok: true, ignored: "no transaction" }, 200, req);

  let tx;
  try { tx = await verifyTransaction(signedTx); } catch { return json({ error: "Transaction failed verification" }, 401, req); }
  const renewal = notification.data?.signedRenewalInfo ? await verifyRenewalInfo(notification.data.signedRenewalInfo).catch(() => null) : null;

  const { data: existing } = await client
    .from("account_subscriptions").select("id, account_id")
    .eq("appstore_original_transaction_id", tx.originalTransactionId).maybeSingle();
  if (!existing) {
    // Purchase made before the user ever signed in on iOS: nothing to link yet.
    // The app forwards the signed transaction once an account exists.
    return json({ ok: true, ignored: "unlinked subscription" }, 200, req);
  }

  const status = mapStatus(notification.notificationType, notification.subtype, tx);
  const { error } = await client.from("account_subscriptions").update({
    status,
    plan_name: tx.productId ?? undefined,
    current_period_ends_at: isoOrNull(tx.expiresDate),
    raw_payload: { notificationType: notification.notificationType, subtype: notification.subtype ?? null, transaction: tx, renewal },
    updated_at: new Date().toISOString(),
  }).eq("id", existing.id);
  if (error) return json({ error: "Could not update subscription" }, 500, req);

  return json({ ok: true, status }, 200, req);
});

function mapStatus(type: string | undefined, subtype: string | undefined, tx: Parameters<typeof statusFromTransaction>[0]): string {
  switch (type) {
    case "SUBSCRIBED":
    case "DID_RENEW":
    case "OFFER_REDEEMED":
    case "DID_CHANGE_RENEWAL_PREF":
      return "active";
    case "DID_FAIL_TO_RENEW":
      // Billing retry: keep access during Apple's grace period, otherwise flag it.
      return subtype === "GRACE_PERIOD" ? "active" : "past_due";
    case "EXPIRED":
      return "expired";
    case "REFUND":
    case "REVOKE":
      return "canceled";
    case "DID_CHANGE_RENEWAL_STATUS":
      // Auto-renew toggled; access continues until expiresDate either way.
      return statusFromTransaction(tx);
    default:
      return statusFromTransaction(tx);
  }
}
