const defaultBaseURL = "https://openrouter.ai/api/v1";

// Default model chain: tried in order, fallback on transient errors and
// "model deprecated/unavailable" (4xx other than 429, plus 5xx and network).
const defaultModels = [
  "x-ai/grok-4.3", // Primary: cheap with prompt cache + reasoning disabled
  "moonshotai/kimi-k2.5", // Fallback 1: proven multilingual mid-tier
  "qwen/qwen3-235b-a22b-2507", // Fallback 2: ultra-cheap flagship multilingual
];

const minCompletionTokens = 96;
const maxCompletionTokens = 4096;

export type OpenRouterResult = {
  translatedText: string;
  model: string;
  fallbackUsed: boolean;
};

export async function translateWithOpenRouter(text: string, systemPrompt: string): Promise<OpenRouterResult> {
  const apiKey = Deno.env.get("OPENROUTER_API_KEY");
  if (!apiKey) {
    throw new Error("Missing OPENROUTER_API_KEY");
  }

  const referer = Deno.env.get("OPENROUTER_REFERER") ?? "https://control-v.info";
  const title = Deno.env.get("OPENROUTER_APP_NAME") ?? "ctrl+v";
  const models = resolveModelChain();

  const errors: string[] = [];
  for (let i = 0; i < models.length; i += 1) {
    const model = models[i];
    try {
      const raw = await callOpenRouter({
        apiKey,
        referer,
        title,
        model,
        text,
        systemPrompt,
      });
      return {
        translatedText: sanitizeTranslation(raw, text),
        model,
        fallbackUsed: i > 0,
      };
    } catch (error) {
      if (error instanceof OpenRouterRateLimitError) {
        // Rate limits should propagate, not silently mask as a model
        // problem and burn budget on a different model.
        throw error;
      }
      const message = error instanceof Error ? error.message : String(error);
      errors.push(`${model}: ${message}`);
      // Try the next model in the chain
    }
  }

  throw new Error(`All OpenRouter models failed: ${errors.join(" | ")}`);
}

async function callOpenRouter(params: {
  apiKey: string;
  referer: string;
  title: string;
  model: string;
  text: string;
  systemPrompt: string;
}): Promise<string> {
  const response = await fetch(`${defaultBaseURL}/chat/completions`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${params.apiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": params.referer,
      "X-Title": params.title,
    },
    body: JSON.stringify({
      model: params.model,
      temperature: 0.1,
      max_tokens: estimateMaxTokens(params.text),
      reasoning: {
        effort: "none",
        exclude: true,
      },
      messages: [
        { role: "system", content: params.systemPrompt },
        { role: "user", content: params.text },
      ],
    }),
  });

  const payload = await response.json().catch(() => null);
  if (response.status === 429) {
    const retryAfter = Number(response.headers.get("retry-after") ?? "0") || null;
    const reason = errorMessage(payload) ?? "OpenRouter rate limited";
    throw new OpenRouterRateLimitError(reason, retryAfter);
  }

  if (!response.ok) {
    throw new Error(errorMessage(payload) ?? `OpenRouter failed with ${response.status}`);
  }

  const translatedText = extractContent(payload);
  if (!translatedText) {
    throw new Error("OpenRouter returned an empty translation");
  }
  return translatedText;
}

/**
 * Resolution order:
 *   1. OPENROUTER_MODELS env var (comma-separated chain)
 *   2. OPENROUTER_MODEL env var (single primary, no fallback) — back-compat
 *   3. Hardcoded defaultModels chain
 */
function resolveModelChain(): string[] {
  const chain = Deno.env.get("OPENROUTER_MODELS");
  if (chain && chain.trim()) {
    const list = chain.split(",")
      .map((entry) => entry.trim())
      .filter((entry) => entry.length > 0);
    if (list.length > 0) return list;
  }

  const single = Deno.env.get("OPENROUTER_MODEL");
  if (single && single.trim()) {
    return [single.trim()];
  }

  return [...defaultModels];
}

export class OpenRouterRateLimitError extends Error {
  retryAfterSeconds: number | null;

  constructor(message: string, retryAfterSeconds: number | null) {
    super(message);
    this.name = "OpenRouterRateLimitError";
    this.retryAfterSeconds = retryAfterSeconds;
  }
}

/**
 * Hard validation: certain "AI tell" characters are stripped from the output
 * UNLESS the user explicitly typed them in the source. This is the safety net
 * behind the prompt-level instruction — models drift, this guarantees the rule.
 *
 * Characters covered:
 *   ¿ — opening Spanish question mark (closing ? is kept)
 *   ¡ — opening Spanish exclamation mark (closing ! is kept)
 *   — — em-dash (replaced with comma if surrounded by spaces, else dropped)
 *   – — en-dash (same handling as em-dash)
 *
 * Normal hyphen `-` is NEVER touched (used for compounds, ranges, etc.).
 */
export function sanitizeTranslation(translation: string, source: string): string {
  let result = translation;

  if (!source.includes("¿")) {
    result = result.split("¿").join("");
  }
  if (!source.includes("¡")) {
    result = result.split("¡").join("");
  }
  if (!source.includes("—")) {
    // " — " (with spaces) usually marks a parenthetical/break; replace with comma.
    // Bare "—" (no spaces) is rare; just drop it.
    result = result.split(" — ").join(", ").split("—").join("");
  }
  if (!source.includes("–")) {
    result = result.split(" – ").join(", ").split("–").join("");
  }

  // Collapse runs of spaces produced by the substitutions, but keep newlines.
  result = result.replace(/[ \t]{2,}/g, " ").trim();
  return result;
}

function estimateMaxTokens(text: string): number {
  const estimated = Math.ceil(text.length / 3);
  return Math.max(minCompletionTokens, Math.min(maxCompletionTokens, estimated));
}

function extractContent(payload: unknown): string | null {
  if (!payload || typeof payload !== "object") return null;
  const choices = (payload as Record<string, unknown>)["choices"];
  if (!Array.isArray(choices) || choices.length === 0) return null;
  const message = (choices[0] as Record<string, unknown> | undefined)?.["message"] as Record<string, unknown> | undefined;
  const content = message?.["content"];

  if (typeof content === "string" && content.trim().length > 0) {
    return content.trim();
  }

  if (Array.isArray(content)) {
    const text = content
      .map((part) => typeof (part as Record<string, unknown>)?.["text"] === "string" ? (part as Record<string, unknown>)["text"] as string : "")
      .join("")
      .trim();
    return text.length > 0 ? text : null;
  }

  return null;
}

function errorMessage(payload: unknown): string | null {
  if (!payload || typeof payload !== "object") return null;
  const error = (payload as Record<string, unknown>)["error"];
  if (typeof error === "object" && error && typeof (error as Record<string, unknown>)["message"] === "string") {
    return (error as Record<string, unknown>)["message"] as string;
  }
  return typeof (payload as Record<string, unknown>)["message"] === "string"
    ? (payload as Record<string, unknown>)["message"] as string
    : null;
}
