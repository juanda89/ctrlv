import { clientIP, handlePreflight, json, methodNotAllowed, requireJSON } from "../_shared/http.ts";
import { FidelityError, OpenRouterRateLimitError, isUntranslatable, resolveModelChain, translateWithOpenRouter, warmOpenRouter } from "../_shared/openrouter.ts";
import { sha256Hex } from "../_shared/security.ts";
import { createServiceClient } from "../_shared/supabase.ts";
import { sessionLifetimeDays } from "../_shared/session.ts";
import { type AccessDecision, type AccessLimits, type AccessPlan, decideAccess, parseAccessSnapshot } from "../_shared/access.ts";

const limits: AccessLimits = {
  trialDays: Number(Deno.env.get("TRIAL_DAYS") ?? "14"),
  trialDailyLimit: Number(Deno.env.get("TRIAL_DAILY_TRANSLATION_LIMIT") ?? "50"),
  trialMaxCharacters: Number(Deno.env.get("TRIAL_MAX_CHARACTERS") ?? "3000"),
  paidBurstLimit: Number(Deno.env.get("PAID_REQUESTS_PER_10_MIN") ?? "80"),
  paidDailyLimit: Number(Deno.env.get("PAID_REQUESTS_PER_DAY") ?? "1500"),
  paidDailyCharacterLimit: Number(Deno.env.get("PAID_CHARACTERS_PER_DAY") ?? "1200000"),
  paidMaxCharacters: Number(Deno.env.get("PAID_MAX_CHARACTERS") ?? "12000"),
};
/// The client's prompt is ~3.5 KB plus the user's custom tone; anything far
/// beyond that is someone using the endpoint as a general LLM proxy.
const maxSystemPromptChars = Number(Deno.env.get("MAX_SYSTEM_PROMPT_CHARACTERS") ?? "16000");
/// New trial identities one network may create per day (see translate_begin).
const newIdentitiesPerNetworkPerDay = Number(Deno.env.get("NEW_IDENTITIES_PER_IP_PER_DAY") ?? "50");
/// Per-phase timings and raw error details are returned only to callers that
/// present this secret in X-Ctrlv-Debug. Unset → never.
const debugToken = Deno.env.get("CTRLV_DEBUG_TOKEN")?.trim() || null;

type TranslateRequest = {
  text: string;
  systemPrompt: string;
  installID: string;
  sessionToken?: string | null;
  warmupOnly?: boolean;
};

/// Supabase's Edge Runtime keeps the isolate alive for promises handed to
/// EdgeRuntime.waitUntil after the response has been sent.
declare const EdgeRuntime: { waitUntil?: (promise: Promise<unknown>) => void } | undefined;

// Request timeline (the whole point is that nothing waits on anything it
// does not need):
//   hash ids ─┬─ model call (speculative, abortable) ──────────┐
//             └─ translate_begin RPC (one DB round trip) ─ verdict ┴─ response
//                                                   usage insert → after the response
Deno.serve(async (req) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed(req);

  const notJSON = requireJSON(req);
  if (notJSON) return notJSON;
  const debug = debugToken !== null && req.headers.get("X-Ctrlv-Debug") === debugToken;

  let abortSpeculative: (() => void) | null = null;
  try {
    const body = await req.json();
    const parsed = parseRequest(body);
    if (!parsed.ok) {
      return json({ error: parsed.error }, 400, req);
    }
    const request = parsed.value;
    // Nobody may send more than the paid ceiling; refusing before any work
    // keeps oversized bodies from reaching the DB or the model.
    if (request.text.length > limits.paidMaxCharacters) {
      return json({ error: `Request exceeds ${limits.paidMaxCharacters} characters.` }, 429, req);
    }

    const startedAt = performance.now();
    const client = createServiceClient();
    const pepper = Deno.env.get("MAGIC_CODE_PEPPER") ?? "";
    const ip = clientIP(req);
    const [identityHash, tokenHash, ipHash] = await Promise.all([
      sha256Hex(request.installID),
      hashSessionToken(request.sessionToken),
      ip ? sha256Hex(`ip:${ip}:${pepper}`) : Promise.resolve(null),
    ]);

    // Warmup: keeps the isolate and the TLS connection to OpenRouter hot
    // without a completion. The access check still runs so an expired or
    // blocked identity cannot use warmups as a free ping, and the client's
    // text is ignored (it used to be forwarded to the model unmetered).
    if (request.warmupOnly) {
      const decision = await beginAccess(client, identityHash, tokenHash, ipHash, 4, false);
      if (!decision.ok) {
        return json(decision.rejection.body, decision.rejection.status, req);
      }
      await warmOpenRouter();
      return json({ warmed: true, model: resolveModelChain()[0] ?? null }, 200, req);
    }

    // Nothing to translate (bare URL, bare email, no letters): echoed back
    // unchanged after the access check. Skips the LLM entirely — free,
    // unmetered, and immune to the model replying "I can't open that link".
    const untranslatable = isUntranslatable(request.text);

    // Speculative model call: started before we know whether the request is
    // allowed, so the DB round trip overlaps the model's latency instead of
    // preceding it. Rejections abort it, but an abort does not stop a
    // non-streaming completion upstream, so the speculation is bounded to
    // trial-sized texts: nothing a caller sends (a bogus session token, a
    // rotated installID) can start a paid-sized completion before the access
    // check passes. Longer texts wait for the RPC (~60 ms).
    const abort = new AbortController();
    abortSpeculative = () => abort.abort();
    const mayTranslate = !untranslatable && request.text.length <= limits.trialMaxCharacters;
    const speculative = mayTranslate
      ? translateWithOpenRouter(request.text, request.systemPrompt, { signal: abort.signal })
      : null;
    speculative?.catch(() => {}); // surfaced on the await below, never as an unhandled rejection

    const rpcStartedAt = performance.now();
    const decision = await beginAccess(client, identityHash, tokenHash, ipHash, request.text.length, !untranslatable);
    const rpcMs = Math.round(performance.now() - rpcStartedAt);
    if (!decision.ok) {
      abort.abort();
      return json(decision.rejection.body, decision.rejection.status, req);
    }
    const plan = decision.plan;

    if (untranslatable) {
      return json({ translatedText: request.text, model: "passthrough", plan: plan.plan }, 200, req);
    }

    const result = await (speculative ?? translateWithOpenRouter(request.text, request.systemPrompt));
    const modelMs = Math.round(performance.now() - startedAt);
    await inBackground(recordUsage(client, identityHash, plan, request.text.length, result.model));

    // Per-phase timings only for callers that opt in: `modelMs` is measured
    // from the request start because the model call overlaps the RPC.
    const timings = debug ? { rpcMs, modelMs, provider: result.provider, costUSD: result.costUSD } : undefined;
    return json({
      translatedText: result.translatedText,
      model: result.model,
      retried: result.retried,
      plan: plan.plan,
      ...(timings ? { timings } : {}),
    }, 200, req);
  } catch (error) {
    abortSpeculative?.();

    if (error instanceof OpenRouterRateLimitError) {
      return json(
        { error: "Translation service is busy. Please try again shortly.", retry_after_seconds: error.retryAfterSeconds },
        429, req,
      );
    }

    // The model answered the text instead of translating it, twice. A wrong
    // message must never be pasted over the user's selection: fail loudly
    // with a hint the popover shows verbatim. 422 keeps it apart from the
    // generic 500 in logs and lets the client stay unchanged.
    if (error instanceof FidelityError) {
      console.warn(`[fidelity] rejected: ${error.issues.join(",")}`);
      return json(
        { error: "The text could not be translated faithfully. Select only the text to translate and try again.", fidelity: error.issues },
        422, req,
      );
    }

    // Raw error detail only for holders of the debug secret.
    if (debug) {
      const detail = error instanceof Error ? error.message : String(error);
      return json({ error: "Translation failed", detail }, 500, req);
    }

    return json({ error: "Translation failed. Please try again." }, 500, req);
  }
});

/// Session tokens are stored hashed with the magic-code pepper. Without the
/// pepper no session can validate, which degrades to the trial plan exactly
/// as before.
async function hashSessionToken(token: string | null | undefined): Promise<string | null> {
  const trimmed = token?.trim();
  if (!trimmed) return null;
  const pepper = Deno.env.get("MAGIC_CODE_PEPPER");
  if (!pepper) return null;
  return await sha256Hex(`${trimmed}:${pepper}`);
}

/// One round trip: identity upsert + sync, session lookup + sliding renewal,
/// subscription lookup and usage-window counts (see the translate_begin
/// migration). The verdict is computed here from the configured limits.
async function beginAccess(
  client: ReturnType<typeof createServiceClient>,
  identityHash: string,
  tokenHash: string | null,
  ipHash: string | null,
  textLength: number,
  enforceLimits: boolean,
): Promise<AccessDecision> {
  const { data, error } = await client.rpc("translate_begin", {
    p_identity_hash: identityHash,
    p_token_hash: tokenHash,
    p_session_lifetime_days: sessionLifetimeDays,
    p_ip_hash: ipHash,
    p_new_identity_limit: newIdentitiesPerNetworkPerDay,
  });
  if (error) {
    throw new Error(error.message);
  }
  if (data && typeof data === "object" && "blocked" in (data as Record<string, unknown>)) {
    // A script rotating installIDs from one network: no new trial for it.
    return {
      ok: false,
      rejection: { status: 429, body: { error: "Too many new devices from this network today. Sign in to continue.", retry_after_seconds: 3600 } },
    };
  }
  return decideAccess(parseAccessSnapshot(data), textLength, limits, { enforceLimits });
}

/// Runs a task after the response is sent when the runtime supports it. A
/// failed usage insert is logged, never turned into an error for a
/// translation that already succeeded.
function inBackground(task: Promise<unknown>): Promise<void> {
  const guarded = task.then(() => {}, (error: unknown) => {
    console.error(`[usage] ${error instanceof Error ? error.message : String(error)}`);
  });
  if (typeof EdgeRuntime !== "undefined" && typeof EdgeRuntime?.waitUntil === "function") {
    EdgeRuntime.waitUntil(guarded);
    return Promise.resolve();
  }
  return guarded;
}

function parseRequest(body: unknown): { ok: true; value: TranslateRequest } | { ok: false; error: string } {
  if (!body || typeof body !== "object") {
    return { ok: false, error: "Invalid request body" };
  }

  // `text` is read raw: the sanitizer restores the source's exact leading /
  // trailing whitespace, so trimming here would silently drop a selected
  // trailing newline and make the pasted paragraph merge with the next one.
  const text = readRawString(body, "text");
  const systemPrompt = readString(body, "systemPrompt");
  const installID = readString(body, "installID");

  if (!text || !systemPrompt || !installID) {
    return { ok: false, error: "Missing text, systemPrompt or installID" };
  }
  if (systemPrompt.length > maxSystemPromptChars) {
    return { ok: false, error: "System prompt too long" };
  }
  if (installID.length > 128) {
    return { ok: false, error: "Invalid installID" };
  }

  return {
    ok: true,
    value: {
      text,
      systemPrompt,
      installID,
      sessionToken: readOptionalString(body, "sessionToken"),
      warmupOnly: readOptionalBoolean(body, "warmupOnly") ?? false,
    },
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
    license_hash: plan.accountHash,
    plan: plan.plan,
    char_count: charCount,
    model,
  });

  if (error) {
    throw new Error(error.message);
  }
}

function readString(body: object, key: string): string | null {
  const value = (body as Record<string, unknown>)[key];
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/// Like readString but returns the value verbatim (only the emptiness check
/// uses trim). Use for user content whose whitespace is meaningful.
function readRawString(body: object, key: string): string | null {
  const value = (body as Record<string, unknown>)[key];
  if (typeof value !== "string") return null;
  return value.trim().length > 0 ? value : null;
}

function readOptionalString(body: object, key: string): string | null {
  const value = (body as Record<string, unknown>)[key];
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function readOptionalBoolean(body: object, key: string): boolean | null {
  const value = (body as Record<string, unknown>)[key];
  return typeof value === "boolean" ? value : null;
}
