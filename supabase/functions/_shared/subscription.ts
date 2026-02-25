export type AppSubscriptionStatus = "trial" | "active" | "past_due" | "canceled" | "expired";

export function normalizePaddleSubscriptionStatus(rawStatus: string | null | undefined): AppSubscriptionStatus {
  const status = (rawStatus ?? "").toLowerCase();

  if (status === "active") {
    return "active";
  }
  if (status === "trialing") {
    return "trial";
  }
  if (status === "past_due") {
    return "past_due";
  }
  if (status === "paused") {
    return "past_due";
  }
  if (status === "canceled") {
    return "canceled";
  }
  return "expired";
}
