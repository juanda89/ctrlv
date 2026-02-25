import { json, handlePreflight, methodNotAllowed } from "../_shared/http.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { hmacSha256Hex, secureCompare } from "../_shared/security.ts";
import { normalizePaddleSubscriptionStatus } from "../_shared/subscription.ts";

type PaddleEvent = {
  event_id: string;
  event_type: string;
  data?: Record<string, unknown>;
};

const signatureToleranceSeconds = Number(Deno.env.get("PADDLE_SIGNATURE_TOLERANCE_SECONDS") ?? "300");

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed();

  const webhookSecret = Deno.env.get("PADDLE_WEBHOOK_SECRET");
  if (!webhookSecret) {
    return json({ error: "Missing PADDLE_WEBHOOK_SECRET" }, 500);
  }

  const signatureHeader = req.headers.get("Paddle-Signature");
  if (!signatureHeader) {
    return json({ error: "Missing Paddle-Signature header" }, 400);
  }

  const rawBody = await req.text();
  const verification = await verifyPaddleSignature(signatureHeader, rawBody, webhookSecret);
  if (!verification.ok) {
    return json({ error: verification.message }, 400);
  }

  let event: PaddleEvent;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return json({ error: "Invalid JSON payload" }, 400);
  }

  if (!event.event_id || !event.event_type) {
    return json({ error: "Missing event_id or event_type" }, 400);
  }

  const client = createServiceClient();

  const { error: eventInsertError } = await client
    .from("paddle_webhook_events")
    .insert({
      event_id: event.event_id,
      event_type: event.event_type,
      payload: event,
    });

  if (eventInsertError?.code === "23505") {
    return json({ ok: true, deduplicated: true });
  }

  if (eventInsertError) {
    return json({ error: eventInsertError.message }, 500);
  }

  try {
    if (event.event_type.startsWith("customer.")) {
      await syncCustomerEvent(client, event.data ?? {});
    }
    if (event.event_type.startsWith("subscription.")) {
      await syncSubscriptionEvent(client, event.data ?? {});
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown webhook processing error";
    return json({ error: message }, 500);
  }

  return json({ ok: true });
});

async function verifyPaddleSignature(
  signatureHeader: string,
  rawBody: string,
  secret: string
): Promise<{ ok: boolean; message?: string }> {
  const fields = signatureHeader.split(";").map((entry) => entry.trim());
  const timestampRaw = fields.find((field) => field.startsWith("ts="))?.slice(3);
  const signatures = fields
    .filter((field) => field.startsWith("h1="))
    .map((field) => field.slice(3))
    .filter((field) => field.length > 0);

  if (!timestampRaw || signatures.length === 0) {
    return { ok: false, message: "Invalid Paddle-Signature format" };
  }

  const timestamp = Number(timestampRaw);
  if (!Number.isFinite(timestamp)) {
    return { ok: false, message: "Invalid signature timestamp" };
  }

  const nowSeconds = Math.floor(Date.now() / 1000);
  if (Math.abs(nowSeconds - timestamp) > signatureToleranceSeconds) {
    return { ok: false, message: "Signature timestamp outside allowed window" };
  }

  const signedPayload = `${timestamp}:${rawBody}`;
  const expected = await hmacSha256Hex(secret, signedPayload);
  const matched = signatures.some((signature) => secureCompare(signature, expected));
  if (!matched) {
    return { ok: false, message: "Invalid signature hash" };
  }

  return { ok: true };
}

async function syncCustomerEvent(client: ReturnType<typeof createServiceClient>, data: Record<string, unknown>) {
  const customerID = asString(data.id);
  const email = asString(data.email)?.toLowerCase();
  if (!customerID || !email) {
    return;
  }

  const { data: existingByCustomer } = await client
    .from("subscription_accounts")
    .select("id")
    .eq("paddle_customer_id", customerID)
    .maybeSingle();

  if (existingByCustomer?.id) {
    const { error } = await client
      .from("subscription_accounts")
      .update({ email, paddle_customer_id: customerID })
      .eq("id", existingByCustomer.id);
    if (error) throw new Error(error.message);
    return;
  }

  const { error } = await client
    .from("subscription_accounts")
    .upsert(
      {
        email,
        paddle_customer_id: customerID,
      },
      { onConflict: "email" }
    );
  if (error) throw new Error(error.message);
}

async function syncSubscriptionEvent(client: ReturnType<typeof createServiceClient>, data: Record<string, unknown>) {
  const subscriptionID = asString(data.id);
  const customerID = asString(data.customer_id);
  const status = normalizePaddleSubscriptionStatus(asString(data.status));

  if (!subscriptionID || !customerID) {
    return;
  }

  const accountID = await resolveAccountID(client, customerID);
  const planName = extractPlanName(data);

  const { error } = await client
    .from("account_subscriptions")
    .upsert(
      {
        account_id: accountID,
        paddle_subscription_id: subscriptionID,
        status,
        plan_name: planName,
        current_period_ends_at: asString(data.current_billing_period_ends_at),
        raw_payload: data,
      },
      { onConflict: "paddle_subscription_id" }
    );

  if (error) {
    throw new Error(error.message);
  }
}

async function resolveAccountID(client: ReturnType<typeof createServiceClient>, customerID: string): Promise<string> {
  const { data: existing } = await client
    .from("subscription_accounts")
    .select("id")
    .eq("paddle_customer_id", customerID)
    .maybeSingle();

  if (existing?.id) {
    return existing.id as string;
  }

  const placeholderEmail = `${customerID.toLowerCase()}@pending.paddle.local`;
  const { data: created, error } = await client
    .from("subscription_accounts")
    .insert({
      email: placeholderEmail,
      paddle_customer_id: customerID,
    })
    .select("id")
    .single();

  if (error || !created?.id) {
    throw new Error(error?.message ?? "Could not create account for subscription event");
  }

  return created.id as string;
}

function extractPlanName(data: Record<string, unknown>): string | null {
  const items = data.items;
  if (!Array.isArray(items) || items.length === 0) {
    return null;
  }

  const firstItem = items[0];
  if (typeof firstItem !== "object" || firstItem === null) {
    return null;
  }

  const price = (firstItem as Record<string, unknown>).price;
  if (typeof price !== "object" || price === null) {
    return null;
  }

  return asString((price as Record<string, unknown>).name);
}

function asString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}
