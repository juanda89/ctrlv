using ControlV.Core.Models;

namespace ControlV.Core;

/// Port of the Mac `LicenseService`: trial by install date, magic-code sign-in,
/// subscription refresh with a 24h revalidation window, 30-day offline grace,
/// 401 → signed out. Time and I/O are injectable for tests.
public sealed class LicenseService
{
    public const int TrialDays = 14;
    public static readonly TimeSpan TranslationRevalidation = TimeSpan.FromHours(24);
    public static readonly TimeSpan OfflineGrace = TimeSpan.FromDays(30);

    private const string InstallDateKey = "installDate";
    private const string LastSignInEmailKey = "lastSignInEmail";

    private readonly IMagicCodeAuthClient _client;
    private readonly IAccountStore _store;
    private readonly IKeyValueStore _kv;
    private readonly Func<DateTimeOffset> _now;
    private readonly Action<Uri> _openUrl;
    private LicenseState _state = new LicenseState.Checking();

    public event Action<LicenseState>? StateChanged;

    public LicenseService(IMagicCodeAuthClient client, IAccountStore store, IKeyValueStore kv, Action<Uri> openUrl, Func<DateTimeOffset>? now = null)
    {
        _client = client;
        _store = store;
        _kv = kv;
        _openUrl = openUrl;
        _now = now ?? (() => DateTimeOffset.Now);
        LastSignInEmail = _kv.GetString(LastSignInEmailKey);
        LoadState();
    }

    public LicenseState State
    {
        get => _state;
        private set { if (_state != value) { _state = value; StateChanged?.Invoke(value); } }
    }

    public bool IsLoading { get; private set; }
    public string? LastError { get; private set; }
    public string? PendingMagicCodeEmail { get; private set; }
    public string? LastSignInEmail { get; private set; }
    public string? StoredSessionToken => _store.Read()?.SessionToken;
    public string? StoredEmail => _store.Read()?.Email;
    public bool IsSignedIn => !string.IsNullOrEmpty(StoredSessionToken);

    public void LoadState()
    {
        var record = _store.Read();
        if (record is null || string.IsNullOrEmpty(record.SessionToken)) { State = LocalTrialOrExpired(); return; }
        if (IsActiveWithinGrace(record, out var validatedAt))
        {
            State = new LicenseState.Active(record.PlanName, validatedAt, IsOfflineGrace: true);
            return;
        }
        State = LocalTrialOrExpired();
    }

    public async Task<bool> RequestMagicCodeAsync(string email, CancellationToken ct = default)
    {
        var normalized = email.Trim().ToLowerInvariant();
        if (normalized.Length == 0 || !normalized.Contains('@')) { LastError = "Enter a valid email"; return false; }
        IsLoading = true;
        try
        {
            await _client.RequestMagicCodeAsync(normalized, ct);
            PendingMagicCodeEmail = normalized;
            LastSignInEmail = normalized;
            _kv.SetString(LastSignInEmailKey, normalized);
            LastError = null;
            return true;
        }
        catch (Exception e) when (e is AuthException or HttpRequestException) { LastError = e.Message; return false; }
        finally { IsLoading = false; }
    }

    public async Task<bool> VerifyMagicCodeAsync(string code, CancellationToken ct = default)
    {
        var normalized = code.Trim();
        if (PendingMagicCodeEmail is not string email || normalized.Length == 0) { LastError = "Enter the 6-digit code"; return false; }
        IsLoading = true;
        try
        {
            var token = await _client.VerifyMagicCodeAsync(email, normalized, ct);
            _store.Save(new StoredAccountRecord { Email = email, SessionToken = token });
            PendingMagicCodeEmail = null;
            LastError = null;
        }
        catch (Exception e) when (e is AuthException or HttpRequestException) { LastError = e.Message; return false; }
        finally { IsLoading = false; }

        await RefreshSubscriptionStatusAsync(forceNetwork: true, ct);
        return true;
    }

    public async Task RefreshSubscriptionStatusAsync(bool forceNetwork = false, CancellationToken ct = default)
    {
        if (IsLoading) return;
        var record = _store.Read();
        if (record is null || string.IsNullOrEmpty(record.SessionToken)) { State = LocalTrialOrExpired(); return; }

        var skipNetwork = !forceNetwork
            && string.Equals(record.SubscriptionStatus, "active", StringComparison.OrdinalIgnoreCase)
            && record.LastValidatedAt is DateTimeOffset last && _now() - last < TranslationRevalidation;
        if (skipNetwork)
        {
            State = new LicenseState.Active(record.PlanName, record.LastValidatedAt!.Value, IsOfflineGrace: false);
            return;
        }

        IsLoading = true;
        try
        {
            var status = await _client.RefreshSubscriptionStatusAsync(record.SessionToken, ct);
            record.SubscriptionStatus = status.Status.RawValue();
            record.PlanName = status.PlanName ?? record.PlanName;
            record.LastValidatedAt = _now();
            _store.Save(record);

            State = status.Status switch
            {
                SubscriptionStatusValue.Active => new LicenseState.Active(record.PlanName, record.LastValidatedAt.Value, false),
                SubscriptionStatusValue.PastDue => new LicenseState.Invalid("Payment past due. Please update your card."),
                _ => LocalTrialOrExpired(),
            };
            if (status.Status == SubscriptionStatusValue.Active) LastError = null;
        }
        catch (AuthException e) when (e.ErrorKind == AuthException.Kind.Server && e.StatusCode == 401)
        {
            _store.Delete();
            State = LocalTrialOrExpired();
            LastError = "Session expired. Please sign in again.";
        }
        catch (Exception e) when (e is AuthException or HttpRequestException or TaskCanceledException)
        {
            ApplyOfflineFallback(record, e.Message);
        }
        finally { IsLoading = false; }
    }

    public async Task OpenUpgradeAsync(CancellationToken ct = default)
    {
        if (StoredSessionToken is not string token) { LastError = "Sign in first to subscribe"; return; }
        await RefreshSubscriptionStatusAsync(forceNetwork: true, ct);
        if (State is LicenseState.Active) { LastError = null; return; }
        await OpenAsync(() => _client.CreateCheckoutSessionAsync(token, ct));
    }

    public async Task OpenManageSubscriptionAsync(CancellationToken ct = default)
    {
        if (StoredSessionToken is not string token) return;
        await OpenAsync(() => _client.CreatePortalSessionAsync(token, ct));
    }

    public void CancelPendingSignIn() { PendingMagicCodeEmail = null; LastError = null; }

    public void SignOut()
    {
        _store.Delete();
        PendingMagicCodeEmail = null;
        LastError = null;
        LoadState();
    }

    private async Task OpenAsync(Func<Task<Uri>> create)
    {
        IsLoading = true;
        try { _openUrl(await create()); }
        catch (Exception e) when (e is AuthException or HttpRequestException) { LastError = e.Message; }
        finally { IsLoading = false; }
    }

    private void ApplyOfflineFallback(StoredAccountRecord record, string errorMessage)
    {
        if (IsActiveWithinGrace(record, out var validatedAt))
        {
            State = new LicenseState.Active(record.PlanName, validatedAt, IsOfflineGrace: true);
            return;
        }
        LastError = errorMessage;
        State = LocalTrialOrExpired();
    }

    private bool IsActiveWithinGrace(StoredAccountRecord record, out DateTimeOffset validatedAt)
    {
        validatedAt = default;
        if (record.LastValidatedAt is not DateTimeOffset last) return false;
        if (!string.Equals(record.SubscriptionStatus, "active", StringComparison.OrdinalIgnoreCase)) return false;
        if (_now() - last > OfflineGrace) return false;
        validatedAt = last;
        return true;
    }

    private LicenseState LocalTrialOrExpired()
    {
        var installDate = StoredInstallDate();
        var daysSinceInstall = (int)Math.Floor((_now() - installDate).TotalDays);
        var remaining = Math.Max(0, TrialDays - daysSinceInstall);
        return remaining > 0 ? new LicenseState.Trial(remaining) : new LicenseState.Expired();
    }

    private DateTimeOffset StoredInstallDate()
    {
        if (DateTimeOffset.TryParse(_kv.GetString(InstallDateKey), null, System.Globalization.DateTimeStyles.RoundtripKind, out var saved)) return saved;
        var created = _now();
        _kv.SetString(InstallDateKey, created.ToString("O"));
        return created;
    }
}
