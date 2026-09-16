// App Store Server verification helpers (StoreKit 2 signed transactions and
// App Store Server Notifications V2). Uses Apple's official library so the
// x5c certificate chain is validated against Apple Root CA - G3 pinned below.
import {
  Environment,
  SignedDataVerifier,
  VerificationException,
  type JWSTransactionDecodedPayload,
  type JWSRenewalInfoDecodedPayload,
  type ResponseBodyV2DecodedPayload,
} from "npm:@apple/app-store-server-library@1.5.0";
import { Buffer } from "node:buffer";

export { VerificationException };
export type { JWSTransactionDecodedPayload, JWSRenewalInfoDecodedPayload, ResponseBodyV2DecodedPayload };

/// Apple Root CA - G3 (DER), fetched from https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
const appleRootCaG3Base64 = "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";

export const bundleId = Deno.env.get("APPSTORE_BUNDLE_ID") ?? "info.controlv.ios";
/// Numeric App Apple ID from App Store Connect; required for PRODUCTION verification.
const appAppleId = Number(Deno.env.get("APPSTORE_APP_APPLE_ID") ?? "") || undefined;

function rootCa(): Buffer {
  return Buffer.from(appleRootCaG3Base64, "base64");
}

/// Reads the (unverified) environment claim so we verify with the matching
/// verifier. The signature check afterwards makes lying about it pointless.
export function peekEnvironment(jws: string): Environment {
  try {
    const payload = jws.split(".")[1] ?? "";
    const json = JSON.parse(atob(payload.replace(/-/g, "+").replace(/_/g, "/")));
    return json.environment === "Production" ? Environment.PRODUCTION : Environment.SANDBOX;
  } catch {
    return Environment.SANDBOX;
  }
}

export function verifierFor(env: Environment): SignedDataVerifier {
  if (env === Environment.PRODUCTION && !appAppleId) {
    throw new Error("APPSTORE_APP_APPLE_ID is required to verify production transactions");
  }
  // Online OCSP checks disabled: the edge runtime has no long-lived connections and
  // Apple's chain validation is fully offline against the pinned root.
  return new SignedDataVerifier([rootCa()], false, env, bundleId, appAppleId);
}

export async function verifyTransaction(jws: string): Promise<JWSTransactionDecodedPayload> {
  return await verifierFor(peekEnvironment(jws)).verifyAndDecodeTransaction(jws);
}

export async function verifyNotification(signedPayload: string): Promise<ResponseBodyV2DecodedPayload> {
  return await verifierFor(peekEnvironment(signedPayload)).verifyAndDecodeNotification(signedPayload);
}

export async function verifyRenewalInfo(jws: string): Promise<JWSRenewalInfoDecodedPayload> {
  return await verifierFor(peekEnvironment(jws)).verifyAndDecodeRenewalInfo(jws);
}

/// Our status vocabulary: 'trial' | 'active' | 'past_due' | 'canceled' | 'expired'.
export function statusFromTransaction(tx: JWSTransactionDecodedPayload, now = Date.now()): string {
  if (tx.revocationDate) return "canceled";
  if (tx.expiresDate && tx.expiresDate > now) return "active";
  return "expired";
}

export function isoOrNull(ms?: number): string | null {
  return typeof ms === "number" && Number.isFinite(ms) ? new Date(ms).toISOString() : null;
}
