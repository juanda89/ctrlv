import { json, handlePreflight, methodNotAllowed } from "../_shared/http.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { normalizeStripeStatus, verifyStripeSignature } from "../_shared/stripe.ts";

type StripeEvent = {
  id: string;
  type: string;
  data?: { object?: Record<string, unknown> };
};

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed(req);

  const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  if (!webhookSecret) {
    return json({ error: "Server configuration error" }, 500, req);
  }

  const signatureHeader = req.headers.get("Stripe-Signature");
  if (!signatureHeader) {
    return json({ error: "Missing Stripe-Signature header" }, 400, req);
  }

  const rawBody = await req.text();
  const verification = await verifyStripeSignature(signatureHeader, rawBody, webhookSecret);
  if (!verification.ok) {
    return json({ error: verification.message }, 400, req);
  }

  let event: StripeEvent;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return json({ error: "Invalid JSON payload" }, 400, req);
  }

  if (!event.id || !event.type) {
    return json({ error: "Missing event id or type" }, 400, req);
  }

  const client = createServiceClient();
  const eventObject = event.data?.object ?? {};

  // Idempotency: store event_id in paddle_webhook_events table (reused for both providers).
  // The 23505 unique violation means we already processed this event.
  const { error: insertError } = await client
    .from("paddle_webhook_events")
    .insert({
      event_id: `stripe_${event.id}`,
      event_type: event.type,
      payload: event,
    });

  if (insertError?.code === "23505") {
    return json({ ok: true, deduplicated: true }, 200, req);
  }
  if (insertError) {
    return json({ error: "Failed to record webhook" }, 500, req);
  }

  try {
    switch (event.type) {
      case "checkout.session.completed":
        await handleCheckoutCompleted(client, eventObject);
        break;
      case "customer.subscription.created":
      case "customer.subscription.updated":
        await handleSubscriptionUpdate(client, eventObject);
        break;
      case "customer.subscription.deleted":
        await handleSubscriptionDeleted(client, eventObject);
        break;
      case "customer.updated":
        await handleCustomerUpdate(client, eventObject);
        break;
      default:
        // Unhandled event types are logged but not failed
        break;
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return json({ error: `Webhook handler failed: ${message}` }, 500, req);
  }

  return json({ ok: true }, 200, req);
});

async function handleCheckoutCompleted(
  client: ReturnType<typeof createServiceClient>,
  data: Record<string, unknown>,
) {
  const customerID = asString(data.customer);
  const subscriptionID = asString(data.subscription);
  const customerEmail = asString(data.customer_details && (data.customer_details as Record<string, unknown>).email)
    ?? asString(data.customer_email);

  if (!customerID || !subscriptionID || !customerEmail) {
    return;
  }

  const accountID = await ensureAccount(client, {
    email: customerEmail.toLowerCase(),
    stripeCustomerID: customerID,
  });

  // The subscription object is nested in expanded checkout sessions, but typically
  // we'll receive a `customer.subscription.created` event right after, which has full data.
  // We just create a placeholder row here so the account is linked.
  await client.from("account_subscriptions").upsert(
    {
      account_id: accountID,
      stripe_subscription_id: subscriptionID,
      provider: "stripe",
      status: "active",
      raw_payload: data,
    },
    { onConflict: "stripe_subscription_id" },
  );
}

async function handleSubscriptionUpdate(
  client: ReturnType<typeof createServiceClient>,
  data: Record<string, unknown>,
) {
  const subscriptionID = asString(data.id);
  const customerID = asString(data.customer);
  const rawStatus = asString(data.status) ?? "expired";
  const status = normalizeStripeStatus(rawStatus);
  const periodEndsRaw = data.current_period_end;
  const periodEndsAt = typeof periodEndsRaw === "number"
    ? new Date(periodEndsRaw * 1000).toISOString()
    : null;
  const planName = extractPlanName(data);

  if (!subscriptionID || !customerID) return;

  const accountID = await resolveAccountByCustomerID(client, customerID);
  if (!accountID) return;

  const { error } = await client.from("account_subscriptions").upsert(
    {
      account_id: accountID,
      stripe_subscription_id: subscriptionID,
      provider: "stripe",
      status,
      plan_name: planName,
      current_period_ends_at: periodEndsAt,
      raw_payload: data,
    },
    { onConflict: "stripe_subscription_id" },
  );

  if (error) {
    throw new Error(error.message);
  }
}

async function handleSubscriptionDeleted(
  client: ReturnType<typeof createServiceClient>,
  data: Record<string, unknown>,
) {
  const subscriptionID = asString(data.id);
  if (!subscriptionID) return;

  const { error } = await client
    .from("account_subscriptions")
    .update({
      status: "canceled",
      raw_payload: data,
    })
    .eq("stripe_subscription_id", subscriptionID);

  if (error) {
    throw new Error(error.message);
  }
}

async function handleCustomerUpdate(
  client: ReturnType<typeof createServiceClient>,
  data: Record<string, unknown>,
) {
  const customerID = asString(data.id);
  const email = asString(data.email)?.toLowerCase();
  if (!customerID || !email) return;

  // Update email on existing account if linked.
  await client
    .from("subscription_accounts")
    .update({ email })
    .eq("stripe_customer_id", customerID);
}

async function ensureAccount(
  client: ReturnType<typeof createServiceClient>,
  params: { email: string; stripeCustomerID: string },
): Promise<string> {
  // Try to find by stripe_customer_id first
  const { data: byCustomer } = await client
    .from("subscription_accounts")
    .select("id")
    .eq("stripe_customer_id", params.stripeCustomerID)
    .maybeSingle();

  if (byCustomer?.id) return byCustomer.id as string;

  // Try to find by email and link Stripe customer ID
  const { data: byEmail } = await client
    .from("subscription_accounts")
    .select("id")
    .eq("email", params.email)
    .maybeSingle();

  if (byEmail?.id) {
    await client
      .from("subscription_accounts")
      .update({ stripe_customer_id: params.stripeCustomerID })
      .eq("id", byEmail.id);
    return byEmail.id as string;
  }

  // Create a new account
  const { data: created, error } = await client
    .from("subscription_accounts")
    .insert({
      email: params.email,
      stripe_customer_id: params.stripeCustomerID,
    })
    .select("id")
    .single();

  if (error || !created?.id) {
    throw new Error(error?.message ?? "Could not create account");
  }

  return created.id as string;
}

async function resolveAccountByCustomerID(
  client: ReturnType<typeof createServiceClient>,
  customerID: string,
): Promise<string | null> {
  const { data } = await client
    .from("subscription_accounts")
    .select("id")
    .eq("stripe_customer_id", customerID)
    .maybeSingle();

  return (data?.id as string) ?? null;
}

function extractPlanName(data: Record<string, unknown>): string | null {
  const items = data.items;
  if (typeof items !== "object" || items === null) return null;

  const dataArray = (items as Record<string, unknown>).data;
  if (!Array.isArray(dataArray) || dataArray.length === 0) return null;

  const firstItem = dataArray[0];
  if (typeof firstItem !== "object" || firstItem === null) return null;

  const price = (firstItem as Record<string, unknown>).price;
  if (typeof price !== "object" || price === null) return null;

  const nickname = asString((price as Record<string, unknown>).nickname);
  if (nickname) return nickname;

  const product = (price as Record<string, unknown>).product;
  if (typeof product === "object" && product !== null) {
    return asString((product as Record<string, unknown>).name);
  }

  return null;
}

function asString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}
