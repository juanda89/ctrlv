const ALLOWED_ORIGINS = [
  "https://control-v.info",
  "https://controlv.lemonsqueezy.com",
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
