import { hmacSha256Hex, secureCompare } from "./security.ts";

const STRIPE_API_BASE = "https://api.stripe.com/v1";

export class StripeError extends Error {
  constructor(message: string, public statusCode: number) {
    super(message);
    this.name = "StripeError";
  }
}

function getSecretKey(): string {
  const key = Deno.env.get("STRIPE_SECRET_KEY");
  if (!key) throw new StripeError("Missing STRIPE_SECRET_KEY", 500);
  return key;
}

async function stripeFetch(
  path: string,
  body: Record<string, string>,
  method: "POST" | "GET" = "POST",
): Promise<Record<string, unknown>> {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(body)) {
    if (value !== undefined && value !== null && value !== "") {
      params.append(key, value);
    }
  }

  const response = await fetch(`${STRIPE_API_BASE}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${getSecretKey()}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: method === "POST" ? params.toString() : undefined,
  });

  const json = await response.json();
  if (!response.ok) {
    const message = (json as { error?: { message?: string } })?.error?.message ?? "Stripe API error";
    throw new StripeError(message, response.status);
  }
  return json as Record<string, unknown>;
}

export type CheckoutSessionParams = {
  priceID: string;
  customerEmail: string;
  successURL: string;
  cancelURL: string;
  clientReferenceID: string;
  existingCustomerID?: string | null;
};

export async function createCheckoutSession(
  params: CheckoutSessionParams,
): Promise<{ id: string; url: string }> {
  const body: Record<string, string> = {
    "mode": "subscription",
    "line_items[0][price]": params.priceID,
    "line_items[0][quantity]": "1",
    "success_url": params.successURL,
    "cancel_url": params.cancelURL,
    "client_reference_id": params.clientReferenceID,
    "allow_promotion_codes": "true",
    "billing_address_collection": "auto",
  };

  if (params.existingCustomerID) {
    body["customer"] = params.existingCustomerID;
  } else {
    body["customer_email"] = params.customerEmail;
    body["customer_creation"] = "always";
  }

  const result = await stripeFetch("/checkout/sessions", body);
  return {
    id: result.id as string,
    url: result.url as string,
  };
}

export type PortalSessionParams = {
  customerID: string;
  returnURL: string;
};

export async function createPortalSession(
  params: PortalSessionParams,
): Promise<{ id: string; url: string }> {
  const result = await stripeFetch("/billing_portal/sessions", {
    customer: params.customerID,
    return_url: params.returnURL,
  });
  return {
    id: result.id as string,
    url: result.url as string,
  };
}

// Stripe webhook signature verification
// Format: t=<timestamp>,v1=<signature>
export async function verifyStripeSignature(
  signatureHeader: string,
  rawBody: string,
  secret: string,
  toleranceSeconds = 300,
): Promise<{ ok: boolean; message?: string }> {
  const fields = signatureHeader.split(",").map((entry) => entry.trim());
  const timestampRaw = fields.find((field) => field.startsWith("t="))?.slice(2);
  const signatures = fields
    .filter((field) => field.startsWith("v1="))
    .map((field) => field.slice(3))
    .filter((field) => field.length > 0);

  if (!timestampRaw || signatures.length === 0) {
    return { ok: false, message: "Invalid Stripe-Signature format" };
  }

  const timestamp = Number(timestampRaw);
  if (!Number.isFinite(timestamp)) {
    return { ok: false, message: "Invalid signature timestamp" };
  }

  const nowSeconds = Math.floor(Date.now() / 1000);
  if (Math.abs(nowSeconds - timestamp) > toleranceSeconds) {
    return { ok: false, message: "Signature timestamp outside allowed window" };
  }

  const signedPayload = `${timestamp}.${rawBody}`;
  const expected = await hmacSha256Hex(secret, signedPayload);
  const matched = signatures.some((signature) => secureCompare(signature, expected));
  if (!matched) {
    return { ok: false, message: "Invalid signature hash" };
  }

  return { ok: true };
}

// Normalize Stripe subscription statuses to our internal vocabulary.
// Our DB constraint accepts: 'trial' | 'active' | 'past_due' | 'canceled' | 'expired'
export function normalizeStripeStatus(status: string): string {
  switch (status) {
    case "active":
    case "trialing":
      return "active";
    case "past_due":
      return "past_due";
    case "canceled":
    case "incomplete_expired":
      return "canceled";
    case "unpaid":
      return "past_due";
    case "incomplete":
      return "past_due";
    default:
      return "expired";
  }
}
