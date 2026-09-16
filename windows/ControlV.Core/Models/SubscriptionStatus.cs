using System.Text.Json.Serialization;

namespace ControlV.Core.Models;

public enum SubscriptionStatusValue { Trial, Active, PastDue, Canceled, Expired, Unknown }

public static class SubscriptionStatusValues
{
    /// Mirrors Swift `SubscriptionStatusValue(raw:)`.
    public static SubscriptionStatusValue Parse(string? raw) => raw?.ToLowerInvariant() switch
    {
        "active" => SubscriptionStatusValue.Active,
        "trial" or "trialing" => SubscriptionStatusValue.Trial,
        "past_due" => SubscriptionStatusValue.PastDue,
        "canceled" or "cancelled" => SubscriptionStatusValue.Canceled,
        "expired" => SubscriptionStatusValue.Expired,
        _ => SubscriptionStatusValue.Unknown,
    };

    public static string RawValue(this SubscriptionStatusValue value) => value switch
    {
        SubscriptionStatusValue.PastDue => "past_due",
        _ => value.ToString().ToLowerInvariant(),
    };

    public static bool CanTranslate(this SubscriptionStatusValue value) =>
        value is SubscriptionStatusValue.Active or SubscriptionStatusValue.Trial;
}

public sealed record SubscriptionStatus(SubscriptionStatusValue Status, string? PlanName, int? TrialDaysRemaining);

/// Persisted account record (encrypted at rest by the AccountStore implementation).
public sealed class StoredAccountRecord
{
    [JsonPropertyName("email")] public string Email { get; set; } = "";
    [JsonPropertyName("sessionToken")] public string SessionToken { get; set; } = "";
    [JsonPropertyName("subscriptionStatus")] public string? SubscriptionStatus { get; set; }
    [JsonPropertyName("planName")] public string? PlanName { get; set; }
    [JsonPropertyName("lastValidatedAt")] public DateTimeOffset? LastValidatedAt { get; set; }
}
