const defaultBaseURL = "https://api.lemonsqueezy.com";

export type LemonValidation = {
  isActive: boolean;
  planName: string | null;
  instanceID: string | null;
  reason: string | null;
};

export async function validateLemonLicense(
  licenseKey: string,
  instanceID?: string | null,
): Promise<LemonValidation> {
  const baseURL = Deno.env.get("LEMON_LICENSE_API_BASE_URL") ?? defaultBaseURL;
  const body = new URLSearchParams({ license_key: licenseKey });
  if (instanceID) {
    body.set("instance_id", instanceID);
  }

  const response = await fetch(`${baseURL}/v1/licenses/validate`, {
    method: "POST",
    headers: {
      "Accept": "application/json",
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: body.toString(),
  });

  const payload = await parseJSON(response);
  const status = stringAt(payload, ["license_key", "status"]);
  const isActive = Boolean(payload?.valid) || status === "active";

  return {
    isActive,
    planName: stringAt(payload, ["license_key", "variant_name"]),
    instanceID: stringAt(payload, ["instance", "id"]) ?? instanceID ?? null,
    reason: stringAt(payload, ["error"]),
  };
}

function stringAt(payload: unknown, path: string[]): string | null {
  let current = payload;
  for (const segment of path) {
    if (!current || typeof current !== "object" || !(segment in current)) {
      return null;
    }
    current = current[segment as keyof typeof current];
  }
  return typeof current === "string" && current.length > 0 ? current : null;
}

async function parseJSON(response: Response): Promise<Record<string, unknown> | null> {
  const text = await response.text();
  if (!text) return null;
  try {
    return JSON.parse(text) as Record<string, unknown>;
  } catch {
    return null;
  }
}
