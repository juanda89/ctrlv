using System.Net;
using System.Text.Json;
using ControlV.Core;
using ControlV.Core.Models;
using Xunit;

namespace ControlV.Core.Tests;

public class MagicCodeAuthClientTests
{
    private static readonly Uri Base = new("https://api.example.com/");

    [Fact]
    public async Task RequestMagicCode_PostsEmailJson()
    {
        var stub = new StubHandler { Handler = (req, body) => (HttpStatusCode.OK, "{\"ok\":true}") };
        var client = new MagicCodeAuthClient(stub.Client(), Base);

        await client.RequestMagicCodeAsync("user@example.com");

        var (request, body) = Assert.Single(stub.Requests);
        Assert.Equal("/request-magic-code", request.RequestUri!.AbsolutePath);
        Assert.Equal("user@example.com", JsonDocument.Parse(body).RootElement.GetProperty("email").GetString());
    }

    [Fact]
    public async Task RefreshSubscriptionStatus_SendsBearer_AndDecodes()
    {
        var stub = new StubHandler { Handler = (req, _) =>
        {
            Assert.Equal("Bearer my-token", req.Headers.Authorization!.ToString());
            return (HttpStatusCode.OK, "{\"status\":\"active\",\"planName\":\"Pro\",\"trialDaysRemaining\":null}");
        } };
        var status = await new MagicCodeAuthClient(stub.Client(), Base).RefreshSubscriptionStatusAsync("my-token");
        Assert.Equal(SubscriptionStatusValue.Active, status.Status);
        Assert.Equal("Pro", status.PlanName);
    }

    [Fact]
    public async Task Errors_MapTo_RateLimited_And_Server()
    {
        var stub = new StubHandler { Handler = (_, _) => ((HttpStatusCode)429, "{\"error\":\"slow down\",\"retry_after_seconds\":120}") };
        var client = new MagicCodeAuthClient(stub.Client(), Base);
        var rate = await Assert.ThrowsAsync<AuthException>(() => client.RequestMagicCodeAsync("u@x.com"));
        Assert.Equal(AuthException.Kind.RateLimited, rate.ErrorKind);
        Assert.Equal(120, rate.RetryAfterSeconds);

        stub.Handler = (_, _) => (HttpStatusCode.InternalServerError, "{\"error\":\"oops\"}");
        var server = await Assert.ThrowsAsync<AuthException>(() => client.RequestMagicCodeAsync("u@x.com"));
        Assert.Equal(500, server.StatusCode);
        Assert.Equal("oops", server.Message);
    }

    [Fact]
    public async Task MissingBaseUrl_Throws()
    {
        var client = new MagicCodeAuthClient(new StubHandler().Client(), null);
        var e = await Assert.ThrowsAsync<AuthException>(() => client.RequestMagicCodeAsync("u@x.com"));
        Assert.Equal(AuthException.Kind.MissingBaseUrl, e.ErrorKind);
    }
}

public class CtrlVCloudProviderTests
{
    private static readonly Uri Endpoint = new("https://example.com/translate");

    [Fact]
    public async Task Translate_SendsInstallIdSessionTokenAndPlatform()
    {
        var stub = new StubHandler { Handler = (_, _) => (HttpStatusCode.OK, "{\"translatedText\":\"Hola\",\"model\":\"x\",\"plan\":\"trial\"}") };
        var provider = new CtrlVCloudProvider(stub.Client(), Endpoint, "install-1", () => "session-abc");

        var result = await provider.TranslateAsync("Hello", "Translate to Spanish");

        Assert.Equal("Hola", result);
        var root = JsonDocument.Parse(stub.Requests[0].Body).RootElement;
        Assert.Equal("install-1", root.GetProperty("installID").GetString());
        Assert.Equal("session-abc", root.GetProperty("sessionToken").GetString());
        Assert.Equal("windows", root.GetProperty("platform").GetString());
        Assert.False(root.GetProperty("warmupOnly").GetBoolean());
    }

    [Fact]
    public async Task Translate_OmitsSessionToken_WhenAbsent_And_Maps429()
    {
        var stub = new StubHandler { Handler = (_, _) => (HttpStatusCode.OK, "{\"translatedText\":\"Hola\",\"model\":\"x\",\"plan\":\"trial\"}") };
        var provider = new CtrlVCloudProvider(stub.Client(), Endpoint, "install-1", () => null);
        await provider.TranslateAsync("Hello", "p");
        Assert.False(JsonDocument.Parse(stub.Requests[0].Body).RootElement.TryGetProperty("sessionToken", out _));

        stub.Handler = (_, _) => ((HttpStatusCode)429, "{\"error\":\"rate limited\",\"retry_after_seconds\":42}");
        var e = await Assert.ThrowsAsync<TranslationException>(() => provider.TranslateAsync("Hello", "p"));
        Assert.Equal(TranslationException.Kind.RateLimited, e.ErrorKind);
        Assert.Equal(42, e.RetryAfterSeconds);
    }
}

public class FeedbackClientTests
{
    [Fact]
    public async Task Submit_PostsFullPayload()
    {
        var stub = new StubHandler { Handler = (_, _) => (HttpStatusCode.OK, "{\"ok\":true,\"emailed\":true}") };
        var client = new FeedbackClient(stub.Client(), new Uri("https://api.example.com/"));

        await client.SubmitAsync(new FeedbackSubmission { Rating = 4, Category = FeedbackCategory.Idea.RawValue(), Message = "Add Portuguese slang", InstallId = "install-1", SessionToken = "tok", AppVersion = "1.0.0" });

        var (request, body) = Assert.Single(stub.Requests);
        Assert.Equal("/submit-feedback", request.RequestUri!.AbsolutePath);
        var root = JsonDocument.Parse(body).RootElement;
        Assert.Equal(4, root.GetProperty("rating").GetInt32());
        Assert.Equal("idea", root.GetProperty("category").GetString());
        Assert.Equal("windows", root.GetProperty("platform").GetString());
    }

    [Fact]
    public void Tracker_InvitesOnce_AfterThreshold()
    {
        var tracker = new FeedbackPromptTracker(new InMemoryKeyValueStore());
        for (var i = 0; i < FeedbackPromptTracker.InviteThreshold - 1; i++) tracker.RecordTranslation();
        Assert.False(tracker.ShouldInvite);
        tracker.RecordTranslation();
        Assert.True(tracker.ShouldInvite);
        tracker.MarkDismissed();
        Assert.False(tracker.ShouldInvite);
    }
}
