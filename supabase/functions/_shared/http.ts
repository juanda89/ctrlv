const ALLOWED_ORIGINS = [
  "https://control-v.info",
  "https://www.control-v.info",
];

function buildCorsHeaders(req?: Request): Record<string, string> {
  const origin = req?.headers.get("origin");
  let allowedOrigin = "*";
  if (origin) {
    allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : "";
  }
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, paddle-signature",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

export function json(data: unknown, status = 200, req?: Request): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...buildCorsHeaders(req),
      "Content-Type": "application/json",
    },
  });
}

export function methodNotAllowed(req?: Request): Response {
  return json({ error: "Method not allowed" }, 405, req);
}

export function handlePreflight(req: Request): Response | null {
  if (req.method !== "OPTIONS") {
    return null;
  }

  return new Response("ok", { headers: buildCorsHeaders(req) });
}

/// Browsers may send cross-origin POSTs without a preflight when the body is
/// text/plain or form-encoded; requiring JSON forces the preflight, which the
/// origin allowlist above then blocks. Every first-party client sends JSON.
export function requireJSON(req: Request): Response | null {
  const type = req.headers.get("content-type") ?? "";
  if (type.toLowerCase().startsWith("application/json")) return null;
  return json({ error: "Content-Type must be application/json" }, 415, req);
}

/// Best-effort client address for abuse caps (never stored raw: callers hash
/// it with the server pepper). Null when the platform did not set a header.
export function clientIP(req: Request): string | null {
  const forwarded = req.headers.get("x-forwarded-for");
  const first = forwarded?.split(",")[0]?.trim();
  if (first) return first;
  const direct = req.headers.get("cf-connecting-ip")?.trim();
  return direct && direct.length > 0 ? direct : null;
}
