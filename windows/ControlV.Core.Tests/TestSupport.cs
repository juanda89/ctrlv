using System.Net;
using System.Text;
using ControlV.Core;
using ControlV.Core.Models;

namespace ControlV.Core.Tests;

/// Scripted HttpMessageHandler: the test decides the response per request and
/// can inspect what was sent (like the URLProtocol stubs in the Swift tests).
public sealed class StubHandler : HttpMessageHandler
{
    public Func<HttpRequestMessage, string, (HttpStatusCode Status, string Json)> Handler { get; set; } = (_, _) => (HttpStatusCode.OK, "{}");
    public List<(HttpRequestMessage Request, string Body)> Requests { get; } = new();

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
    {
        var body = request.Content is null ? "" : await request.Content.ReadAsStringAsync(ct);
        Requests.Add((request, body));
        var (status, json) = Handler(request, body);
        return new HttpResponseMessage(status) { Content = new StringContent(json, Encoding.UTF8, "application/json") };
    }

    public HttpClient Client() => new(this);
}

public sealed class MockAuthClient : IMagicCodeAuthClient
{
    public List<string> RequestedEmails { get; } = new();
    public Func<string> VerifyResult { get; set; } = () => "token-xyz";
    public Func<SubscriptionStatus> StatusResult { get; set; } = () => new SubscriptionStatus(SubscriptionStatusValue.Active, "Pro", null);
    public Exception? StatusError { get; set; }

    public Task RequestMagicCodeAsync(string email, CancellationToken ct = default) { RequestedEmails.Add(email); return Task.CompletedTask; }
    public Task<string> VerifyMagicCodeAsync(string email, string code, CancellationToken ct = default) => Task.FromResult(VerifyResult());
    public Task<SubscriptionStatus> RefreshSubscriptionStatusAsync(string token, CancellationToken ct = default) =>
        StatusError is null ? Task.FromResult(StatusResult()) : Task.FromException<SubscriptionStatus>(StatusError);
    public Task<Uri> CreateCheckoutSessionAsync(string token, CancellationToken ct = default) => Task.FromResult(new Uri("https://checkout.stripe.com/abc"));
    public Task<Uri> CreatePortalSessionAsync(string token, CancellationToken ct = default) => Task.FromResult(new Uri("https://billing.stripe.com/abc"));
}
