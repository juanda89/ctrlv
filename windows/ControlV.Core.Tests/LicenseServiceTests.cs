using ControlV.Core;
using ControlV.Core.Models;
using Xunit;

namespace ControlV.Core.Tests;

public class LicenseServiceTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1_700_000_000);

    private static LicenseService Make(MockAuthClient client, IAccountStore? store = null, IKeyValueStore? kv = null, DateTimeOffset? now = null)
        => new(client, store ?? new InMemoryAccountStore(), kv ?? new InMemoryKeyValueStore(), _ => { }, () => now ?? Now);

    [Fact]
    public async Task RequestMagicCode_NormalizesEmail_AndPersistsLastSignInEmail()
    {
        var client = new MockAuthClient();
        var kv = new InMemoryKeyValueStore();
        var service = Make(client, kv: kv);

        var ok = await service.RequestMagicCodeAsync(" User@Example.com ");

        Assert.True(ok);
        Assert.Equal("user@example.com", service.PendingMagicCodeEmail);
        Assert.Equal(new[] { "user@example.com" }, client.RequestedEmails);
        Assert.Equal("user@example.com", Make(new MockAuthClient(), kv: kv).LastSignInEmail);
    }

    [Fact]
    public async Task RequestMagicCode_RejectsInvalidEmail()
    {
        var client = new MockAuthClient();
        var service = Make(client);
        Assert.False(await service.RequestMagicCodeAsync("not-an-email"));
        Assert.Null(service.PendingMagicCodeEmail);
        Assert.Empty(client.RequestedEmails);
    }

    [Fact]
    public async Task VerifyMagicCode_SavesSession_AndBecomesActive()
    {
        var client = new MockAuthClient();
        var store = new InMemoryAccountStore();
        var service = Make(client, store);

        await service.RequestMagicCodeAsync("user@example.com");
        var ok = await service.VerifyMagicCodeAsync("123456");

        Assert.True(ok);
        Assert.Null(service.PendingMagicCodeEmail);
        Assert.Equal("token-xyz", store.Read()!.SessionToken);
        var active = Assert.IsType<LicenseState.Active>(service.State);
        Assert.Equal("Pro", active.PlanName);
        Assert.False(active.IsOfflineGrace);
    }

    [Fact]
    public async Task VerifyMagicCode_StaysOnTrial_WhenServerSaysTrial()
    {
        var client = new MockAuthClient { StatusResult = () => new SubscriptionStatus(SubscriptionStatusValue.Trial, null, 7) };
        var service = Make(client);
        await service.RequestMagicCodeAsync("user@example.com");
        await service.VerifyMagicCodeAsync("123456");
        Assert.IsType<LicenseState.Trial>(service.State);
    }

    [Fact]
    public void LoadState_UsesOfflineGrace_WithinThirtyDays()
    {
        var store = new InMemoryAccountStore();
        store.Save(new StoredAccountRecord { Email = "u@x.com", SessionToken = "tok", SubscriptionStatus = "active", PlanName = "Pro", LastValidatedAt = Now.AddDays(-15) });
        var service = Make(new MockAuthClient(), store);
        var active = Assert.IsType<LicenseState.Active>(service.State);
        Assert.True(active.IsOfflineGrace);
    }

    [Fact]
    public void LoadState_FallsBackToTrialOrExpired_AfterThirtyDays()
    {
        var store = new InMemoryAccountStore();
        store.Save(new StoredAccountRecord { Email = "u@x.com", SessionToken = "tok", SubscriptionStatus = "active", PlanName = "Pro", LastValidatedAt = Now.AddDays(-31) });
        var service = Make(new MockAuthClient(), store);
        Assert.IsType<LicenseState.Trial>(service.State); // fresh install date → 14-day trial
    }

    [Fact]
    public async Task Refresh_On401_DeletesSession_AndReportsExpiredSession()
    {
        var store = new InMemoryAccountStore();
        store.Save(new StoredAccountRecord { Email = "u@x.com", SessionToken = "tok", SubscriptionStatus = "active", LastValidatedAt = Now.AddDays(-2) });
        var client = new MockAuthClient { StatusError = AuthException.Server(401, "Invalid session") };
        var service = Make(client, store);

        await service.RefreshSubscriptionStatusAsync(forceNetwork: true);

        Assert.Null(store.Read());
        Assert.Equal("Session expired. Please sign in again.", service.LastError);
        Assert.False(service.State is LicenseState.Active);
    }

    [Fact]
    public async Task Refresh_OnNetworkError_KeepsActive_WithinGrace()
    {
        var store = new InMemoryAccountStore();
        store.Save(new StoredAccountRecord { Email = "u@x.com", SessionToken = "tok", SubscriptionStatus = "active", PlanName = "Pro", LastValidatedAt = Now.AddDays(-3) });
        var client = new MockAuthClient { StatusError = new HttpRequestException("offline") };
        var service = Make(client, store);

        await service.RefreshSubscriptionStatusAsync(forceNetwork: true);

        var active = Assert.IsType<LicenseState.Active>(service.State);
        Assert.True(active.IsOfflineGrace);
    }

    [Fact]
    public async Task Refresh_SkipsNetwork_WhenRecentlyValidated()
    {
        var store = new InMemoryAccountStore();
        store.Save(new StoredAccountRecord { Email = "u@x.com", SessionToken = "tok", SubscriptionStatus = "active", PlanName = "Pro", LastValidatedAt = Now.AddHours(-1) });
        var client = new MockAuthClient { StatusError = new HttpRequestException("must not be called") };
        var service = Make(client, store);

        await service.RefreshSubscriptionStatusAsync(forceNetwork: false);

        var active = Assert.IsType<LicenseState.Active>(service.State);
        Assert.False(active.IsOfflineGrace);
    }

    [Fact]
    public void Trial_Expires_After14Days()
    {
        var kv = new InMemoryKeyValueStore();
        kv.SetString("installDate", Now.AddDays(-14).ToString("O"));
        var service = Make(new MockAuthClient(), kv: kv);
        Assert.IsType<LicenseState.Expired>(service.State);
        Assert.False(service.State.CanTranslate);
    }

    [Fact]
    public void SignOut_ClearsStore_KeepsLastSignInEmail()
    {
        var store = new InMemoryAccountStore();
        store.Save(new StoredAccountRecord { Email = "u@x.com", SessionToken = "tok", SubscriptionStatus = "active", LastValidatedAt = Now });
        var kv = new InMemoryKeyValueStore();
        kv.SetString("lastSignInEmail", "u@x.com");
        var service = Make(new MockAuthClient(), store, kv);

        service.SignOut();

        Assert.Null(store.Read());
        Assert.False(service.IsSignedIn);
        Assert.Equal("u@x.com", service.LastSignInEmail);
    }
}
