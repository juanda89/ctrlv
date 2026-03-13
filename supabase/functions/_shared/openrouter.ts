const defaultBaseURL = "https://openrouter.ai/api/v1";
const defaultModel = "moonshotai/kimi-k2.5";
const minCompletionTokens = 96;
const maxCompletionTokens = 4096;

export type OpenRouterResult = {
  translatedText: string;
  model: string;
};

export async function translateWithOpenRouter(text: string, systemPrompt: string): Promise<OpenRouterResult> {
  const apiKey = Deno.env.get("OPENROUTER_API_KEY");
  if (!apiKey) {
    throw new Error("Missing OPENROUTER_API_KEY");
  }

  const model = Deno.env.get("OPENROUTER_MODEL") ?? defaultModel;
  const referer = Deno.env.get("OPENROUTER_REFERER") ?? "https://control-v.info";
  const title = Deno.env.get("OPENROUTER_APP_NAME") ?? "ctrl+v";

  const response = await fetch(`${defaultBaseURL}/chat/completions`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": referer,
      "X-Title": title,
    },
    body: JSON.stringify({
      model,
      temperature: 0.1,
      max_tokens: estimateMaxTokens(text),
      reasoning: {
        effort: "none",
        exclude: true,
      },
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: text },
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

  return { translatedText, model };
}

export class OpenRouterRateLimitError extends Error {
  retryAfterSeconds: number | null;

  constructor(message: string, retryAfterSeconds: number | null) {
    super(message);
    this.name = "OpenRouterRateLimitError";
    this.retryAfterSeconds = retryAfterSeconds;
  }
}

function estimateMaxTokens(text: string): number {
  const estimated = Math.ceil(text.length / 3);
  return Math.max(minCompletionTokens, Math.min(maxCompletionTokens, estimated));
}

function extractContent(payload: unknown): string | null {
  if (!payload || typeof payload !== "object") return null;
  const choices = payload["choices"];
  if (!Array.isArray(choices) || choices.length === 0) return null;
  const message = choices[0]?.message;
  const content = message?.content;

  if (typeof content === "string" && content.trim().length > 0) {
    return content.trim();
  }

  if (Array.isArray(content)) {
    const text = content
      .map((part) => typeof part?.text === "string" ? part.text : "")
      .join("")
      .trim();
    return text.length > 0 ? text : null;
  }

  return null;
}

function errorMessage(payload: unknown): string | null {
  if (!payload || typeof payload !== "object") return null;
  const error = payload["error"];
  if (typeof error === "object" && error && typeof error["message"] === "string") {
    return error["message"];
  }
  return typeof payload["message"] === "string" ? payload["message"] : null;
}
