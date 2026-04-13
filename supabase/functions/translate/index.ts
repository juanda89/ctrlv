import { json, handlePreflight, methodNotAllowed } from "../_shared/http.ts";
import { validateLemonLicense } from "../_shared/lemon.ts";
import { OpenRouterRateLimitError, translateWithOpenRouter } from "../_shared/openrouter.ts";
import { sha256Hex } from "../_shared/security.ts";
import { createServiceClient } from "../_shared/supabase.ts";

const trialDays = Number(Deno.env.get("TRIAL_DAYS") ?? "14");
const trialDailyLimit = Number(Deno.env.get("TRIAL_DAILY_TRANSLATION_LIMIT") ?? "50");
const trialMaxCharacters = Number(Deno.env.get("TRIAL_MAX_CHARACTERS") ?? "3000");
const paidBurstLimit = Number(Deno.env.get("PAID_REQUESTS_PER_10_MIN") ?? "80");
const paidDailyLimit = Number(Deno.env.get("PAID_REQUESTS_PER_DAY") ?? "1500");
const paidDailyCharacterLimit = Number(Deno.env.get("PAID_CHARACTERS_PER_DAY") ?? "1200000");
const paidMaxCharacters = Number(Deno.env.get("PAID_MAX_CHARACTERS") ?? "12000");

type TranslateRequest = {
  text: string;
  systemPrompt: string;
  installID: string;
  licenseKey?: string | null;
  licenseInstanceID?: string | null;
  warmupOnly?: boolean;
};

type AccessPlan = {
  plan: "trial" | "active";
  licenseHash: string | null;
  planName: string | null;
  trialDaysRemaining: number;
};

Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed(req);

  try {
    const body = await req.json();
    const parsed = parseRequest(body);
    if (!parsed.ok) {
      return json({ error: parsed.error }, 400, req);
    }

    if (parsed.value.warmupOnly) {
      const result = await translateWithOpenRouter(parsed.value.text, parsed.value.systemPrompt);
      return json({ warmed: true, model: result.model }, 200, req);
    }

    const client = createServiceClient();
    const identityHash = await sha256Hex(parsed.value.installID);
    const identity = await upsertIdentity(client, identityHash);
    const plan = await resolveAccessPlan(parsed.value, identity.firstSeenAt);

    if (plan.plan === "trial" && plan.trialDaysRemaining <= 0) {
      return json({ error: "Trial expired" }, 403, req);
    }

    await syncIdentity(client, identityHash, plan);

    const rateLimit = await enforceLimits(client, identityHash, parsed.value.text.length, plan);
    if (rateLimit) {
      return json(rateLimit.body, 429, req);
    }

    const result = await translateWithOpenRouter(parsed.value.text, parsed.value.systemPrompt);
    await recordUsage(client, identityHash, plan, parsed.value.text.length, result.model);

    return json({
      translatedText: result.translatedText,
      model: result.model,
      plan: plan.plan,
    }, 200, req);
  } catch (error) {
    if (error instanceof OpenRouterRateLimitError) {
      return json(
        { error: "Translation service is busy. Please try again shortly.", retry_after_seconds: error.retryAfterSeconds },
        429, req,
      );
    }

    return json({ error: "Translation failed. Please try again." }, 500, req);
  }
});

function parseRequest(body: unknown): { ok: true; value: TranslateRequest } | { ok: false; error: string } {
  if (!body || typeof body !== "object") {
    return { ok: false, error: "Invalid request body" };
  }

  const text = readString(body, "text");
  const systemPrompt = readString(body, "systemPrompt");
  const installID = readString(body, "installID");

  if (!text || !systemPrompt || !installID) {
    return { ok: false, error: "Missing text, systemPrompt or installID" };
  }

  return {
    ok: true,
    value: {
      text,
      systemPrompt,
      installID,
      licenseKey: readOptionalString(body, "licenseKey"),
      licenseInstanceID: readOptionalString(body, "licenseInstanceID"),
      warmupOnly: readOptionalBoolean(body, "warmupOnly") ?? false,
    },
  };
}

async function upsertIdentity(client: ReturnType<typeof createServiceClient>, identityHash: string) {
  const nowISO = new Date().toISOString();
  const { data, error } = await client
    .from("translation_identities")
    .upsert(
      {
        identity_hash: identityHash,
        last_seen_at: nowISO,
      },
      { onConflict: "identity_hash" },
    )
    .select("first_seen_at")
    .single();

  if (error || !data?.first_seen_at) {
    throw new Error(error?.message ?? "Could not load translation identity");
  }

  return { firstSeenAt: data.first_seen_at as string };
}

async function resolveAccessPlan(request: TranslateRequest, firstSeenAt: string): Promise<AccessPlan> {
  const trialDaysRemaining = calculateTrialDaysRemaining(firstSeenAt);
  const licenseKey = request.licenseKey?.trim();
  if (!licenseKey) {
    return { plan: "trial", licenseHash: null, planName: null, trialDaysRemaining };
  }

  const validation = await validateLemonLicense(licenseKey, request.licenseInstanceID);
  if (!validation.isActive) {
    return { plan: "trial", licenseHash: null, planName: null, trialDaysRemaining };
  }

  const licenseHash = await sha256Hex(licenseKey);
  return {
    plan: "active",
    licenseHash,
    planName: validation.planName,
    trialDaysRemaining,
  };
}

function calculateTrialDaysRemaining(firstSeenAt: string): number {
  const startedAt = new Date(firstSeenAt).getTime();
  const elapsedDays = Math.floor((Date.now() - startedAt) / (1000 * 60 * 60 * 24));
  return Math.max(0, trialDays - elapsedDays);
}

async function syncIdentity(
  client: ReturnType<typeof createServiceClient>,
  identityHash: string,
  plan: AccessPlan,
) {
  const { error } = await client
    .from("translation_identities")
    .update({
      last_seen_at: new Date().toISOString(),
      last_plan: plan.plan,
      last_license_hash: plan.licenseHash,
    })
    .eq("identity_hash", identityHash);

  if (error) {
    throw new Error(error.message);
  }
}

async function enforceLimits(
  client: ReturnType<typeof createServiceClient>,
  identityHash: string,
  textLength: number,
  plan: AccessPlan,
) {
  if (plan.plan === "trial") {
    return await enforceTrialLimits(client, identityHash, textLength);
  }

  const scopeHash = plan.licenseHash ?? identityHash;
  return await enforcePaidLimits(client, scopeHash, textLength);
}

async function enforceTrialLimits(
  client: ReturnType<typeof createServiceClient>,
  identityHash: string,
  textLength: number,
) {
  if (textLength > trialMaxCharacters) {
    return {
      body: { error: `Trial text exceeds ${trialMaxCharacters} characters.` },
    };
  }

  const dailyUsage = await loadUsageWindow(client, "identity_hash", identityHash, minutesAgo(24 * 60));
  if (dailyUsage.count >= trialDailyLimit) {
    return {
      body: { error: "Trial daily limit reached.", retry_after_seconds: secondsUntilTomorrowUTC() },
    };
  }

  return null;
}

async function enforcePaidLimits(
  client: ReturnType<typeof createServiceClient>,
  licenseHash: string,
  textLength: number,
) {
  if (textLength > paidMaxCharacters) {
    return {
      body: { error: `Request exceeds ${paidMaxCharacters} characters.` },
    };
  }

  const burstUsage = await loadUsageWindow(client, "license_hash", licenseHash, minutesAgo(10));
  if (burstUsage.count >= paidBurstLimit) {
    return {
      body: { error: "Too many requests in a short period.", retry_after_seconds: 600 },
    };
  }

  const dailyUsage = await loadUsageWindow(client, "license_hash", licenseHash, minutesAgo(24 * 60));
  if (dailyUsage.count >= paidDailyLimit || dailyUsage.characters >= paidDailyCharacterLimit) {
    return {
      body: { error: "Daily fair-use limit reached.", retry_after_seconds: secondsUntilTomorrowUTC() },
    };
  }

  return null;
}

async function loadUsageWindow(
  client: ReturnType<typeof createServiceClient>,
  column: "identity_hash" | "license_hash",
  value: string,
  sinceISO: string,
) {
  let query = client
    .from("translation_usage_events")
    .select("char_count")
    .gte("created_at", sinceISO);

  query = column === "identity_hash"
    ? query.eq("identity_hash", value)
    : query.eq("license_hash", value);

  const { data, error } = await query;
  if (error) {
    throw new Error(error.message);
  }

  const rows = data ?? [];
  return {
    count: rows.length,
    characters: rows.reduce((sum, row) => sum + Number(row.char_count ?? 0), 0),
  };
}

async function recordUsage(
  client: ReturnType<typeof createServiceClient>,
  identityHash: string,
  plan: AccessPlan,
  charCount: number,
  model: string,
) {
  const { error } = await client.from("translation_usage_events").insert({
    identity_hash: identityHash,
    license_hash: plan.licenseHash,
    plan: plan.plan,
    char_count: charCount,
    model,
  });

  if (error) {
    throw new Error(error.message);
  }
}

function minutesAgo(minutes: number): string {
  return new Date(Date.now() - minutes * 60_000).toISOString();
}

function secondsUntilTomorrowUTC(): number {
  const now = new Date();
  const tomorrow = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1);
  return Math.max(60, Math.floor((tomorrow - now.getTime()) / 1000));
}

function readString(body: object, key: string): string | null {
  const value = body[key as keyof typeof body];
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function readOptionalString(body: object, key: string): string | null {
  const value = body[key as keyof typeof body];
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function readOptionalBoolean(body: object, key: string): boolean | null {
  const value = body[key as keyof typeof body];
  return typeof value === "boolean" ? value : null;
}
