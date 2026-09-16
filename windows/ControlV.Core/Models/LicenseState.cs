namespace ControlV.Core.Models;

/// Mirrors Swift `LicenseState` (an enum with payloads) as a closed record hierarchy.
public abstract record LicenseState
{
    public sealed record Checking : LicenseState;
    public sealed record Trial(int DaysRemaining) : LicenseState;
    public sealed record Expired : LicenseState;
    public sealed record Active(string? PlanName, DateTimeOffset ValidatedAt, bool IsOfflineGrace) : LicenseState;
    public sealed record Invalid(string Reason) : LicenseState;

    public bool CanTranslate => this is Trial or Active;

    public string StatusText => this switch
    {
        Checking => "Checking license",
        Trial t => $"Trial: {t.DaysRemaining} days remaining",
        Expired => "Trial expired",
        Active a => (string.IsNullOrEmpty(a.PlanName) ? "Active license" : $"Active: {a.PlanName}") + (a.IsOfflineGrace ? " (offline mode)" : ""),
        Invalid i => $"Invalid license: {i.Reason}",
        _ => "Unknown",
    };
}
