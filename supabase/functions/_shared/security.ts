const encoder = new TextEncoder();

export async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(input));
  const bytes = new Uint8Array(digest);
  return Array.from(bytes).map((value) => value.toString(16).padStart(2, "0")).join("");
}

export async function hmacSha256Hex(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(payload));
  const bytes = new Uint8Array(signature);
  return Array.from(bytes).map((value) => value.toString(16).padStart(2, "0")).join("");
}

export function secureCompare(left: string, right: string): boolean {
  if (left.length !== right.length) {
    return false;
  }

  let result = 0;
  for (let index = 0; index < left.length; index += 1) {
    result |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return result === 0;
}

export function randomDigits(length: number): string {
  const values = crypto.getRandomValues(new Uint32Array(length));
  return Array.from(values)
    .map((value) => String(value % 10))
    .join("");
}

export function randomToken(bytes = 32): string {
  const raw = crypto.getRandomValues(new Uint8Array(bytes));
  let token = "";
  for (const value of raw) {
    token += value.toString(16).padStart(2, "0");
  }
  return token;
}
